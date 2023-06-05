# A high-performance compiled template engine
# inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, macros, strutils]
import pkg/[pkginfo, sass]
import pkg/kapsis/cli
import ./ast

when not defined timEngineStandalone:
  import std/json

from ./meta import TimEngine, Template, ImportFunction, NKind,
                  setPlaceHolderId, getPlaceholderIndent, getType

when defined timEngineStandalone:
  type
    Language* = enum
      Nim = "nim"
      JavaScript = "js"
      Python = "python"
      Php = "php"
else:
  type Memtable = TableRef[string, JsonNode]

type
  Compiler* = object
    program: Program
    tpl: Template
    minify: bool
    baseIndent: int
    html, js, sass, json, yaml: string
    hasViewCode, hasJS, hasSass, hasJson, hasYaml: bool
    viewCode: string
    when defined timEngineStandalone:
      language: Language
      prev, next: NodeType
      firstParentNode: NodeType
    else:
      engine: TimEngine
      data: JsonNode
      memtable: Memtable
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
  UndefinedVariable = "Undefined variable \"$1\" in \"$2\""

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

template writeHtml(body): untyped =
  when defined timEngineStandalone:
    add(result, body)
  else:
    add(c.html, body)

proc writeStrValue(c: var Compiler, node: Node) =
  add c.html, node.sVal
  c.fixTail = true

when defined timEngineStandalone:
  discard
else:
  include ./private/jitutils

proc getHtml*(c: Compiler): string =
  ## Returns compiled HTML for static `timl` templates
  result = $(c.html)

proc getIndentSize(c: var Compiler, isize: int): int =
  result =
    if c.baseIndent == 2:
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

proc getAttrs(c: var Compiler, attrs: HtmlAttributes): string =
  var i = 0
  var skipQuote: bool
  let attrslen = attrs.len
  for k, attrNodes in attrs.pairs():
    if k == "id":
      continue # handled by `writeIDAttribute`
    var strAttrs: seq[string]
    if k[0] == '$':
      for attrNode in attrNodes:
        if attrNode.nodeType == NTVariable:
          strAttrs.add c.getStringValue(attrNode)
    elif k[0] == '%':
      # handle short hand conditional
      # Example: $myvar == true ? checked="true" | disabled="disabled"
      if attrNodes[0].nodeType == NTShortConditionStmt:
        if c.compInfixNode(attrNodes[0].sIfCond):
          add result, indent(c.getAttrs(attrNodes[0].sIfBody), 1)
          skipQuote = true
    else:
      add result, indent("$1=" % [k], 1) & "\""
      for attrNode in attrNodes:
        if attrNode.nodeType == NTString:
          if attrNode.sConcat.len == 0:
            strAttrs.add attrNode.sVal
          else:
            var strInterp = attrNode.sVal
            for varInterp in attrNode.sConcat:
              when defined timEngineStandalone:
                discard # TODO
              else:
                strInterp &= c.getStringValue(varInterp)
            strAttrs.add strInterp
        elif attrNode.nodeType == NTVariable:
          when defined timEngineStandalone:
            discard # TODO
          else:
            strAttrs.add c.getStringValue(attrNode)
    if strAttrs.len != 0:
      add result, join(strAttrs, " ")
    if not skipQuote and i != attrslen:
      add result, "\""
    else:
      skipQuote = false
    inc i

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
    when defined timEngineStandalone:
      discard
    else:
      add result, c.getStringValue(idAttrNode)
  add result, "\""

template `<>`(tag: string, node: Node, skipBr = false) =
  ## Open tag of the current JsonNode element
  if not c.minify:
    writeHtml getIndent(c, node.meta, skipBr)
  writeHtml ("<" & tag)
  if hasIDAttr(node): writeHtml getIDAttr(c, node)
  if hasAttrs(node):
    writeHtml getAttrs(c, node.attrs)
  writeHtml ">"

template `</>`(node: Node, skipBr = false) =
  ## Close an HTML tag
  if node.issctag == false:
    if not c.fixTail and not c.minify:
      writeHtml getIndent(c, node.meta, skipBr)
    add c.html, "</" & node.htmlNodeName & ">"

proc getCode(c: var Compiler, node: Node): string =
  result =
    if c.hasViewCode:
      if c.minify:
        c.viewCode
      else:
        indent(c.viewCode, node.meta.pos)
        # indent(c.viewCode, c.tpl.getPlaceholderIndent())
    else:
      c.tpl.setPlaceHolderId(node.meta.pos)

proc handleView(c: var Compiler, node: Node) =
  add c.html, c.getCode(node)
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
      writeHtml c.getStringValue(node)
    of NTInfixStmt:
      c.handleInfixStmt(node)
    of NTConditionStmt:
      c.handleConditionStmt(node)
    of NTString:
      c.writeStrValue(node)
    of NTForStmt:
      c.handleForStmt(node)
    of NTView:
      c.handleView(node)
    of NTJavaScript:
      c.getJSSnippet(node)
    of NTSass:
      c.getSassSnippet(node)
    of NTJson:
      c.getJsonSnippet(node)
    of NTYaml:
      c.getYamlSnippet(node)
    of NTCall:
      c.callFunction(node)
    else: discard

proc compileProgram(c: var Compiler) =
  # when not defined timEngineStandalone:
  #   if c.hasSass and getType(c.tpl) == Layout:
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
      c.handleView(node.stmtList)
    of NTJavaScript:
      c.getJSSnippet(node.stmtList)
    of NTSass:
      c.getSassSnippet(node.stmtList)
    of NTJson:
      c.getJsonSnippet(node.stmtList)
    of NTYaml:
      c.getYamlSnippet(node.stmtList)
    of NTCall:
      c.callFunction(node.stmtList)
    else: discard

  when not defined timEngineStandalone:
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

when defined timEngineStandalone:
  proc newCompiler*(program: Program, tpl: Template, minify: bool,
                    indent: int, filePath: string,
                    viewCode = "", lang = Nim): Compiler =
    ## Create a new Compiler instance for Command Line interface
    var c = Compiler(
      language: lang,
      program: program,
      tpl: tpl,
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
  proc newCompiler*(e: TimEngine, p: Program, tpl: Template, minify: bool,
                    indent: int, filePath: string, data = %*{}, viewCode = "",
                    hasViewCode = false): Compiler =
    ## Create a new Compiler at runtime for just in time compilation
    var c = Compiler(
      engine: e,
      program: p,
      tpl: tpl,
      data: data,
      minify: minify,
      baseIndent: indent,
      viewCode: viewCode,
      hasViewCode: hasViewCode,
      memtable: Memtable(),
    )
    c.compileProgram()
    result = c

  proc newCompiler*(program: Program, minify: bool, indent: int, data: JsonNode): Compiler =
    var jsonData = newJObject()
    jsonData["globals"] = newJObject()
    jsonData["scope"] = if data != nil: data else: newJObject()
    var c = Compiler(program: program, minify: minify,
                    baseIndent: indent, data: jsonData, memtable: Memtable())
    c.compileProgram()
    result = c