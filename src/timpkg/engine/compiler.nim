# A blazing fast, cross-platform, multi-language
# template engine and markup language written in Nim.
#
#    Made by Humans from OpenPeeps
#    (c) George Lemon | LGPLv3 License
#    https://github.com/openpeeps/tim

import std/[tables, critbits, strutils, json]

import ./ast
from ./meta import Tim, Template, TemplateType, getType

type
  ScopeTable = TableRef[string, Node]
  HtmlCompiler* = ref object
    ast: Tree
    tpl: Template
    case templateType: TemplateType
    of ttLayout:
      head: string
    else: discard
    minify: bool
    indent: int
    html, js, sass, json,
      yaml, runtime: string
    hasJs, hasSass, hasJson,
      hasYaml, hasRuntime: bool
    output: string
    error: string
    nl: string = "\n"
    stickytail: bool
      ## if false inserts a \n line before closing
      ## the element. This does not apply
      ## to `textarea`, `submit` `button` and self closing tags. 
    when defined timStandalone:
      discard
    else:
      engine: Tim
      data: JsonNode
      globalScope: ScopeTable = ScopeTable()

#
# Forward declaration
#
proc writeInnerNode(c: HtmlCompiler, nodes: seq[Node], scopetables: var seq[ScopeTable])
proc writeNode(c: HtmlCompiler, node: Node, scopetables: var seq[ScopeTable])

proc hasError*(c: HtmlCompiler): bool =
  result = c.error.len > 0

proc getError*(c: HtmlCompiler): string =
  result = c.error

when not defined timStandalone:
  # Available when Tim is imported as a Nim library.
  # If you want native performance, you can switch
  # to Tim CLI and transpile `.timl` templates to static `.nim` files

  #
  # Scope API
  #
  proc globalScope(c: HtmlCompiler, node: Node) =
    # Add `node` to global scope
    c.globalScope[node.varIdentExpr] = node

  proc `+=`(scope: ScopeTable, node: Node) =
    # Add `node` to current `scope` 
    scope[node.varIdentExpr] = node

  proc stack(c: HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
    # Add `node` to either local or global scope
    if scopetables.len > 0:
      scopetables[^1] += node
      return
    c.globalScope += node

  proc getCurrentScope(c: HtmlCompiler, scopetables: var seq[ScopeTable]): ScopeTable =
    # Returns the current `ScopeTable`. When not found,
    # returns the `globalScope` ScopeTable
    if scopetables.len > 0:
      return scopetables[^1] # the last scope
    return c.globalScope

  proc getScope(c: HtmlCompiler, key: string,
      scopetables: var seq[var ScopeTable]): tuple[scopeTable: ScopeTable, index: int] =
    # Walks (bottom-top) through available `scopetables`, and finds
    # the closest `ScopeTable` that contains a node for given `key`.
    # If found returns the ScopeTable followed by index (position).
    for i in countdown(scopetables.high, scopetables.low):
      if scopetables[i].hasKey(key):
        return (scopetables[i], i)
    if likely c.globalScope.hasKey(key):
      result = (c.globalScope, 0)

  proc inScope(key: string, scopetables: var seq[ScopeTable]): bool =
    # Performs a quick search in the current `ScopeTable`
    if scopetables.len > 0:
      result = scopetables[^1].hasKey(key)

  proc fromScope(c: HtmlCompiler, key: string, scopetables: var seq[ScopeTable]): Node =
    # Retrieves a node with given `key` from `scopetables`
    let some = c.getScope(key, scopetables)
    if some.scopeTable != nil:
      result = some.scopeTable[key]

  #
  # AST Evaluators for JIT computation
  #
  proc getValue(c: HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node
  proc writeValue(c: HtmlCompiler, node: Node, scopetables: var seq[ScopeTable])
  
  proc infixEvaluator(c: HtmlCompiler, lhs, rhs: Node, infixOp: InfixOp, scopetables: var seq[ScopeTable]): bool =
    # Evaluates `a` with `b` based on given infix operator
    case infixOp:
    of EQ:
      case lhs.nt:
      of ntBool:
        case rhs.nt
        of ntBool:
          result = lhs.bVal == rhs.bVal
        else: discard
      of ntString:
        case rhs.nt
        of ntString:
          result = lhs.sVal == rhs.sVal
        else: discard
      of ntInt:
        case rhs.nt
        of ntInt:
          result = lhs.iVal == rhs.iVal
        of ntFloat:
          result = toFloat(lhs.iVal) == rhs.fVal
        else: discard
      of ntFloat:
        case rhs.nt
        of ntFloat:
          result = lhs.fVal == rhs.fVal
        of ntInt:
          result = lhs.fVal == toFloat(rhs.iVal)
        else: discard
      else: discard
    of GT:
      case lhs.nt:
      of ntInt:
        case rhs.nt
        of ntInt:
          result = lhs.iVal > rhs.iVal
        of ntFloat:
          result = toFloat(lhs.iVal) > rhs.fVal
        else: discard
      of ntFloat:
        case rhs.nt
        of ntFloat:
          result = lhs.fVal > rhs.fVal
        of ntInt:
          result = lhs.fVal > toFloat(rhs.iVal)
        else: discard
      else: discard # handle float
    of GTE:
      case lhs.nt:
      of ntInt:
        case rhs.nt
        of ntInt:
          result = lhs.iVal >= rhs.iVal
        of ntFloat:
          result = toFloat(lhs.iVal) >= rhs.fVal
        else: discard
      of ntFloat:
        case rhs.nt
        of ntFloat:
          result = lhs.fVal >= rhs.fVal
        of ntInt:
          result = lhs.fVal >= toFloat(rhs.iVal)
        else: discard
      else: discard # handle float
    else: discard # todo

  proc evalCondition(c: HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
    # Evaluates an `if`, `elif`, `else` conditional node  
    if c.infixEvaluator(node.ifCond.infixLeft,
        node.ifCond.infixRight, node.ifCond.infixOp, scopetables):
      c.writeInnerNode(node.ifBody, scopetables)
      return # condition is truthy

    # handle `elif` branches
    if node.elifBranch.len > 0:
      for elifBranch in node.elifBranch:
        if c.infixEvaluator(elifBranch.cond.infixLeft,
            elifBranch.cond.infixRight, elifBranch.cond.infixOp, scopetables):
          c.writeInnerNode(elifBranch.body, scopetables)
          return # condition is truthy

    # handle `else` branch
    if node.elseBody.len > 0:
      c.writeInnerNode(node.elseBody, scopetables)

  proc evalFor(c: HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
    # Evaluates a `for` node
    discard

  proc evalVar(c: HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node =
    # Evaluates a variable call
    let varNode = c.fromScope(node.varIdent, scopetables)
    if likely(varNode != nil):
      return varNode
    # todo error, variable not found
  
  proc getValue(c: HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node =
    case node.nt
    of ntVariable:
      let varNode = c.evalVar(node, scopetables)
    else: discard

  proc writeValue(c: HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
    case node.nt
    of ntVariable:
      let varNode = c.evalVar(node, scopetables)
      if likely(varNode != nil):
        case varNode.varValue.nt
        of ntString:
          add c.output, varNode.varValue.sVal
        of ntInt:
          add c.output, $(varNode.varValue.iVal)
        of ntFloat:
          add c.output, $(varNode.varValue.fVal)
        of ntBool:
          add c.output, $(varNode.varValue.bVal)
        else:
          echo "error"
    else: discard
    c.stickytail = true

proc getId(c: HtmlCompiler, node: Node): string =
  add result, indent("id=", 1) & "\""
  let attrNode = node.attrs["id"][0]
  case attrNode.nt
  of ntString:
    add result, attrNode.sVal
  else: discard # todo
  add result, "\""

proc getAttrs(c: HtmlCompiler, attrs: HtmlAttributes): string =
  var i = 0
  var skipQuote: bool
  let len = attrs.len
  for k, attrNodes in attrs:
    var attrStr: seq[string]
    add result, indent("$1=" % [k], 1) & "\""
    for attrNode in attrNodes:
      case attrNode.nt
      of ntString:
        if attrNode.sConcat.len == 0:
          add attrStr, attrNode.sVal
        else: discard
      else: discard
    add result, attrStr.join(" ")
    if not skipQuote and i != len:
      add result, "\""
    else:
      skipQuote = false
    inc i

proc baseIndent(c: HtmlCompiler, isize: int): int =
  if c.indent == 2:
    int(isize / c.indent)
  else:
    isize

proc getIndent(c: HtmlCompiler, meta: MetaNode, skipbr = false): string =
  case meta.pos
  of 0:
    if not c.stickytail:
      add result, c.nl
  else:
    if not c.stickytail:
      add result, c.nl
      add result, indent("", c.baseIndent(meta.pos))

template htmlblock(tag: string, body: untyped) =
  var isSelfcloser: bool
  case c.minify:
  of false:
    if c.stickytail == true:
      c.stickytail = false
    add c.output, c.getIndent(node.meta) 
  else: discard
  add c.output, "<" & tag
  case node.nt
  of ntStmtList:
    isSelfcloser = node.stmtList.selfCloser
    if node.stmtList.attrs.hasKey("id"):
      add c.output, c.getId(node.stmtList)
      node.stmtList.attrs.del("id")
    if node.stmtList.attrs.len > 0:
      add c.output, c.getAttrs(node.stmtList.attrs)
  else:
    isSelfcloser = node.selfCloser
    if node.attrs.hasKey("id"):
      add c.output, c.getId(node)
      node.attrs.del("id")
    if node.attrs.len > 0:
      add c.output, c.getAttrs(node.attrs)
  add c.output, ">"
  body
  case isSelfcloser
  of false:
    case c.minify:
    of false:
      add c.output, c.getIndent(node.meta) 
    else: discard
    add c.output, "</" & tag & ">"
    c.stickytail = false
  else: discard

proc writeInnerNode(c: HtmlCompiler, nodes: seq[Node], scopetables: var seq[ScopeTable]) =
  for node in nodes:
    case node.nt:
    of ntHtmlElement:
      let tag = node.htmlNodeName
      htmlblock tag:
        if node.nodes.len > 0:
          c.writeInnerNode(node.nodes, scopetables)
    of ntString:
      add c.output, node.sVal
      c.stickytail = true
    of ntVariable:
      c.writeValue(node, scopetables)
    of ntCondition:
      c.evalCondition(node, scopetables)
    of ntView:
      add c.output, c.getIndent(node.meta)
      c.head = c.output
      reset(c.output)
    else: discard

proc writeNode(c: HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  case node.stmtList.nt:
  of ntHtmlElement:
    let tag = node.stmtList.htmlNodeName
    htmlblock tag:
      if node.stmtList.nodes.len > 0:
        c.writeInnerNode(node.stmtList.nodes, scopetables)
  of ntCondition:
    c.evalCondition(node.stmtList, scopetables)
  of ntForStmt:
    c.evalFor(node.stmtList, scopetables)
  of ntVarExpr:
    if likely(not c.globalScope.hasKey(node.stmtList.varIdentExpr)):
      c.globalScope += node.stmtList
  of ntView:
    # echo node
    discard
  else: discard

#
# Public API
#
proc newHtmlCompiler*(ast: Tree, minify: bool,
    indent: range[2..4], tpl: Template): HtmlCompiler =
  ## Creates a new instance of `HtmlCompiler`
  result = HtmlCompiler(ast: ast, minify: minify,
      indent: indent, tpl: tpl, templateType: tpl.getType)
  if minify: setLen(result.nl, 0)
  var scopetables = newSeq[ScopeTable]()
  for i in 0 .. result.ast.nodes.high:
    result.writeNode(result.ast.nodes[i], scopetables)

proc getHtml*(c: var HtmlCompiler): string =
  case c.minify:
  of true:
    result = c.output
  else:
    if c.output.len > 0:
      result = c.output[1..^1]

proc getHead*(c: var HtmlCompiler): string =
  ## Returns the top of a split layout 
  assert c.templateType == ttLayout
  case c.minify
  of true:
    result = c.head
  else:
    if c.head.len > 0:
      result = c.head[1..^1]

proc getTail*(c: var HtmlCompiler): string =
  ## Returns the tail of a layout
  assert c.templateType == ttLayout
  return c.getHtml()