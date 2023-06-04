# A high-performance compiled template engine
# inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import ./ast
import pkg/pkginfo
import pkg/[msgpack4nim, msgpack4nim/msgpack4collection]
import std/[tables, md5, json, os, strutils, macros]
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
    case timlType: TemplateType
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

  TimlTemplateTable = OrderedTableRef[string, Template]

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

  # Main Tim Engine
  TimEngine* = ref object
    when defined timEngineStandalone:
      globalData: Globals
    else:
      globalData: JsonNode
      imports*: TableRef[string, ImportFunction]
    root: string
      ## root path to your Timl templates
    output: string
      ## root path for HTML and AST output
    layouts: TimlTemplateTable
      ## a table representing `.timl` layouts
    views: TimlTemplateTable
      ## a table representing `.timl` views
    partials: TimlTemplateTable
      ## a table representing `.timl` partials
    minified: bool
      ## whether it should minify the final HTML output
    indent: int
      ## the base indentation (default to 2)
    paths: tuple[layouts, views, partials: string]
    reloader: HotReloadType
    errors*: seq[string]

  SyntaxError* = object of CatchableError      # raise errors from Tim language
  TimDefect* = object of CatchableError
  TimParsingError* = object of CatchableError

const currentVersion = "0.1.0"

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

proc getPathDir*(engine: TimEngine, key: string): string =
  if key == "layouts":
    result = engine.paths.layouts
  elif key == "views":
    result = engine.paths.views
  else:
    result = engine.paths.partials

proc isPartial*(t: Template): bool =
  ## Determine if current template is a `partial`
  result = t.timlType == Partial

proc addDependentView*(t: var Template, path: string) =
  ## Add a new view that includes the current partial.
  ## This is mainly used to auto reload (recompile) views
  ## when a partial get modified
  t.dependents.add(path)

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

proc getLayouts*(e: TimEngine): TimlTemplateTable =
  ## Retrieve entire table of layouts as TimlTemplateTable
  result = e.layouts

proc hasLayout*(e: TimEngine, key: string): bool =
  ## Determine if specified layout exists
  ## Use dot annotation for accessing views in subdirectories
  result = e.layouts.hasKey(e.getPath(key, "layouts"))

proc getLayout*(e: TimEngine, key: string): Template =
  ## Get a layout object as ``Template``
  ## Use dot annotation for accessing views in subdirectories
  result = e.layouts[e.getPath(key, "layouts")]

proc getViews*(e: TimEngine): TimlTemplateTable =
  ## Retrieve entire table of views as TimlTemplateTable
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

proc getPartials*(e: TimEngine): TimlTemplateTable =
  ## Retrieve entire table of partials as TimlTemplateTable
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

# proc writeBson*(e: TimEngine, t: Template, ast: string, baseIndent: int) =
#   ## Write current JSON AST to BSON
#   var doc = newBsonDocument()
#   doc["ast"] = ast
#   doc["version"] = currentVersion
#   doc["baseIndent"] = baseIndent
#   try:
#     writeFile(t.paths.ast, doc.bytes)
#   except IOError:
#     e.errors.add "Could not write BSON file for $1" % [t.meta.name]

proc writeAst*(e: TimEngine, t: Template, ast: Program, baseIndent: int) =
  var s = MsgStream.init()
  s.pack(ast)  
  # s.pack_bin(sizeof(ast))
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

# proc readBson*(e: TimEngine, t: Template): string =
#   ## Read current BSON and parse to JSON
#   let document: Bson = newBsonDocument(readFile(t.paths.ast))
#   let docv: string = document["version"] # TODO use pkginfo to extract current version from nimble file
#   if not checkDocVersion(docv):
#     # TODO error message
#     raise newException(TimDefect,
#       "This template has been compiled with an older version ($1) of Tim Engine. Please upgrade to $2" % [docv, currentVersion])
#   result = document["ast"]

proc readAst*(e: TimEngine, t: Template): Program =
  ## Read current AST and return as `ast.Program`
  var astProgram: Program
  unpack(readFile(t.paths.ast), astProgram)
  result = astProgram
  # if not checkDocVersion(docv):
  #   # TODO error message
  #   raise newException(TimDefect,
  #     "This template has been compiled with an older version ($1) of Tim Engine. Please upgrade to $2" % [docv, currentVersion])
  # result = document["ast"]

proc writeHtml*(e: TimEngine, t: Template, output: string, isTail = false) =
  let filePath =
    if not isTail:
      t.paths.html
    else:
      t.paths.tails
  discard existsOrCreateDir(e.getStoragePath() / "html") # create `html` directory
  writeFile(filePath, output)

proc flush*(tempDir: string) =
  removeDir(tempDir)

proc finder(findArgs: seq[string] = @[], path=""): seq[string] =
  ## Recursively search for timl templates.
  var files: seq[string]
  for file in walkDirRec(path):
    if file.isHidden(): continue
    if file.endsWith(".timl"):
      files.add(file)
  result = files

macro getAbsolutePath(p: string): untyped =
  result = newStmtList()
  let ppath = getProjectPath()
  result.add quote do:
    `ppath` / `p`


proc init*(timEngine: var TimEngine, source, output: string,
      indent: int, minified = true, reloader: HotReloadType = None) =
  ## Initialize a new Tim Engine providing the source path 
  ## to your templates (layouts, views and partials) and output directory,
  ## where will save the compiled templates.
  var timlInOutDirs: seq[string]
  for path in @[source, output]:
    var tpath = getAbsolutePath(path.normalizedPath())
    if not tpath.dirExists():
      createDir(tpath)
    timlInOutDirs.add(tpath)
    if path == output:
      # create `ast` and `html` dirs inside `output` directory, where
      #
      # `ast` is used for saving the binary abstract syntax tree
      # for pages that requires dynamic computation, such as data assignation,
      # and conditional statements.
      #
      # `html` directory is reserved for saving the final HTML output.
      for inDir in @["ast", "html"]:
        # let innerDir = path & "/" & inDir
        let outputDir = getAbsolutePath(path.normalizedPath() / inDir)
        if not dirExists(outputDir):
          createDir(outputDir)
        else:
          flush(outputDir)      # flush cached files inside `html` and `ast`
          createDir(outputDir)  # then recreate directories

  var layoutsTable, viewsTable,
      partialsTable = newOrderedTable[string, Template]()
  for tdir in @["views", "layouts", "partials"]:
    var tdirpath = timlInOutDirs[0] & "/" & tdir
    if not dirExists(tdirpath):
      createDir(tdirpath)
    else:
      let files = finder(findArgs = @["-type", "f", "-print"], path = tdirpath)
      if files.len != 0:
        for f in files:
          let fname = splitPath(f)
          var filePath = f
          filePath.normalizePath()
          case tdir:
            of "layouts":
              layoutsTable[filePath] = Template(
                id: hashName(filePath),
                timlType: Layout,
                meta: (name: fname.tail, templateType: Layout),
                paths: (
                  file: filePath,
                  ast: astPath(timlInOutDirs[1], filePath),
                  html: htmlPath(timlInOutDirs[1], filePath),
                  tails: htmlPath(timlInOutDirs[1], filePath, true)
                )
              )                            
            of "views":
              viewsTable[filePath] = Template(
                id: hashName(filePath),
                timlType: View,
                meta: (name: fname.tail, templateType: View),
                paths: (
                  file: filePath,
                  ast: astPath(timlInOutDirs[1], filePath),
                  html: htmlPath(timlInOutDirs[1], filePath),
                  tails: htmlPath(timlInOutDirs[1], filePath, true)
                )
              )
            of "partials":
              partialsTable[filePath] = Template(
                id: hashName(filePath),
                timlType: Partial,
                meta: (name: fname.tail, templateType: Partial),
                paths: (
                  file: filePath,
                  ast: astPath(timlInOutDirs[1], filePath),
                  html: htmlPath(timlInOutDirs[1], filePath),
                  tails: htmlPath(timlInOutDirs[1], filePath, true)
                )
              )

  timEngine = TimEngine(
    root: timlInOutDirs[0],
    output: timlInOutDirs[1],
    layouts: layoutsTable,
    views: viewsTable,
    partials: partialsTable,
    minified: minified,
    indent: indent,
    paths: (
      layouts: timlInOutDirs[0] & "/layouts",
      views: timlInOutDirs[0] & "/views",
      partials: timlInOutDirs[0] & "/partials"
    )
  )
  when not defined release: # enable auto refresh browser for dev mode
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
    result.add(newCall(ident "init", timEngine, source, output, indent, minified, reloader))
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