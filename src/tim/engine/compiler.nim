# A high-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2023 Tim Engine | MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import ./ast, ./tokens
import std/[tables, ropes, macros]

from std/strutils import `%`, indent, multiReplace, join, escape
from ./meta import TimlTemplate, setPlaceHolderId

type
  Language* = enum
    Nim = "nim"
    JavaScript = "js"
    Python = "python"
    Php = "php"

  Compiler* = object
    ## Compiles current AST program to HTML or SCF (Source Code Filters)
    program: Program
      ## All Nodes statements under a `Program` object instance
    language: Language
    timView: TimlTemplate
    minify: bool
      ## Whether to minify the final HTML output (disabled by default)
    html: Rope
      ## A rope containg the final HTML output
    baseIndent: int
      ## Document base indentation
    hasViewCode: bool
    viewCode: string
      ## When compiler is initialized for layout,
      ## this field will contain the view code (HTML)
    fixTail: bool
    prev, next: NodeType
    firstParentNode: MetaNode

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

var langs = {
  "nim": {
    "if": "if $1:",
    "elif": "elif $1:",
    "else": "else:",
    "fn": "proc render$1View[G, S](app: G, this: S) =",
    "for": "for $1 in $2"
  },
  "js": {
    "if": "if($1) {",
    "elif": "} else if($1) {",
    "else": "} else {",
    "fn": "function render$1View(app = {}, this = {}) {$2}",
    "for": ""
  }
}.toTable

proc writeNewLine(c: var Compiler, nodes: seq[Node]) # defer
proc getNewLine(c: var Compiler, nodes: seq[Node]): string # defer

proc getIndent(c: var Compiler, nodeIndent: int): int =
  if c.baseIndent == 2:
    return int(nodeIndent / c.baseIndent)
  result = nodeIndent

proc getIndentLine(c: var Compiler, meta: MetaNode, skipBr = false): string =
  if meta.pos != 0:
    if not skipBr:
      add result, NewLine
    add result, indent("", c.getIndent(meta.pos))
  else:
    if not skipBr:
      add result, NewLIne

proc indentLine(c: var Compiler, meta: MetaNode, skipBr = false) =
  add c.html, c.getIndentLine(meta, skipBr)

proc getIDAttribute(c: var Compiler, node: Node): string =
  ## Write an ID HTML attribute to current HTML Element
  add result, indent("id=", 1) & "\""
  let idAttrNode = node.attrs["id"][0]
  if idAttrNode.nodeType == NTString:
    add result, idAttrNode.sVal
  # else: c.writeValue(idAttrNode)
  add result, "\""
  # add c.html, ("id=\"$1\"" % [node.attrs["id"][0]]).indent(1)

proc getAttributes(c: var Compiler, node: Node): string =
  ## write one or more HTML attributes
  for k, attrNodes in node.attrs.pairs():
    if k == "id": continue # handled by `writeIDAttribute`
    add result, indent("$1=" % [k], 1) & "\""
    var strAttrs: seq[string]
    for attrNode in attrNodes:
      if attrNode.nodeType == NTString:
        strAttrs.add attrNode.sVal
      elif attrNode.nodeType == NTVariable:
        # TODO handle concat
        discard
        # c.writeValue(attrNode)
    if strAttrs.len != 0:
      add result, join(strAttrs, " ")
    add result, "\""
    # add c.html, ("$1=\"$2\"" % [k, join(v, " ")]).indent(1)

proc writeStrValue(c: var Compiler, node: Node) =
  add c.html, node.sVal
  c.fixTail = true

proc writeIntValue(c: var Compiler, node: Node) =
  add c.html, $node.iVal
  c.fixTail = true

proc getOpenTag(c: var Compiler, tag: string, node: Node, skipBr = false): string =
  if not c.minify:
    add result, c.getIndentLine(node.meta, skipBr = skipBr)
  add result, "<" & tag
  if node.attrs.hasKey("id"):
    add result, c.getIDAttribute(node)
  if node.attrs.len != 0:
    add result, c.getAttributes(node)
  if node.issctag:
    add result, "/"
  add result, ">"

proc openTag(c: var Compiler, tag: string, node: Node, skipBr = false) =
  ## Open tag of the current JsonNode element
  add c.html, c.getOpenTag(tag, node)

proc getCloseTag(c: var Compiler, node: Node, skipBr: bool): string =
  ## Close an HTML tag
  if node.issctag == false:
    if not c.fixTail and not c.minify:
      add result, c.getIndentLine(node.meta, skipBr)
    add result, "</" & node.htmlNodeName & ">"

proc closeTag(c: var Compiler, node: Node, skipBr = false) =
  ## Close an HTML tag
  if node.issctag == false:
    add c.html, c.getCloseTag(node, skipBr)

proc newResult(c: var Compiler, meta: MetaNode) =
  let pos = if meta.col == 0: 2
        else: meta.col + 2
  add c.html, NewLine
  case c.language:
  of Nim:
    c.html &= indent("result &= \"\"\"", pos)
  of Php:
    c.html &= indent("$result = \"\";", pos)    # define $result var
    c.html &= NewLine
    c.html &= indent("$result .= <<<EOT", pos)
    c.html &= NewLine
  else: discard # TODO

proc endResult(c: var Compiler, nl = false) =
  case c.language:
  of Nim:
    c.html &= "\"\"\""
  of Php:
    c.html &= NewLine
    c.html &= "EOT;"
  else: discard # TODO
  # c.prev = NTNone
  if nl:
    c.html &= NewLine

proc getHtml*(c: Compiler): string {.inline.} =
  ## Returns compiled HTML for static `timl` templates
  result = $(c.html)

proc handleViewInclude(c: var Compiler) =
  if c.hasViewCode:
    if c.minify:
      add c.html, c.viewCode
    else:
      add c.html, indent(c.viewCode, c.baseIndent * 2)
  else:
    add c.html, c.timView.setPlaceHolderId()

template `>$`(ident: string) =
  case c.language:
  of Nim:
    add result, $TK_DOT & n.sVal
  of JavaScript:
    discard
  of Python:
    discard
  of Php:
    add result, $TK_MINUS & $TK_GT & n.sVal

template `>$`(i: int) =
  add result, "[" & $(i) & "]"

template `{`() =
  if braces:
    case c.language:
    of Nim:
      result = "\"\"\" & fmt(\"{"
    of Php:
      result = "{$"
    else: discard # TODO

template `}`() =
  if braces:
    case c.language:
    of Nim:
      add result, "}\") & \"\"\""
    of Php:
      add result, "}"
    else: discard # TODO

proc getIdent(c: var Compiler, node: Node, braces = false): string =
  case node.nodeType:
  of NTInt:
    result = $(node.iVal)
  of NTBool:
    result = $(node.bVal)
  of NTVariable:
    `{`
    case node.visibility:
      of GlobalVar:
        case c.language:
        of Nim:
          add result, "app" & $TK_DOT
        of JavaScript:
          discard
        of Python:
          discard
        of Php:
          add result, "app" & $TK_MINUS & $TK_GT
      of ScopeVar:
        add result, "this" & $TK_DOT
      else: discard # InternalVar
    # var accessorTk: string
    add result, node.varIdent
    if node.accessors.len != 0:
      for n in node.accessors:
        if n.nodeType == NTString:
          >$ n.sVal
        else:
          >$ n.iVal
    `}`
  of NTString:
    result = node.sVal
  else: discard

proc newInfixOp(c: var Compiler, a, b: Node, op: OperatorType, tkCond = TK_IF): string =
  result = $tkCond
  result &= indent(c.getIdent(a), 1)
  result &= indent($op, 1)
  result &= indent(c.getIdent(a), 1)
  result &= $TK_COLON

template br() =
  c.html &= NewLine

proc handleConditionStmt(c: var Compiler, node: Node) =
  br
  var i = if node.meta.col == 0: 2 else: node.meta.col + 2
  var infixCond = c.newInfixOp(node.ifCond.infixLeft, node.ifCond.infixRight, node.ifCond.infixOp)
  add c.html, indent(infixCond, i)
  c.writeNewLine(node.ifBody)
  if node.elifBranch.len != 0:
    for elifNode in node.elifBranch:
      c.endResult()
      br
      infixCond = c.newInfixOp(
              elifNode.cond.infixLeft,
              elifNode.cond.infixRight,
              elifNode.cond.infixOp,
              TK_ELIF
            )
      add c.html, indent(infixCond, i)
      c.prev = NTConditionStmt
      c.writeNewLine(elifNode.body)
      c.endResult(true)
  c.endResult(true)
  if node.elseBody.len != 0:
    var elseTk = $TK_ELSE & $TK_COLON
    c.html &= indent(elseTk, i)
    c.prev = NTConditionStmt
    for n in node.elseBody:
      c.writeNewLine(node.elseBody)
      c.endResult(true)

proc handleForStmt(c: var Compiler, node: Node) =
  c.endResult()
  var forStmt = indent("\nfor $1 in $2:" % [node.forItem.varIdent, c.getIdent(node.forItems)], node.meta.col)
  c.html &= forStmt
  if node.forBody[0].nodeType == NTHtmlElement:
    c.newResult(node.forBody[0].meta)
  c.writeNewLine(node.forBody)
  c.endResult()
  c.newResult(c.firstParentNode)

proc getNewLine(c: var Compiler, nodes: seq[Node]): string =
  for node in nodes:
    if node == nil: continue
    case node.nodeType:
    of NTHtmlElement:
      let tag = node.htmlNodeName
      add result, c.getOpenTag(tag, node)
      if node.nodes.len != 0:
        discard c.getNewLine(node.nodes)
      add result, c.getCloseTag(node, false)
      if c.fixTail: c.fixTail = false
    of NTConditionStmt:
      c.handleConditionStmt(node)
    of NTString:
      add result, c.getIdent(node)
    else: discard

proc writeNewLine(c: var Compiler, nodes: seq[Node]) =
  # if nodes[0].nodeType == NTHtmlElement:
    # add c.html, NewLine
    # add c.html, indent("result.add(\"\"\"", nodes[0].meta.col * 2)
  for node in nodes:
    if node == nil: continue # TODO
    case node.nodeType:
    of NTHtmlElement:
      let tag = node.htmlNodeName
      c.openTag(tag, node)
      if node.nodes.len != 0:
        c.writeNewLine(node.nodes)
      c.closeTag(node, false)
      if c.fixTail:
        c.fixTail = false
    of NTConditionStmt:
      c.handleConditionStmt(node)
    of NTForStmt:
      c.handleForStmt(node)
    of NTVariable:
      add c.html, c.getIdent(node, true)
      c.fixTail = true
    of NTView:
      c.handleViewInclude()
    of NTString:
      c.writeStrValue(node)
    of NTInt:
      c.writeIntValue(node)
    else: discard

proc newCompiler*(program: Program, t: TimlTemplate, minify: bool,
        indent: int, filePath: string, viewCode = "", lang = Nim): Compiler =
  var c = Compiler(
    language: lang,
    program: program,
    timView: t,
    minify: false,
    baseIndent: 2
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

  if c.program.nodes.len != 0:
    if c.program.nodes[0].stmtList.nodeType == NTHtmlElement: 
      var metaNode: MetaNode
      c.newResult(metaNode)
  for node in c.program.nodes:
    case node.stmtList.nodeType:
    of NTHtmlElement:
      let tag = node.stmtList.htmlNodeName
      c.firstParentNode = node.meta
      c.openTag(tag, node.stmtList)
      if node.stmtList.nodes.len != 0:
        c.writeNewLine(node.stmtList.nodes)
      c.closeTag(node.stmtList)
    of NTConditionStmt:
      c.endResult()
      c.handleConditionStmt(node.stmtList)
    of NTForStmt:
      c.handleForStmt(node.stmtList)
    of NTVariable:
      add c.html, c.getIdent(node)
    of NTView:
      c.handleViewInclude()
    else: discard
  c.endResult()
  case c.language:
  of Php, JavaScript:
    c.html &= NewLine
    c.html &= indent("return $result;", 2)
    c.html &= NewLine & "}"
  else: discard
  result = c
