# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim
import std/[macros, tables, strutils]
import pkg/jsony
import ./tim

from ../meta import TimEngine, TimTemplate, TimTemplateType,
  getType, getSourcePath, getGlobalData

type
  NimCompiler* = object of TimCompiler

  NimNodeSymbol = distinct string

template genNewResult: NimNodeSymbol =
  let x = newAssignment(ident"result", newLit(""))
  NimNodeSymbol x.repr

template genNewVar: NimNodeSymbol =
  let x = newVarStmt(ident"$1", ident"$2")
  NimNodeSymbol x.repr

template genNewConst: NimNodeSymbol =
  let x = newConstStmt(ident"$1", ident"$2")
  NimNodeSymbol x.repr

template genNewAddResult: NimNodeSymbol =
  let x = nnkCommand.newTree(ident"add", ident"result", newLit"$1")
  NimNodeSymbol x.repr

template genNewAddResultUnquote: NimNodeSymbol =
  let x = nnkCommand.newTree(ident"add", ident"result", ident"$1")
  NimNodeSymbol x.repr 

template genViewProc: NimNodeSymbol =
  let x = newProc(
    nnkPostfix.newTree(ident"*", ident"$1"),
    params = [
      ident"string",
      nnkIdentDefs.newTree(
        ident"app",
        ident"this",
        ident"JsonNode",
        newCall(ident"newJObject")
      )
    ],
    body = newStmtList(
      newCommentStmtNode("Render homepage")
    )
  )
  NimNodeSymbol x.repr

const
  ctrl = genViewProc()
  newResult* = genNewResult()
  addResult* = genNewAddResult()
  addResultUnquote* = genNewAddResultUnquote()
  newVar* = genNewVar()
  newConst* = genNewConst()
  voidElements = [tagArea, tagBase, tagBr, tagCol,
    tagEmbed, tagHr, tagImg, tagInput, tagLink, tagMeta,
    tagParam, tagSource, tagTrack, tagWbr, tagCommand,
    tagKeygen, tagFrame]
#
# forward declarations
#
proc getValue(c: NimCompiler, node: Node, needEscaping = true, quotes = "\""): string
proc walkNodes(c: var NimCompiler, nodes: seq[Node])

proc fmt*(nns: NimNodeSymbol, arg: varargs[string]): string =
  result = nns.string % arg

template write(nns: NimNodeSymbol, args: varargs[string]) =
  add c.output, indent(fmt(nns, args), 2) & c.nl

template writeToResult(nns: NimNodeSymbol, isize = 2, addNewLine = true, args: varargs[string]) =
  add result, indent(fmt(nns, args), isize)
  if addNewLine: add result, c.nl

proc writeVar(c: var NimCompiler, node: Node) =
  case node.varImmutable:
  of false:
    write(newVar, node.varName, c.getValue(node.varValue))
  of true:
    write(newConst, node.varName, c.getValue(node.varValue))

proc getVar(c: var NimCompiler, node: Node): string =
  case node.varImmutable:
  of false:
    writeToResult(newVar, 0, args = [node.varName, c.getValue(node.varValue)])
  of true:
    writeToResult(newConst, 0, args = [node.varName, c.getValue(node.varValue)])


proc getAttrs(c: var NimCompiler, attrs: HtmlAttributes): string =
  ## Write HTMLAttributes
  var i = 0
  var skipQuote: bool
  let len = attrs.len
  for k, attrNodes in attrs:
    var attrStr: seq[string]
    if not c.isClientSide:
      add result, indent("$1=\\\"" % k, 1)
    for attrNode in attrNodes:
      case attrNode.nt
      of ntLitString, ntLitInt, ntLitFloat, ntLitBool:
        add attrStr, c.getValue(attrNode, true, "")
      else: discard # todo
    if not c.isClientSide:
      add result, attrStr.join(" ")
      if not skipQuote and i != len:
        add result, "\\\""
      else:
        skipQuote = false
      inc i
    # else:
      # add result, domSetAttribute % [xel, k, attrStr.join(" ")]

proc htmlElement(c: var NimCompiler, x: Node): string =
  block:
    case c.minify:
    of false:
      if c.stickytail == true:
        c.stickytail = false
    else: discard
    let t = x.getTag()
    add result, "<"
    add result, t
    if x.attrs != nil:
      if x.attrs.len > 0:
        add result, c.getAttrs(x.attrs)
    add result, ">"
    for i in 0..x.nodes.high:
      let node = x.nodes[i]
      case node.nt
      of ntLitString, ntLitInt, ntLitFloat, ntLitBool:
        add result, c.getValue(node, false)
      of ntIdent:
        add result, "\" & " & c.getValue(node, false) & " & \""
      of ntVariableDef:
        add result, "\"" & c.nl
        add result, c.getVar(node)
        # kinda hack, `add result, $1` unquoted for inserting remaining tails
        writeToResult(addResultUnquote, 0, false, args = "\"")
      of ntHtmlElement:
        add result, c.htmlElement(node)
      else: discard
    case x.tag
    of voidElements:
      discard
    else:
      case c.minify:
      of false:
        discard
        # add c.output, c.getIndent(node.meta) 
      else: discard
      add result, "</"
      add result, t
      add result, ">"
      c.stickytail = false

proc writeElement(c: var NimCompiler, node: Node) =
  write(addResult, c.htmlElement(node))

proc getValue(c: NimCompiler, node: Node, needEscaping = true, quotes = "\""): string =
  result = 
    case node.nt
    of ntLitString:
      if needEscaping: 
        escape(node.sVal, quotes, quotes)
      else:
        node.sVal
    of ntLitInt:
      $node.iVal
    of ntLitFloat:
      $node.iVal
    of ntLitBool:
      $node.bVal
    of ntIdent:
      node.identName
    else: ""

proc walkNodes(c: var NimCompiler, nodes: seq[Node]) =
  for i in 0..nodes.high:
    let node = nodes[i]
    case node.nt
    of ntVariableDef:
      c.writeVar node
    of ntHtmlElement:
      c.writeElement node
    else: discard

proc newCompiler*(ast: Ast): NimCompiler =
  var c = NimCompiler(ast: ast)
  add c.output, ctrl.string % ["getHomepage"]
  add c.output, fmt(newResult) & c.nl
  c.walkNodes(c.ast.nodes)
  result = c

proc exportCode*(c: NimCompiler): string = c.output
