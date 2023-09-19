# A blazing fast, cross-platform, multi-language
# template engine and markup language written in Nim.
#
#    Made by Humans from OpenPeeps
#    (c) George Lemon | LGPLv3 License
#    https://github.com/openpeeps/tim

import std/[macros, os, json, strutils, base64, tables]
import pkg/checksums/md5

export getProjectPath

from ./ast import Tree

when defined timStandalone:
  type Globals* = ref object of RootObj

type
  TemplateType* = enum
    ttLayout = "layouts"
    ttView = "views"
    ttPartial = "partials"

  TemplateSourcePaths = tuple[src, ast, html: string]
  Template* = ref object
    ast*: Tree
    templateId: string
    templateJit: bool
    templateName: string
    case templateType: TemplateType
    of ttPartial:
      discard
    of ttLayout:
      discard
    else: discard
    sources*: TemplateSourcePaths

  TemplateTable = TableRef[string, Template]

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

# proc setPlaceholderIndent*(t: var Template, pos: int) =
#   t.placeholderIndent = pos

# proc setPlaceHolderId*(t: var Template, pos: int): string =
#   t.setPlaceholderIndent pos
#   result = "$viewHandle_" & t.id & ""

# proc getPlaceholderId*(t: Template): string =
#   result = "viewHandle_" & t.id & ""

# proc getPlaceholderIndent*(t: var Template): int =
#   result = t.placeholderIndent

proc getPath(engine: Tim, key: string, templateType: TemplateType): string =
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
# Template API
#
proc newTemplate(id: string, templateType: TemplateType,
    sources: TemplateSourcePaths): Template =
  Template(templateId: id, templateType: templateType, sources: sources)

proc getType*(t: Template): TemplateType =
  t.templateType

proc getHash*(t: Template): string =
  hashid(t.sources.src)

proc getName*(t: Template): string =
  t.templateName

proc getTemplateId*(t: Template): string =
  t.templateId

proc writeHtml*(engine: Tim, tpl: Template, htmlCode: string) =
  ## Writes `htmlCode` on disk using `tpl` info
  writeFile(tpl.sources.html, htmlCode)

proc writeHtmlTail*(engine: Tim, tpl: Template, htmlCode: string) =
  ## Writes `htmlCode` tails on disk using `tpl` info
  writeFile(tpl.sources.html.changeFileExt("tail"), htmlCode)

proc writeAst*(engine: Tim, tpl: Template, astCode: Tree) =
  ## Writes `astCode` on disk using `tpl` info
  # writeFile(tpl.sources.ast, tpl.tree)
  discard

proc getSourcePath*(t: Template): string =
  ## Returns the absolute source path of `t` Template
  result = t.sources.src

proc getAstPath*(t: Template): string =
  ## Returns the absolute `html` path of `t` Template
  result = t.sources.ast

proc getHtmlPath*(t: Template): string =
  ## Returns the absolute `ast` path of `t` Template 
  result = t.sources.html

proc enableJIT*(t: Template) =
  t.templateJit = true

proc hasjit*(t: Template): bool =
  t.templateJit

proc getHtml*(t: Template): string =
  ## Returns precompiled static HTML of `t` Template
  result = readFile(t.getHtmlPath)

proc getTail*(t: Template): string =
  ## Returns the tail of a split layout
  result = readFile(t.getHtmlPath.changeFileExt("tail"))

iterator getViews*(engine: Tim): Template =
  for id, tpl in engine.views:
    yield tpl

iterator getLayouts*(engine: Tim): Template =
  for id, tpl in engine.layouts:
    yield tpl

#
# Tim Engine API
#

proc getTemplateByPath*(engine: Tim, path: string): Template =
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

proc getLayout*(engine: Tim, key: string): Template =
  ## Returns a `Template` layout with `layoutName`
  result = engine.layouts[engine.getPath(key, ttLayout)]

proc hasView*(engine: Tim, key: string): bool =
  ## Determine if `key` exists in `views` table
  result = engine.views.hasKey(engine.getPath(key, ttView))

proc getView*(engine: Tim, key: string): Template =
  ## Returns a `Template` view with `key`
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
    discard existsOrCreateDir(result.src / $sourceDir)
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