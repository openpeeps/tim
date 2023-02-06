# A high-performance compiled template engine inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import std/[ropes, tables, macros, strutils]
import pkg/[pkginfo, sass]
import pkg/klymene/cli
import ./ast

when not defined cli:
  import std/json

from ./meta import Template, setPlaceHolderId, getPlaceholderIndent, getType

when defined cli:
  type
    Language* = enum
      Nim = "nim"
      JavaScript = "js"
      Python = "python"
      Php = "php"
else:
  type MemStorage = TableRef[string, JsonNode]

type
  Compiler* = object
    program: Program
    `template`: Template
    minify: bool
    baseIndent: int
    html, js, sass, json, yaml: Rope
    hasViewCode, hasJS, hasSass, hasJson, hasYaml: bool
    viewCode: string
    when defined cli:
      language: Language
      prev, next: NodeType
      firstParentNode: NodeType
    else:
      data: JsonNode
      memtable: MemStorage
    fixTail: bool
    logs: seq[string]

const
  NewLine = "\n"
  InvalidAccessorKey = "Invalid property accessor \"$1\" for $2 ($3)"
  InvalidConversion = "Failed to convert $1 \"$2\" to string"
  InvalidComparison = "Can't compare $1 and $2 values"
  InvalidObjectAccess = "Invalid object access"
  UndefinedPropertyAccessor = "Undefined property accessor \"$1\" in data storage"
  UndefinedArray = "Undefined array"
  InvalidArrayAccess = "Array indices must be positive integers. Got $1[\"$2\"]"
  ArrayIndexOutBounds = "Index out of bounds [$1]. \"$2\" size is [$3]"
  UndefinedProperty = "Undefined property \"$1\""
  UndefinedVariable = "Undefined property \"$1\" in \"$2\""

# defer
proc writeNewLine(c: var Compiler, nodes: seq[Node])
# proc getNewLine(c: var Compiler, nodes: seq[Node]): string

proc hasError*(c: Compiler): bool =
  result = c.logs.len != 0

proc getErrors*(c: Compiler): seq[string] =
  result = c.logs

proc printErrors*(c: var Compiler, filePath: string) =
  if c.logs.len != 0:
    for error in c.logs:
      display error, indent = 2
    echo filePath
    setLen(c.logs, 0)

template `&==`(body): untyped =
  when defined cli:
    add(result, body)
  else:
    add(c.html, body)

proc writeStrValue(c: var Compiler, node: Node) =
  add c.html, node.sVal
  c.fixTail = true

when defined cli:
  discard
else:
  include ./private/jitutils

proc getHtml*(c: Compiler): string =
  ## Returns compiled HTML for static `timl` templates
  result = $(c.html)

proc getIndentSize(c: var Compiler, isize: int): int =
  result = if c.baseIndent == 2:
              int(isize / c.baseIndent)
           else: isize

proc getIndent(c: var Compiler, meta: MetaNode, skipBr = false): string =
  if meta.pos != 0:
    if not skipBr:
      add result, NewLine
    add result, indent("", c.getIndentSize(meta.pos))
  else:
    if not skipBr:
      add result, NewLine

proc hasAttrs(node: Node): bool =
  result = node.attrs.len != 0

proc getAttrs(c: var Compiler, node: Node): string =
  for k, attrNodes in node.attrs.pairs():
    if k == "id": continue # handled by `writeIDAttribute`
    add result, indent("$1=" % [k], 1) & "\""
    var strAttrs: seq[string]
    for attrNode in attrNodes:
      if attrNode.nodeType == NTString:
        strAttrs.add attrNode.sVal
      elif attrNode.nodeType == NTVariable:
        strAttrs.add c.getStringValue(attrNode)
    if strAttrs.len != 0:
      add result, join(strAttrs, " ")
    add result, "\""

proc hasIDAttr(node: Node): bool =
  ## Determine if current JsonNode has an HTML ID attribute attached to it
  result = node.attrs.hasKey("id")

proc getIDAttr(c: var Compiler, node: Node): string =
  # Write an ID HTML attribute to current HTML Element
  add result, indent("id=", 1) & "\""
  let idAttrNode = node.attrs["id"][0]
  if idAttrNode.nodeType == NTString:
    add result, idAttrNode.sVal
  else:
    add result, c.getStringValue(idAttrNode)
  add result, "\""

template `<>`(tag: string, node: Node, skipBr = false) =
  ## Open tag of the current JsonNode element
  if not c.minify:
    &== getIndent(c, node.meta, skipBr)
  &== ("<" & tag)
  if hasIDAttr(node):
    &== getIDAttr(c, node)
  if hasAttrs(node):
    &== getAttrs(c, node)
  if node.issctag:
    &== "/"
  &== ">"

template `</>`(node: Node, skipBr = false) =
  ## Close an HTML tag
  if node.issctag == false:
    if not c.fixTail and not c.minify:
      &== getIndent(c, node.meta, skipBr)
    add c.html, "</" & node.htmlNodeName & ">"

proc getViewCode(c: var Compiler, node: Node): string =
  result =
    if c.hasViewCode:
      if c.minify:
        c.viewCode
      else:
        indent(c.viewCode, c.`template`.getPlaceholderIndent())
    else:
      c.`template`.setPlaceHolderId(node.meta.pos)

proc insertViewCode(c: var Compiler, node: Node) =
  add c.html, c.getViewCode(node)
  if c.hasJS:
    add c.html, NewLine & "<script type=\"text/javascript\">"
    add c.html, $c.js
    add c.html, NewLine & "</script>"
  if c.hasSass:
    add c.html, NewLine & "<style>"
    add c.html, $c.sass
    add c.html, NewLine & "</style>"

proc getJSSnippet(c: var Compiler, node: Node) =
  c.js &= node.jsCode
  if not c.hasJs: c.hasJs = true

proc getSassSnippet(c: var Compiler, node: Node) =
  try:
    c.sass &= NewLine & compileSass(node.sassCode, outputStyle = OutputStyle.Compressed)
  except SassException:
    c.logs.add(getCurrentExceptionMsg())
  if not c.hasSass: c.hasSass = true

proc getJsonSnippet(c: var Compiler, node: Node) =
  let jsonIdentName = 
    if node.jsonIdent[0] == '#':
      "id=\"$1\"" % node.jsonIdent[1..^1]
    else:
      "class=\"$1\"" % node.jsonIdent[1..^1]
  c.json &= NewLine & "<script type=\"application/json\" $1>" % [jsonIdentName]
  c.json &= node.jsonCode
  c.json &= "</script>"
  if not c.hasJson: c.hasJson = true

proc getYamlSnippet(c: var Compiler, node: Node) =
  c.yaml &= node.yamlCode
  if not c.hasYaml: c.hasYaml = true

proc writeNewLine(c: var Compiler, nodes: seq[Node]) =
  for node in nodes:
    if node == nil: continue # TODO sometimes we get nil. check parser
    case node.nodeType:
    of NTHtmlElement:
      let tag = node.htmlNodeName
      tag <> node
      c.fixTail = tag in ["textarea", "button"]
      if node.nodes.len != 0:
        c.writeNewLine(node.nodes)
      node </> false
      if c.fixTail: c.fixTail = false
    of NTVariable:
      &== c.getStringValue(node)
    of NTInfixStmt:
      c.handleInfixStmt(node)
    of NTConditionStmt:
      c.handleConditionStmt(node)
    of NTString:
      c.writeStrValue(node)
    of NTForStmt:
      c.handleForStmt(node)
    of NTView:
      c.insertViewCode(node)
    of NTJavaScript:
      c.getJSSnippet(node)
    of NTSass:
      c.getSassSnippet(node)
    of NTJson:
      c.getJsonSnippet(node)
    of NTYaml:
      c.getYamlSnippet(node)
    else: discard

proc compileProgram(c: var Compiler) =
  # when not defined cli:
  #   if c.hasSass and getType(c.`template`) == Layout:
  for node in c.program.nodes:
    case node.stmtList.nodeType:
    of NTHtmlElement:
      let tag = node.stmtList.htmlNodeName
      tag <> node.stmtList
      if node.stmtList.nodes.len != 0:
        c.writeNewLine(node.stmtList.nodes)
      node.stmtList </> false
    of NTConditionStmt:
      c.handleConditionStmt(node.stmtList)
    of NTForStmt:
      c.handleForStmt(node.stmtList)
    of NTView:
      c.insertViewCode(node.stmtList)
    of NTJavaScript:
      c.getJSSnippet(node.stmtList)
    of NTSass:
      c.getSassSnippet(node.stmtList)
    of NTJson:
      c.getJsonSnippet(node.stmtList)
    of NTYaml:
      c.getYamlSnippet(node.stmtList)
    else: discard

  when not defined cli:
    # if c.hasViewCode == false:
    if c.hasJson:
      add c.html, $c.json
    if c.hasJS:
      add c.html, NewLine & "<script type=\"text/javascript\">"
      add c.html, "document.addEventListener(\"DOMContentLoaded\", async function(){"
      add c.html, indent($c.js, 2)
      add c.html, "})"
      add c.html, NewLine & "</script>"
    if c.hasSass:
      add c.html, NewLine & "<style>"
      add c.html, $c.sass
      add c.html, NewLine & "</style>"

when defined cli:
  proc newCompiler*(program: Program, `template`: Template, minify: bool,
                    indent: int, filePath: string,
                    viewCode = "", lang = Nim): Compiler =
    ## Create a new Compiler instance for Command Line interface
    var c = Compiler(
      language: lang,
      program: p,
      `template`: `template`,
      minify: minify,
      baseIndent: indent
    )
    case c.language
    of Nim:
      c.html &= "proc renderProductsView[G, S](app: G, this: S): string ="
      if c.program.nodes.len == 0:
        c.html &= NewLine & indent("discard", 2)
    of JavaScript:
      c.html &= "function renderProductsView(app = {}, this = {}) {"
    of Python:
      c.html &= "def renderProductsView(app: Dict, this: Dict):"
    of Php:
      c.html &= "function renderProductsView(object $app, object $this) {"
    var metaNode: MetaNode
    if c.program.nodes.len != 0:
      if c.program.nodes[0].stmtList.nodeType == NTHtmlElement: 
        c.newResult(metaNode)
    c.compileProgram()
    result = c

else:
  proc newCompiler*(p: Program, `template`: Template, minify: bool,
                    indent: int, filePath: string,
                    data = %*{}, viewCode = "", hasViewCode = false): Compiler =
    ## Create a new Compiler at runtime for just in time compilation
    var c = Compiler(
      program: p,
      `template`: `template`,
      data: data,
      minify: minify,
      baseIndent: indent,
      viewCode: viewCode,
      hasViewCode: hasViewCode,
      memtable: newTable[string, JsonNode]()
    )
    c.compileProgram()
    result = c