# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[macros, os, json,
  strutils, sequtils, base64, tables]
import pkg/[checksums/md5, flatty]

export getProjectPath

from ./ast import Ast

when defined timStandalone:
  type Globals* = ref object of RootObj

type
  TimTemplateType* = enum
    ttInvalid
    ttLayout = "layouts"
    ttView = "views"
    ttPartial = "partials"

  TemplateSourcePaths = tuple[src, ast, html: string]
  TimTemplate* = ref object
    jit, inUse: bool
    templateId: string
    templateName: string
    case templateType: TimTemplateType
    of ttPartial:
      discard
    of ttLayout:
      viewIndent: uint
    else: discard
    sources*: TemplateSourcePaths
    dependents: Table[string, string]

  TemplateTable = TableRef[string, TimTemplate]

  TimCallback* = proc() {.nimcall, gcsafe.}

  TimPolicy* = ref object
    # todo

  TimEngine* = ref object
    base, src, output: string
    minify, htmlErrors: bool
    indentSize: int
    layouts, views, partials: TemplateTable = TemplateTable()
    errors*: seq[string]
    placeholders: Table[string, seq[Ast]]
      ## A table containing available placeholders
    policy: TimPolicy
    when defined timStandalone:
      globals: Globals
    else:
      globals: JsonNode = newJObject()

  TimError* = object of CatchableError

#
# Placeholders API
#
proc addPlaceholder*(engine: TimEngine,
    k: string, snippetTree: Ast)  =
  if engine.placeholders.hasKey(k):
    engine.placeholders[k].add(snippetTree)
  else:
    engine.placeholders[k] = @[snippetTree]

proc hasPlaceholder*(engine: TimEngine, k: string): bool =
  result = engine.placeholders.hasKey(k)

iterator listPlaceholders*(engine: TimEngine): (string, seq[Ast]) =
  for k, v in engine.placeholders.mpairs:
    yield (k, v)

iterator snippets*(engine: TimEngine, k: string): Ast =
  for x in engine.placeholders[k]:
    yield x

proc deleteSnippet*(engine: TimEngine, k: string, i: int) =
    engine.placeholders[k].del(i)

proc getPath*(engine: TimEngine, key: string, templateType: TimTemplateType): string =
  ## Get absolute path of `key` view, partial or layout
  var k: string
  var tree: seq[string]
  result = engine.src & "/" & $templateType & "/$1"
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

proc setGlobalData*(engine: TimEngine, data: JsonNode) =
  engine.globals = data

proc getGlobalData*(engine: TimEngine): JsonNode =
  engine.globals

proc hashid(path: string): string =
  # Creates an MD5 hashed version of `path`
  result = getMD5(path)

proc getHtmlPath(engine: TimEngine, path: string): string =
  engine.output / "html" / hashid(path) & ".html"

proc getAstPath(engine: TimEngine, path: string): string =
  engine.output / "ast" / hashid(path) & ".ast"

proc getHtmlStoragePath*(engine: TimEngine): string =
  ## Returns the `html` directory path used for
  ## storing static HTML files
  result = engine.output / "html"

proc getAstStoragePath*(engine: TimEngine): string =
  ## Returns the `ast` directory path used for
  ## storing binary AST files.
  result = engine.output / "ast"

#
# TimTemplate API
#
proc newTemplate(id: string, tplType: TimTemplateType,
    sources: TemplateSourcePaths): TimTemplate =
  TimTemplate(
    templateId: id,
    templateType: tplType,
    templateName: sources.src.extractFilename,
    sources: sources
  )

proc getType*(t: TimTemplate): TimTemplateType =
  ## Get template type of `t`
  t.templateType

proc getHash*(t: TimTemplate): string =
  ## Returns the hashed path of `t`
  hashid(t.sources.src)

proc getName*(t: TimTemplate): string =
  ## Get template name of `t`
  t.templateName

proc getTemplateId*(t: TimTemplate): string =
  ## Get template id of `t`
  t.templateId

proc setViewIndent*(t: TimTemplate, i: uint) =
  assert t.templateType == ttLayout
  t.viewIndent = i

proc getViewIndent*(t: TimTemplate): uint =
  assert t.templateType == ttLayout
  t.viewIndent

proc hasDep*(t: TimTemplate, path: string): bool =
  t.dependents.hasKey(path)

proc addDep*(t: TimTemplate, path: string) =
  ## Add a new dependent
  t.dependents[path] = path

proc getDeps*(t: TimTemplate): seq[string] =
  t.dependents.keys.toSeq()

proc writeHtml*(engine: TimEngine, tpl: TimTemplate, htmlCode: string) =
  ## Writes `htmlCode` on disk using `tpl` info
  writeFile(tpl.sources.html, htmlCode)

proc writeHtmlTail*(engine: TimEngine, tpl: TimTemplate, htmlCode: string) =
  ## Writes `htmlCode` tails on disk using `tpl` info
  writeFile(tpl.sources.html.changeFileExt("tail"), htmlCode)

proc writeAst*(engine: TimEngine, tpl: TimTemplate, astCode: Ast) =
  ## Writes `astCode` on disk using `tpl` info
  writeFile(tpl.sources.ast, flatty.toFlatty(astCode))

proc readAst*(engine: TimEngine, tpl: TimTemplate): Ast = 
  ## Get `AST` of `tpl` TimTemplate from storage
  try:
    let binAst = readFile(tpl.sources.ast)
    result = flatty.fromFlatty(binAst, Ast)
  except IOError:
    discard

proc getSourcePath*(t: TimTemplate): string =
  ## Returns the absolute source path of `t` TimTemplate
  result = t.sources.src

proc getAstPath*(t: TimTemplate): string =
  ## Returns the absolute `html` path of `t` TimTemplate
  result = t.sources.ast

proc getHtmlPath*(t: TimTemplate): string =
  ## Returns the absolute `ast` path of `t` TimTemplate 
  result = t.sources.html

proc jitEnable*(t: TimTemplate) =
  if not t.jit: t.jit = true

proc jitEnabled*(t: TimTemplate): bool = t.jit

proc getHtml*(t: TimTemplate): string =
  ## Returns precompiled static HTML of `t` TimTemplate
  try:
    result = readFile(t.getHtmlPath)
  except IOError:
    result = ""

proc getTail*(t: TimTemplate): string =
  ## Returns the tail of a split layout
  result = readFile(t.getHtmlPath.changeFileExt("tail"))

iterator getViews*(engine: TimEngine): TimTemplate =
  for id, tpl in engine.views:
    yield tpl

iterator getLayouts*(engine: TimEngine): TimTemplate =
  for id, tpl in engine.layouts:
    yield tpl

#
# TimEngine Engine API
#

proc getTemplateByPath*(engine: TimEngine, path: string): TimTemplate =
  ## Search for `path` in `layouts` or `views` table
  let id = hashid(path) # todo extract parent dir from path?
  if engine.views.hasKey(path):
    return engine.views[path]
  if engine.layouts.hasKey(path):
    return engine.layouts[path]
  if engine.partials.hasKey(path):
    return engine.partials[path]
  let
    astPath = engine.output / "ast" / id & ".ast"
    htmlPath = engine.output / "html" / id & ".html"
    sources = (src: path, ast: astPath, html: htmlPath)
  if engine.src / $ttLayout in path:
    engine.layouts[path] = newTemplate(id, ttLayout, sources)
    return engine.layouts[path]
  if engine.src / $ttView in path:
    engine.views[path] = newTemplate(id, ttView, sources)
    return engine.views[path]
  if engine.src / $ttPartial in path:
    engine.partials[path] = newTemplate(id, ttPartial, sources)
    return engine.partials[path]

proc hasLayout*(engine: TimEngine, key: string): bool =
  ## Determine if `key` exists in `layouts` table
  result = engine.layouts.hasKey(engine.getPath(key, ttLayout))

proc getLayout*(engine: TimEngine, key: string): TimTemplate =
  ## Get a `TimTemplate` from `layouts` by `key`
  result = engine.layouts[engine.getPath(key, ttLayout)]
  result.inUse = true

proc hasView*(engine: TimEngine, key: string): bool =
  ## Determine if `key` exists in `views` table
  result = engine.views.hasKey(engine.getPath(key, ttView))

proc getView*(engine: TimEngine, key: string): TimTemplate =
  ## Get a `TimTemplate` from `views` by `key`
  result = engine.views[engine.getPath(key, ttView)]
  result.inUse = true

proc getTemplatePath*(engine: TimEngine, path: string): string =
  path.replace(engine.base, "")

proc isUsed*(t: TimTemplate): bool = t.inUse
proc showHtmlErrors*(engine: TimEngine): bool = engine.htmlErrors

proc newTim*(src, output, basepath: string, minify = true,
    indent = 2, showHtmlError = false): TimEngine =
  ## Initializes `TimEngine` engine
  var basepath =
    if basepath.fileExists:
      basepath.parentDir # if comes from `currentSourcePath()`
    else:
      if not basepath.dirExists:
        raise newException(TimError, "Invalid basepath directory")
      basepath
  if src.isAbsolute or output.isAbsolute:
    raise newException(TimError,
      "Expecting a relative path for `src` and `output`")
  result =
    TimEngine(
      src: normalizedPath(basepath / src),
      output: normalizedPath(basepath / output),
      base: basepath,
      minify: minify,
      indentSize: indent,
      htmlErrors: showHtmlError
    )

  for sourceDir in [ttLayout, ttView, ttPartial]:
    if not dirExists(result.src / $sourceDir):
      raise newException(TimError, "Missing $1 directory: \n$2" % [$sourceDir, result.src / $sourceDir])
    for fpath in walkDirRec(result.src / $sourceDir):
      let
        id = hashid(fpath)
        astPath = result.output / "ast" / id & ".ast"
        htmlPath = result.output / "html" / id & ".html"
        sources = (src: fpath, ast: astPath, html: htmlPath)
      case sourceDir:
      of ttLayout:
        result.layouts[fpath] = id.newTemplate(ttLayout, sources)
      of ttView:
        result.views[fpath] = id.newTemplate(ttView, sources)
      of ttPartial:
        result.partials[fpath] = id.newTemplate(ttPartial, sources)
      else: discard

  discard existsOrCreateDir(result.output / "ast")
  discard existsOrCreateDir(result.output / "html")

proc isMinified*(engine: TimEngine): bool =
  result = engine.minify

proc getIndentSize*(engine: TimEngine): int =
  result = engine.indentSize

proc flush*(engine: TimEngine) =
  ## Flush precompiled files
  for f in walkDir(engine.getAstStoragePath):
    if f.path.endsWith(".ast"):
      f.path.removeFile()

  for f in walkDir(engine.getHtmlStoragePath):
    if f.path.endsWith(".html"):
      f.path.removeFile()

proc getSourcePath*(engine: TimEngine): string =
  result = engine.src

proc getTemplateType*(engine: TimEngine, path: string): TimTemplateType =
  ## Returns `TimTemplateType` by `path`
  let basepath = engine.getSourcePath()
  for xdir in ["layouts", "views", "partials"]:
    if path.startsWith(basepath / xdir):
      return parseEnum[TimTemplateType](xdir)

proc clearTemplateByPath*(engine: TimEngine, path: string) =
  ## Clear a template from `TemplateTable` by `path`
  case engine.getTemplateType(path):
  of ttLayout:
    engine.layouts.del(path)
  of ttView:
    engine.views.del(path)
  of ttPartial:
    engine.partials.del(path)
  else: discard