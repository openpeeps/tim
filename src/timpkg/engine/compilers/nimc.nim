# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[macros, os, tables, strutils]
import pkg/jsony
import ./tim

from ../meta import TimEngine, TimTemplate, TimTemplateType,
  getType, getSourcePath, getGlobalData

type
  NimCompiler* = object of TimCompiler
  Code = distinct string
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

template genIfStmt: NimNodeSymbol =
  let x = newIfStmt(
    (
      cond: ident"$1",
      body: newStmtList().add(ident"$2")
    )
  )
  NimNodeSymbol x.repr

template genElifStmt: NimNodeSymbol =
  let x = nnkElifBranch.newTree(ident"$1", newStmtList().add(ident"$2"))
  NimNodeSymbol x.repr

template genElseStmt: NimNodeSymbol =
  let x = nnkElse.newTree(newStmtList(ident"$1"))
  NimNodeSymbol x.repr

template genCall: NimNodeSymbol =
  let x = nnkCall.newTree(ident"$1")
  NimNodeSymbol x.repr

template genCommand: NimNodeSymbol =
  NimNodeSymbol("$1 $2")

template genForItemsStmt: NimNodeSymbol = 
  let x = nnkForStmt.newTree(
    ident"$1",
    ident"$2",
    newStmtList().add(ident"$3")
  )
  NimNodeSymbol x.repr

const
  ctrl = genViewProc()
  newResult* = genNewResult()
  addResult* = genNewAddResult()
  addResultUnquote* = genNewAddResultUnquote()
  newVar* = genNewVar()
  newConst* = genNewConst()
  newIf* = genIfStmt()
  newElif* = genElifStmt()
  newElse* = genElseStmt()
  newCallNode* = genCall()
  newCommandNode* = genCommand()
  newForItems* = genForItemsStmt()
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

template toCode(nns: NimNodeSymbol, args: varargs[string]): untyped =
  indent(fmt(nns, args), 2)

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

proc getInfixExpr(c: var NimCompiler, node: Node): string =
  case node.nt
  of ntInfixExpr:
    result = c.getValue(node.infixLeft)
    add result, indent($(node.infixOp), 1)
    add result, c.getValue(node.infixRight).indent(1)
  else: discard

proc writeCondition(c: var NimCompiler, node: Node) =
  let ifexpr = c.getInfixExpr(node.condIfBranch.expr)
  var cond = toCode(newIf, ifexpr, "discard")
  for elifnode in node.condElifBranch:
    let elifexpr = c.getInfixExpr(elifnode.expr)
    add cond, toCode(newElif, elifexpr, "discard")
  if node.condElseBranch.stmtList.len > 0:
    add cond, toCode(newElse, "")
  add c.output, cond & "\n"

proc writeCommand(c: var NimCompiler, node: Node) =
  case node.cmdType
  of cmdEcho:
    write newCommandNode, $cmdEcho, c.getValue(node.cmdValue)
  of cmdReturn:
    write newCommandNode, $cmdReturn, c.getValue(node.cmdValue)
  else: discard

proc writeLoop(c: var NimCompiler, node: Node) =
  write newForItems, "keys", "fruits", "echo aaa"

proc getValue(c: NimCompiler, node: Node,
    needEscaping = true, quotes = "\""): string =
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
    of ntConditionStmt:
      c.writeCondition node
    of ntCommandStmt:
      c.writeCommand node
    of ntLoopStmt:
      c.writeLoop node
    else: discard

proc genProcName(path: string): string =
  # Generate view proc name based on `path`
  let path = path.splitFile
  result = "render"
  var i = 0
  var viewName: string
  while i < path.name.len:
    case path.name[i]
    of '-', ' ', '_':
      while path.name[i] in {'-', ' ', '_'}:
        inc i
      add viewName, path.name[i].toUpperAscii # todo convert unicode to ascii
    else:
      add viewName, path.name[i]
      inc i
  add result, viewName.capitalizeAscii

proc newCompiler*(ast: Ast, makelib = false): NimCompiler =
  var c = NimCompiler(ast: ast)
  if makelib:
    add c.output, "import std/[json, dynlib]" & c.nl
    add c.output, "proc NimMain {.cdecl, importc.}" & c.nl
    add c.output, "{.push exportc, dynlib, cdecl.}" & c.nl
    add c.output, "proc library_init = NimMain()" & c.nl
  else:
    add c.output, "import std/json" & c.nl
  let procName = genProcName(ast.src)
  add c.output, ctrl.string % "renderTemplate"
  add c.output, fmt(newResult) & c.nl
  c.walkNodes(c.ast.nodes)
  # if makelib:
  #   add c.output, "echo " & procName & "()" & c.nl
  if makelib:
    add c.output, "proc library_deinit = GC_FullCollect()" & c.nl
    add c.output, "{.pop.}" & c.nl
  result = c

proc exportCode*(c: NimCompiler): string =
  c.output
