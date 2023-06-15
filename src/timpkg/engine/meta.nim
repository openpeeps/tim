# A high-performance compiled template engine
# inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import ./ast
import pkg/pkginfo
import pkg/[msgpack4nim, msgpack4nim/msgpack4collection]
import std/[tables, md5, times, json, os, strutils, macros]
from std/math import sgn

when defined timEngineStandalone:
  type Globals* = ref object of RootObj

type 
  TemplateType* = enum
    Layout  = "layout"
    View    = "view"
    Partial = "partial"

  Template* = ref object
    id: string
    jit: bool
    case `type`: TemplateType
    of Partial:
      dependents: seq[string]                ## a sequence containing all views that include this partial
    of Layout:
      placeholderIndent: int
    else: discard
    astSource*: string
    paths: tuple[file, ast, html, tails: string]
    meta: tuple[name: string, templateType: TemplateType]
      ## name of the current Template representing file name
      ## type of Template, either Layout, View or Partial

  TemplatesTable = OrderedTableRef[string, Template]

  HotReloadType* = enum
    None, HttpReloader, WsReloader
  
  NKind* = enum
    nkBool
    nkInt
    nkFloat
    nkString

  ImportFunction* = ref object
    paramCount*: int
    case nKind: NKind 
    of nkInt:
      intFn*: proc(params: seq[string]): int
    of nkString:
      strFn*: proc(params: seq[string]): string
    of nkBool:
      boolFn*: proc(params: seq[string]): bool
    of nkFloat:
      floatFn*: proc(params: seq[string]): float

  TimEngine* = ref object
    when defined timEngineStandalone:
      globalData: Globals
    else:
      globalData: JsonNode
      imports*: TableRef[string, ImportFunction]
    root: string
    output: string
    layouts, views, partials: TemplatesTable
    minified: bool
    indent: int
    paths: tuple[layouts, views, partials: string]
    reloader: HotReloadType
    errors*: seq[string]

  SyntaxError* = object of CatchableError      # raise errors from Tim language
  TimDefect* = object of CatchableError
  TimParsingError* = object of CatchableError

const currentVersion = "0.1.0" # todo use pkginfo to extract the current version from .nimble

proc getIndent*(t: TimEngine): int = 
  ## Get preferred indentation size (2 or 4 spaces). Default 4
  result = t.indent

proc getType*(t: Template): TemplateType =
  result = t.meta.templateType

proc getName*(t: Template): string =
  ## Retrieve the file name (including extension)
  # of the current Template
  result = t.meta.name

proc getTemplateId*(t: Template): string =
  result = t.id

proc setPlaceholderIndent*(t: var Template, pos: int) =
  t.placeholderIndent = pos

proc setPlaceHolderId*(t: var Template, pos: int): string =
  t.setPlaceholderIndent pos
  result = "$viewHandle_" & t.id & ""

proc getPlaceholderId*(t: Template): string =
  result = "viewHandle_" & t.id & ""

proc getPlaceholderIndent*(t: var Template): int =
  result = t.placeholderIndent

proc enableJIT*(t: Template) =
  t.jit = true

proc isJitEnabled*(t: Template): bool =
  result = t.jit

proc isModified*(t: Template): bool =
  let srcModified = t.paths.file.getLastModificationTime
  let astExists = fileExists(t.paths.ast)
  let htmlExists = fileExists(t.paths.html)
  if astExists and htmlExists == false:
    let astModified = t.paths.ast.getLastModificationTime
    result = srcModified > astModified
    t.jit = true
  elif astExists and htmlExists:
    let astModified = t.paths.ast.getLastModificationTime
    let htmlModified = t.paths.html.getLastModificationTime
    if astModified > htmlModified:
      result = srcModified > astModified
      t.jit = true
    else:
      result = srcModified > htmlModified
  elif htmlExists and astExists == false:
    let htmlModified = t.paths.html.getLastModificationTime
    result = srcModified > htmlModified
  else: result = true # new file

proc getPathDir*(engine: TimEngine, key: string): string =
  if key == "layouts":
    result = engine.paths.layouts
  elif key == "views":
    result = engine.paths.views
  else:
    result = engine.paths.partials

proc isPartial*(t: Template): bool =
  ## Determine if current template is a `partial`
  result = t.`type` == Partial

proc addDependentView*(t: var Template, path: string) =
  ## Add dependent templates. Used to auto-recompile
  ## templates and dependencies.
  if path notin t.dependents:
    add t.dependents, path

proc getDependentViews*(t: var Template): seq[string] =
  ## Retrieve all views included in current partial.
  result = t.dependents

proc getFilePath*(t: Template): string =
  ## Retrieve the file path of the current Template
  result = t.paths.file

proc getSourceCode*(t: Template): string =
  ## Retrieve source code of a Template object
  result = readFile(t.paths.file)

proc getHtmlCode*(t: Template): string =
  ## Retrieve the HTML code for given ``Template`` object
  ## TODO retrieve source code from built-in memory table
  result = readFile(t.paths.html)

proc templatesExists*(e: TimEngine): bool =
  ## Check for available templates in `layouts` and `views
  result = len(e.views) != 0 or len(e.layouts) != 0

proc setData*(t: var TimEngine, data: JsonNode) =
  ## Add global data that can be accessed across templates
  t.globalData = data

proc globalDataExists*(t: TimEngine): bool =
  ## Determine if global data is available
  if t.globalData != nil:
    result = t.globalData.kind != JNull

proc getGlobalData*(t: TimEngine): JsonNode =
  ## Retrieves global data
  result = t.globalData

proc merge*(data: JsonNode, key: string, mainGlobals, globals: JsonNode) =
  data["globals"] = %*{}
  for k, f in mainGlobals.pairs():
    data[key][k] = f
  for k, f in globals.pairs():
    data[key][k] = f

proc getPath(e: TimEngine, key, pathType: string): string =
  ## Retrieve path key for either a partial, view or layout
  var k: string
  var tree: seq[string]
  result = e.root & "/" & pathType & "/$1"
  if key.endsWith(".timl"):
    k = key[0 .. ^6]
  else:
    k = key
  if key.contains("."):
    tree = k.split(".")
    result = result % [tree.join("/")]
  else:
    result = result % [k]
  result &= ".timl"
  result = normalizedPath(result) # normalize path for Windows

proc getLayouts*(e: TimEngine): TemplatesTable =
  ## Retrieve entire table of layouts as TemplatesTable
  result = e.layouts

proc hasLayout*(e: TimEngine, key: string): bool =
  ## Determine if specified layout exists
  ## Use dot annotation for accessing views in subdirectories
  result = e.layouts.hasKey(e.getPath(key, "layouts"))

proc getLayout*(e: TimEngine, key: string): Template =
  ## Get a layout object as ``Template``
  ## Use dot annotation for accessing views in subdirectories
  result = e.layouts[e.getPath(key, "layouts")]

proc getViews*(e: TimEngine): TemplatesTable =
  ## Retrieve entire table of views as TemplatesTable
  result = e.views

proc hasView*(e: TimEngine, key: string): bool =
  ## Determine if a specific view exists by name.
  ## Use dot annotation for accessing views in subdirectories
  result = e.views.hasKey(e.getPath(key, "views"))

proc getView*(e: TimEngine, key: string): Template =
  ## Retrieve a view template by key.
  ## Use dot annotation for accessing views in subdirectories
  result = e.views[e.getPath(key, "views")]

proc hasPartial*(e: TimEngine, key: string): bool =
  ## Determine if a specific view exists by name.
  ## Use dot annotation for accessing views in subdirectories
  result = e.partials.hasKey(e.getPath(key, "partials"))

proc getPartials*(e: TimEngine): TemplatesTable =
  ## Retrieve entire table of partials as TemplatesTable
  result = e.partials

proc getStoragePath*(e: TimEngine): string =
  ## Retrieve the absolute path of TimEngine output directory
  result = e.output

proc getBsonPath*(e: Template): string = 
  ## Get the absolute path of BSON AST file
  result = e.paths.ast

proc shouldMinify*(e: TimEngine): bool =
  ## Determine if Tim Engine should minify the final HTML
  result = e.minified

proc hashName(input: string): string =
  ## Create a MD5 hashed version of given input string
  result = getMD5(input)

proc astPath(outputDir, filePath: string): string =
  ## Set the BSON AST path and return the string
  result = outputDir & "/ast/" & hashName(filePath) & ".ast"
  normalizePath(result)

proc htmlPath(outputDir, filePath: string, isTail = false): string =
  ## Set the HTML output path and return the string
  var suffix = if isTail: "_" else: ""
  result = outputDir & "/html/" & hashName(filePath) & suffix & ".html"
  normalizePath(result)

proc getTemplateByPath*(engine: TimEngine, filePath: string): var Template =
  ## Return `Template` object representation for given file `filePath`
  let fp = normalizedPath(filePath)
  if engine.views.hasKey(fp):
    result = engine.views[fp]
  elif engine.layouts.hasKey(fp):
    result = engine.layouts[fp]
  else:
    result = engine.partials[fp]

proc writeAst*(e: TimEngine, t: Template, ast: Program, baseIndent: int) =
  var s = MsgStream.init()
  s.pack(ast)
  s.pack_bin(sizeof(ast))
  try:
    writeFile(t.paths.ast, s.data)
  except IOError:
    e.errors.add "Could not build AST for $1" % [t.meta.name]

proc checkDocVersion(docVersion: string): bool =
  let docv = parseInt replace(docVersion, ".", "")
  let currv = parseInt replace(currentVersion, ".", "")
  result = sgn(docv - currv) != -1

proc getReloadType*(engine: TimEngine): HotReloadType =
  result = engine.reloader

proc readAst*(e: TimEngine, t: Template): Program =
  ## Unpack binary AST and return the `Program`
  var astProgram: Program
  unpack(readFile(t.paths.ast), astProgram)
  result = astProgram

proc writeHtml*(e: TimEngine, t: Template, output: string, isTail = false) =
  ## Write HTML file to disk
  let filePath =
    if not isTail: t.paths.html
    else: t.paths.tails
  discard existsOrCreateDir(e.getStoragePath() / "html") # create `html` directory
  writeFile(filePath, output)

proc flush*(tempDir: string) =
  ## Flush specific directory
  ## todo to flush only known directories
  removeDir(tempDir)

proc finder(files: var seq[string], path="") =
  for file in walkDirRec path:
    if file.isHidden: continue
    if file.endsWith ".timl":
      add files, file

macro getAbsolutePath(path: string): untyped =
  result = newStmtList()
  let abspath = getProjectPath()
  result.add quote do:
    if isAbsolute(`path`):
      `path`
    else:
      `abspath` / `path`

proc newTemplate(basePath, filePath, fileName: string, templateType: TemplateType): Template =
  result = Template(id: hashName(filePath), `type`: templateType,
                    meta: (name: fileName, templateType: templateType),
                    paths: (
                      file: filePath,
                      ast: astPath(basePath, filePath),
                      html: htmlPath(basePath, filePath),
                      tails: htmlPath(basePath, filePath, true)
                    )
                  )

proc init*(timEngine: var TimEngine, source, output: string,
      indent: int, minified = true, reloader: HotReloadType = None) =
  ## Initialize a new Tim Engine providing the source path 
  ## to your templates (layouts, views and partials) and output directory,
  ## where will save the compiled templates.
  let
    srcDirPath = getAbsolutePath(source.normalizedPath())
    outputDirPath = getAbsolutePath(output.normalizedPath())
  # for path in @[source, output]:
  discard existsOrCreateDir(srcDirPath)
  discard existsOrCreateDir(outputDirPath)
  discard existsOrCreateDir(outputDirPath / "ast")
  discard existsOrCreateDir(outputDirPath / "html")
  var layoutsTable, viewsTable, partialsTable = TemplatesTable()
  for tdir in @["views", "layouts", "partials"]:
    if not dirExists(srcDirPath / tdir):
      createDir(srcDirPath / tdir)
    else:
      var files: seq[string]
      files.finder(path = srcDirPath / tdir)
      for f in files:
        let fname = splitPath(f)
        let filePath = f.normalizedPath
        case tdir:
        of "layouts":
          layoutsTable[filePath] = newTemplate(outputDirPath, filePath, fname.tail, Layout)
        of "views":
          viewsTable[filePath] = newTemplate(outputDirPath, filePath, fname.tail, View)
        of "partials":
          partialsTable[filePath] = newTemplate(outputDirPath, filePath, fname.tail, Partial)

  timEngine = TimEngine(
    root: srcDirPath,
    output: outputDirPath,
    layouts: layoutsTable,
    views: viewsTable,
    partials: partialsTable,
    minified: minified,
    indent: indent,
    paths: (
      layouts: srcDirPath / "layouts",
      views: srcDirPath / "views",
      partials: srcDirPath / "partials"
    )
  )
  when not defined release:
    # enable in-browser auto refresh
    timEngine.reloader = reloader

when not defined timEngineStandalone:
  var
    stdlibs {.compileTime.} = nnkBracket.newTree()
    pkglibs {.compileTime.} = nnkBracket.newTree()
    stdlibsChecker {.compileTime.}: seq[string]
    pkglibsChecker {.compileTime.}: seq[string]
    functions {.compileTime.}: seq[
      tuple[
        prefix, ident: string,
        params: JsonNode,
        toString: bool,
        returnType: NKind,
        paramCount: int
      ]
    ]

  macro init*(timEngine: var TimEngine, source, output: string,
        indent: int, minified = true, reloader: HotReloadType = None,
        imports: JsonNode) =
    result = newStmtList()
    var hasImports: bool
    for imports in parseJSON(imports[1].strVal):
      for pkgIdent, procs in pairs(imports):
        if pkgIdent.startsWith("std/"):
          let lib = pkgIdent[4..^1]
          if lib notin stdlibsChecker:
            stdlibs.add(ident lib)
            stdlibsChecker.add(lib)
          else: error("$1 already imported" % [pkgIdent])
        elif pkgIdent.startsWith("pkg/"):
          let pkg = pkgIdent[4..^1]
          if pkg notin pkglibsChecker:
            pkglibs.add(ident pkg)
            pkglibsChecker.add(pkg)
          else: error("$1 already imported" % [pkgIdent])
        else: error("prefix imported modules with `std` or `pkg`")
        for p in procs:
          var
            returnType: NKind
            paramCount = p["params"].len
          let returnTypeStr = p["return"].getStr
          if returnTypeStr == "bool":
            returnType = nkBool
          elif returnTypeStr == "int":
            returnType = nkInt
          elif returnTypeStr == "string":
            returnType = nkString
          elif returnTypeStr == "float":
            returnType = nkFloat
          let toString =
            if p.hasKey("toString"):
              p["toString"].getBool == true:
            else: false
          functions.add((
            pkgIdent[4..^1],
            p["ident"].getStr,
            p["params"],
            toString,
            returnType,
            paramCount,
          ))
    if stdlibs.len != 0:
      hasImports = true
      result.add(
        nnkImportStmt.newTree(
          nnkInfix.newTree(
            ident "/",
            ident "std",
            stdlibs
          )
        )
      )
    if pkglibs.len != 0:
      hasImports = true
      result.add(
        nnkImportStmt.newTree(
          nnkInfix.newTree(
            ident "/",
            ident "pkg",
            pkglibs
          )
        )
      )
    add result, newCall(ident("init"), timEngine, source,
                      output, indent, minified, reloader)
    if hasImports:
      let initImportsTable = 
        newAssignment(
          newDotExpr(timEngine, ident("imports")),
          newCall(
            nnkBracketExpr.newTree(
              ident "newTable",
              ident "string",
              ident "ImportFunction"
            )
          )
        )
      result.add(initImportsTable)
      for fn in functions:
        var fnField, fnReturnType: string
        case fn.returnType:
        of nkInt:
          fnField = "intFn"
          fnReturnType = "int"
        of nkString:
          fnField = "strFn"
          fnReturnType = "string"
        of nkFloat:
          fnField = "floatFn"
          fnReturnType = "float"
        of nkBool:
          fnField = "boolFn"
          fnReturnType = "bool"
        
        var i = 0
        var callFn = nnkCall.newTree()
        callFn.add(ident fn.ident)
        for param in fn.params:
          callFn.add(
            nnkBracketExpr.newTree(
              ident "params",
              newLit(i)
            )
          )
          inc i
        if fn.toString:
          callFn = nnkPrefix.newTree(ident("$"), callFn)
        result.add(
          newAssignment(
            nnkBracketExpr.newTree(
              newDotExpr(
                timEngine,
                ident "imports"
              ),
              # newLit fn.prefix & "." & fn.ident
              newlit fn.ident
            ),
            nnkObjConstr.newTree(
              ident "ImportFunction",
              newColonExpr(
                ident "nKind",
                ident($fn.returnType)
              ),
              newColonExpr(
                ident "paramCount",
                newLit(fn.paramCount)
              ),
              newColonExpr(
                ident fnField,
                nnkLambda.newTree(
                  newEmptyNode(),
                  newEmptyNode(),
                  newEmptyNode(),
                  nnkFormalParams.newTree(
                    ident fnReturnType,
                    nnkIdentDefs.newTree(
                      ident "params",
                      nnkBracketExpr.newTree(
                        ident "seq",
                        ident "string"
                      ),
                      newEmptyNode()
                    )
                  ),
                  newEmptyNode(),
                  newEmptyNode(),
                  newStmtList(callFn)
                )
              )
            )
          )
        )