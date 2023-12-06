# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[macros, os, json, strutils, base64, tables]
import pkg/[checksums/md5, supersnappy, flatty]

export getProjectPath

from ./ast import Ast

when defined timStandalone:
  type Globals* = ref object of RootObj

type
  TimTemplateType* = enum
    ttLayout = "layouts"
    ttView = "views"
    ttPartial = "partials"

  TemplateSourcePaths = tuple[src, ast, html: string]
  TimTemplate* = ref object
    # ast*: Ast
    templateId: string
    jit: bool
    templateName: string
    case templateType: TimTemplateType
    of ttPartial:
      discard
    of ttLayout:
      viewIndent: uint
    else: discard
    sources*: TemplateSourcePaths

  TemplateTable = TableRef[string, TimTemplate]

  TimCallback* = proc() {.nimcall, gcsafe.}
  Tim* = ref object
    base, src, output: string
    minify: bool
    indentSize: int
    layouts, views, partials: TemplateTable = TemplateTable()
    errors*: seq[string]
    # sources: tuple[
    #   layoutsPath = "layouts",
    #   viewsPath = "views",
    #   partialsPath = "partials"
    # ]
    when defined timStandalone:
      globals: Globals
    else:
      globals: JsonNode = newJObject()
      # imports: TableRef[string, ImportFunction]

  TimError* = object of CatchableError

proc getPath(engine: Tim, key: string, templateType: TimTemplateType): string =
  ## Retrieve path key for either a partial, view or layout
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

proc hashid(path: string): string =
  # Creates an MD5 hashed version of `path`
  result = getMD5(path)

proc getHtmlPath(engine: Tim, path: string): string =
  engine.output / "html" / hashid(path) & ".html"

proc getAstPath(engine: Tim, path: string): string =
  engine.output / "ast" / hashid(path) & ".ast"

proc getHtmlStoragePath*(engine: Tim): string =
  ## Returns the `html` directory path used for
  ## storing static HTML files
  result = engine.output / "html"

proc getAstStoragePath*(engine: Tim): string =
  ## Returns the `ast` directory path used for
  ## storing binary AST files.
  result = engine.output / "ast"

#
# TimTemplate API
#
proc newTemplate(id: string, templateType: TimTemplateType,
    sources: TemplateSourcePaths): TimTemplate =
  TimTemplate(templateId: id, templateType: templateType, sources: sources)

proc getType*(t: TimTemplate): TimTemplateType =
  t.templateType

proc getHash*(t: TimTemplate): string =
  hashid(t.sources.src)

proc getName*(t: TimTemplate): string =
  t.templateName

proc getTemplateId*(t: TimTemplate): string =
  t.templateId

proc setViewIndent*(t: TimTemplate, i: uint) =
  assert t.templateType == ttLayout
  t.viewIndent = i

proc getViewIndent*(t: TimTemplate): uint =
  assert t.templateType == ttLayout
  t.viewIndent

proc writeHtml*(engine: Tim, tpl: TimTemplate, htmlCode: string) =
  ## Writes `htmlCode` on disk using `tpl` info
  writeFile(tpl.sources.html, htmlCode)

proc writeHtmlTail*(engine: Tim, tpl: TimTemplate, htmlCode: string) =
  ## Writes `htmlCode` tails on disk using `tpl` info
  writeFile(tpl.sources.html.changeFileExt("tail"), htmlCode)

proc writeAst*(engine: Tim, tpl: TimTemplate, astCode: Ast) =
  ## Writes `astCode` on disk using `tpl` info
  writeFile(tpl.sources.ast, supersnappy.compress(flatty.toFlatty(astCode)))

proc readAst*(engine: Tim, tpl: TimTemplate): Ast = 
  ## Get `AST` of `tpl` TimTemplate from storage
  try:
    let binAst = readFile(tpl.sources.ast)
    result = flatty.fromFlatty(supersnappy.uncompress(binAst), Ast)
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

iterator getViews*(engine: Tim): TimTemplate =
  for id, tpl in engine.views:
    yield tpl

iterator getLayouts*(engine: Tim): TimTemplate =
  for id, tpl in engine.layouts:
    yield tpl

#
# Tim Engine API
#

proc getTemplateByPath*(engine: Tim, path: string): TimTemplate =
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
    result = newTemplate(id, ttLayout, sources)
  elif engine.src / $ttView in path:
    result = newTemplate(id, ttView, sources)
  elif engine.src / $ttPartial in path:
    result = newTemplate(id, ttPartial, sources)

proc hasLayout*(engine: Tim, key: string): bool =
  ## Determine if `key` exists in `layouts` table
  result = engine.layouts.hasKey(engine.getPath(key, ttLayout))

proc getLayout*(engine: Tim, key: string): TimTemplate =
  ## Returns a `TimTemplate` layout with `layoutName`
  result = engine.layouts[engine.getPath(key, ttLayout)]

proc hasView*(engine: Tim, key: string): bool =
  ## Determine if `key` exists in `views` table
  result = engine.views.hasKey(engine.getPath(key, ttView))

proc getView*(engine: Tim, key: string): TimTemplate =
  ## Returns a `TimTemplate` view with `key`
  result = engine.views[engine.getPath(key, ttView)]

proc newTim*(src, output, basepath: string,
    minify = true, indent = 2): Tim =
  ## Initializes `Tim` engine
  var basepath =
    if basepath.fileExists:
      basepath.parentDir # if comes from `currentSourcePath()`
    else:
      if not basepath.dirExists:
        raise newException(TimError,
          "Invalid basepath directory")
      basepath
  if src.isAbsolute or output.isAbsolute:
    raise newException(TimError,
      "Expecting a relative path for `src` and `output`")
  result =
    Tim(
      src: normalizedPath(basepath / src),
      output: normalizedPath(basepath / output),
      base: basepath,
      minify: minify,
      indentSize: indent
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

  discard existsOrCreateDir(result.output / "ast")
  discard existsOrCreateDir(result.output / "html")

proc isMinified*(engine: Tim): bool =
  result = engine.minify

proc getIndentSize*(engine: Tim): int =
  result = engine.indentSize

proc flush*(engine: Tim) =
  ## Flush precompiled files
  for f in walkDir(engine.getAstStoragePath):
    if f.path.endsWith(".ast"):
      f.path.removeFile()

  for f in walkDir(engine.getHtmlStoragePath):
    if f.path.endsWith(".html"):
      f.path.removeFile()

proc getSourcePath*(engine: Tim): string =
  result = engine.src