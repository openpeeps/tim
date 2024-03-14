# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, strutils, json,
  jsonutils, options, terminal]

import pkg/jsony
import ./tim

from std/xmltree import escape
from ../meta import TimEngine, TimTemplate, TimTemplateType,
  getType, getSourcePath, getGlobalData

type
  HtmlCompiler* = object of TimCompiler
    ## Object of a TimCompiler to output `HTML`
    when not defined timStandalone:
      globalScope: ScopeTable = ScopeTable()
      data: JsonNode
      jsOutputCode: string = "{"
      jsCountEl: uint
      jsTargetElement: string
      isClientSide: bool
    # jsComp: Table[string, JSCompiler] # todo

# Forward Declaration
proc walkNodes(c: var HtmlCompiler, nodes: seq[Node],
    scopetables: var seq[ScopeTable], parentNodeType: NodeType = ntUnknown,
    xel = newStringOfCap(0)): Node {.discardable.}

proc typeCheck(c: var HtmlCompiler, x, node: Node): bool
proc typeCheck(c: var HtmlCompiler, node: Node, expect: NodeType): bool
proc mathInfixEvaluator(c: var HtmlCompiler, lhs, rhs: Node, op: MathOp, scopetables: var seq[ScopeTable]): Node
proc dotEvaluator(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node
proc getValue(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node
proc fnCall(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node
proc hasError*(c: HtmlCompiler): bool = c.hasErrors # or c.logger.errorLogs.len > 0
proc bracketEvaluator(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node

proc baseIndent(c: HtmlCompiler, isize: int): int =
  if c.indent == 2:
    int(isize / c.indent)
  else:
    isize

proc getIndent(c: HtmlCompiler, meta: Meta, skipbr = false): string =
  case meta[1]
  of 0:
    if not c.stickytail:
      if not skipbr:
        add result, c.nl
  else:
    if not c.stickytail:
      add result, c.nl
      add result, indent("", c.baseIndent(meta[1]))

const
  domCreateElement = "let $1 = document.createElement('$2');"
  domSetAttribute = "$1.setAttribute('$2','$3');"
  domInsertAdjacentElement = "$1.insertAdjacentElement('beforeend',$2);"
  domInnerText = "$1.innerText=\"$2\";"

when not defined timStandalone:
  # Scope API, available for library version of TimEngine 
  proc globalScope(c: var HtmlCompiler, key: string, node: Node) =
    # Add `node` to global scope
    c.globalScope[key] = node

  proc `+=`(scope: ScopeTable, key: string, node: Node) =
    # Add `node` to current `scope` 
    scope[key] = node

  proc stack(c: var HtmlCompiler, key: string, node: Node,
      scopetables: var seq[ScopeTable]) =
    # Add `node` to either local or global scope
    case node.nt
    of ntVariableDef:
      if scopetables.len > 0:
        scopetables[^1][node.varName] = node
      else:
        c.globalScope[node.varName] = node
    of ntLitFunction:
      if scopetables.len > 0:
        scopetables[^1][node.fnIdent] = node
      else:
        c.globalScope[node.fnIdent] = node
    else: discard

  proc getCurrentScope(c: var HtmlCompiler,
      scopetables: var seq[ScopeTable]): ScopeTable =
    # Returns the current `ScopeTable`. When not found,
    # returns the `globalScope` ScopeTable
    if scopetables.len > 0:
      return scopetables[^1] # the last scope
    return c.globalScope

  proc getScope(c: var HtmlCompiler, key: string,
      scopetables: var seq[ScopeTable]
    ): tuple[scopeTable: ScopeTable, index: int] =
    # Walks (bottom-top) through available `scopetables`, and finds
    # the closest `ScopeTable` that contains a node for given `key`.
    # If found returns the ScopeTable followed by index (position).
    if scopetables.len > 0:
      for i in countdown(scopetables.high, scopetables.low):
        if scopetables[i].hasKey(key):
          return (scopetables[i], i)
    if likely(c.globalScope.hasKey(key)):
      result = (c.globalScope, 0)

  proc inScope(c: HtmlCompiler, key: string, scopetables: var seq[ScopeTable]): bool =
    # Performs a quick search in the current `ScopeTable`
    if scopetables.len > 0:
      result = scopetables[^1].hasKey(key)
    if not result:
      return c.globalScope.hasKey(key)

  proc fromScope(c: var HtmlCompiler, key: string,
      scopetables: var seq[ScopeTable]): Node =
    # Retrieves a node by `key` from `scopetables`
    let some = c.getScope(key, scopetables)
    if some.scopeTable != nil:
      return some.scopeTable[key]
  
  proc newScope(scopetables: var seq[ScopeTable]) {.inline.} =
    ## Create a new Scope
    scopetables.add(ScopeTable())

  proc clearScope(scopetables: var seq[ScopeTable]) {.inline.} =
    ## Clears the current (latest) ScopeTable
    scopetables.delete(scopetables.high)

# define default value nodes
let
  intDefault = ast.newNode(ntLitInt)
  strDefault = ast.newNode(ntLitString)
  boolDefault = ast.newNode(ntLitBool)
boolDefault.bVal = true

#
# Forward Declaration
#
proc varExpr(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable])

#
# AST Evaluators
#
proc dumpHook*(s: var string, v: seq[Node])
proc dumpHook*(s: var string, v: OrderedTableRef[string, Node])
# proc dumpHook*(s: var string, v: Color)

proc dumpHook*(s: var string, v: Node) =
  ## Dumps `v` node to stringified JSON using `pkg/jsony`
  case v.nt
  of ntLitString: s.add("\"" & $v.sVal & "\"")
  of ntLitFloat:  s.add($v.fVal)
  of ntLitInt:    s.add($v.iVal)
  of ntLitBool:   s.add($v.bVal)
  of ntLitObject: s.dumpHook(v.objectItems)
  of ntLitArray:  s.dumpHook(v.arrayItems)
  else: discard

proc dumpHook*(s: var string, v: seq[Node]) =
  s.add("[")
  if v.len > 0:
    s.dumpHook(v[0])
    for i in 1 .. v.high:
      s.add(",")
      s.dumpHook(v[i])
  s.add("]")

proc dumpHook*(s: var string, v: OrderedTableRef[string, Node]) =
  var i = 0
  let len = v.len - 1
  s.add("{")
  for k, node in v:
    s.add("\"" & k & "\":")
    s.dumpHook(node)
    if i < len:
      s.add(",")
    inc i
  s.add("}")

proc toString(node: Node, escape = false): string =
  if likely(node != nil):
    result =
      case node.nt
      of ntLitString: node.sVal
      of ntLitInt:    $node.iVal
      of ntLitFloat:  $node.fVal
      of ntLitBool:   $node.bVal
      of ntLitObject:
        fromJson(jsony.toJson(node.objectItems)).pretty
      of ntLitArray:
        fromJson(jsony.toJson(node.arrayItems)).pretty
      of ntIdent:     node.identName
      else: ""
    if escape:
      result = xmltree.escape(result)

proc toString(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable], escape = false): string =
  result =
    case node.nt
    of ntLitString:
      if node.sVals.len == 0:
        node.sVal
      else:
        var concat: string
        for concatNode in node.sVals:
          let x = c.getValue(concatNode, scopetables)
          if likely(x != nil):
            add concat, x.sVal
        node.sVal & concat
    of ntLitInt:    $node.iVal
    of ntLitFloat:  $node.fVal
    of ntLitBool:   $node.bVal
    of ntLitObject:
      fromJson(jsony.toJson(node.objectItems)).pretty
    of ntLitArray:
      fromJson(jsony.toJson(node.arrayItems)).pretty
    else: ""
  if escape:
    result = xmltree.escape(result)

proc toString(node: JsonNode, escape = false): string =
  result =
    case node.kind
    of JString: node.str
    of JInt:    $node.num
    of JFloat:  $node.fnum
    of JBool:   $node.bval
    of JObject, JArray: $(node)
    else: "null"

proc toString(value: Value, escape = false): string =
  result =
    case value.kind
    of jsonValue:
      value.jVal.toString(escape)
    of nimValue:
      value.nVal.toString(escape)

template write(x: Node, fixtail, escape: bool) =
  if likely(x != nil):
    add c.output, x.toString(escape)
    c.stickytail = fixtail

proc print(val: Node) =
  let meta = " ($1:$2) " % [$val.meta[0], $val.meta[2]]
  stdout.styledWriteLine(
    fgGreen, "Debug",
    fgDefault, meta,
    fgMagenta, $(val.nt),
    fgDefault, "\n" & toString(val)
  )

proc print(val: JsonNode, line, col: int) =
  let meta = " ($1:$2) " % [$line, $col]
  var kind: JsonNodeKind
  var val = val
  if val != nil:
    kind = val.kind
  else:
    val = newJNull()
  stdout.styledWriteLine(
    fgGreen, "Debug",
    fgDefault, meta,
    fgMagenta, $(val.kind),
    fgDefault, "\n" & toString(val)
  )

proc evalJson(c: var HtmlCompiler,
    storage: JsonNode, lhs, rhs: Node): JsonNode =
  # Evaluate a JSON node
  if lhs == nil:
    if likely(storage.hasKey(rhs.identName)):
      return storage[rhs.identName]
    else:
      c.logger.newError(undeclaredField, rhs.meta[0],
        rhs.meta[1], true, [rhs.identName])
      # tim should print error and continue the transpilation
      # process even if accessed field does not exist
      # c.hasErrors = true

proc evalStorage(c: var HtmlCompiler, node: Node): JsonNode =
  case node.lhs.nt
  of ntIdent:
    if node.lhs.identName == "this":
      return c.evalJson(c.data["local"], nil, node.rhs)
    if node.lhs.identName == "app":
      return c.evalJson(c.data["global"], nil, node.rhs)
  of ntDotExpr:
    let lhs = c.evalStorage(node.lhs)
    if likely(lhs != nil):
      return c.evalJson(lhs, nil, node.rhs)
  else: discard

proc walkAccessorStorage(c: var HtmlCompiler,
    lhs, rhs: Node, scopetables: var seq[ScopeTable]): Node =
  case lhs.nt
  of ntLitObject:
    case rhs.nt
    of ntIdent:
      try:
        result = lhs.objectItems[rhs.identName]
      except KeyError:
        compileErrorWithArgs(undeclaredField, rhs.meta, [rhs.identName])
    else: compileErrorWithArgs(invalidAccessorStorage, rhs.meta, [rhs.toString, $lhs.nt])
  of ntDotExpr:
    let x = c.walkAccessorStorage(lhs.lhs, lhs.rhs, scopetables)
    if likely(x != nil):
      return c.walkAccessorStorage(x, rhs, scopetables)
  of ntIdent:
    let x = c.getValue(lhs, scopetables)
    if likely(x != nil):
      result = c.walkAccessorStorage(x, rhs, scopetables)
  of ntBracketExpr:
    let lhs = c.bracketEvaluator(lhs, scopetables)
    if likely(lhs != nil):
      return c.walkAccessorStorage(lhs, rhs, scopetables)
  of ntLitArray:
    case rhs.nt
    of ntLitInt:
      try:
        result = lhs.arrayItems[rhs.iVal]
      except Defect:
        compileErrorWithArgs(indexDefect, lhs.meta, [$(rhs.iVal), "0.." & $(lhs.arrayItems.high)])
    of ntIndexRange:
      let l = c.getValue(rhs.rangeNodes[0], scopetables)
      let r = c.getValue(rhs.rangeNodes[1], scopetables)
      if likely(l != nil and r != nil):
        let l = l.iVal
        let r = r.iVal
        try:
          result = ast.newNode(ntLitArray)
          result.meta = lhs.meta
          case rhs.rangeLastIndex
          of false:
            result.arrayItems = lhs.arrayItems[l..r]
          of true:
            result.arrayItems = lhs.arrayItems[l..^r]
        except Defect:
          let someRange =
            if rhs.rangeLastIndex: $(l) & "..^" & $(r)
            else: $(l) & ".." & $(r)
          compileErrorWithArgs(indexDefect, lhs.meta, [someRange, "0.." & $(lhs.arrayItems.high)])
      else: discard # todo error?
    else: compileErrorWithArgs(invalidAccessorStorage, rhs.meta, [rhs.toString, $lhs.nt])
  else: discard

proc dotEvaluator(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node =
  # Evaluate dot expressions
  case node.storageType
  of localStorage, globalStorage:
    let x = c.evalStorage(node)
    if likely(x != nil):
      return x.toTimNode
    result = ast.newNode(ntLitBool)
  of scopeStorage:
    return c.walkAccessorStorage(node.lhs, node.rhs, scopetables)

proc bracketEvaluator(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node =
  case node.bracketStorageType
  of localStorage, globalStorage:
    let x = c.evalStorage(node)
    if likely(x != nil):
      result = x.toTimNode
  of scopeStorage:
    let index = c.getValue(node.bracketIndex, scopetables)
    if likely(index != nil):
      return c.walkAccessorStorage(node.bracketLHS, index, scopetables)

proc writeDotExpr(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  # Handle dot expressions
  let someValue: Node = c.dotEvaluator(node, scopetables)
  if likely(someValue != nil):
    add c.output, someValue.toString()
    c.stickytail = true

proc evalCmd(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node =
  # Evaluate a command
  var val = c.getValue(node.cmdValue, scopetables)
  if val != nil:
    case node.cmdType
    of cmdEcho:
      val.meta = node.cmdValue.meta
      print(val)
    of cmdReturn:
      return val

proc infixEvaluator(c: var HtmlCompiler, lhs, rhs: Node,
    infixOp: InfixOp, scopetables: var seq[ScopeTable]): bool =
  # Evaluates comparison expressions
  if unlikely(lhs == nil or rhs == nil): return
  case infixOp:
  of EQ:
    case lhs.nt:
    of ntLitBool:
      case rhs.nt
      of ntLitBool:
        result = lhs.bVal == rhs.bVal
      else: discard
    of ntLitString:
      case rhs.nt
      of ntLitString:
        result = lhs.sVal == rhs.sVal
      else: discard
    of ntLitInt:
      case rhs.nt
      of ntLitInt:
        result = lhs.iVal == rhs.iVal
      of ntLitFloat:
        result = toFloat(lhs.iVal) == rhs.fVal
      else: discard
    of ntLitFloat:
      case rhs.nt
      of ntLitFloat:
        result = lhs.fVal == rhs.fVal
      of ntLitInt:
        result = lhs.fVal == toFloat(rhs.iVal)
      else: discard
    of ntIdent:
      let lhs = c.getValue(lhs, scopetables)
      if likely(lhs != nil):
        return c.infixEvaluator(lhs, rhs, infixOp, scopetables)
    of ntDotExpr:
      let x = c.dotEvaluator(lhs, scopetables)
      result = c.infixEvaluator(x, rhs, infixOp, scopetables)
    else: discard
  of NE:
    case lhs.nt:
    of ntLitBool:
      case rhs.nt
      of ntLitBool:
        result = lhs.bVal != rhs.bVal
      else: discard
    of ntLitString:
      case rhs.nt
      of ntLitString:
        result = lhs.sVal != rhs.sVal
      else: discard
    of ntLitInt:
      case rhs.nt
      of ntLitInt:
        result = lhs.iVal != rhs.iVal
      of ntLitFloat:
        result = toFloat(lhs.iVal) != rhs.fVal
      else: discard
    of ntLitFloat:
      case rhs.nt
      of ntLitFloat:
        result = lhs.fVal != rhs.fVal
      of ntLitInt:
        result = lhs.fVal != toFloat(rhs.iVal)
      else: discard
    of ntIdent:
      let lhs = c.getValue(lhs, scopetables)
      if likely(lhs != nil):
        return c.infixEvaluator(lhs, rhs, infixOp, scopetables)
    of ntDotExpr:
      let x = c.dotEvaluator(lhs, scopetables)
      result = c.infixEvaluator(x, rhs, infixOp, scopetables)
    else: discard
  of GT:
    case lhs.nt:
    of ntLitInt:
      case rhs.nt
      of ntLitInt:
        result = lhs.iVal > rhs.iVal
      of ntLitFloat:
        result = toFloat(lhs.iVal) > rhs.fVal
      else: discard
    of ntLitFloat:
      case rhs.nt
      of ntLitFloat:
        result = lhs.fVal > rhs.fVal
      of ntLitInt:
        result = lhs.fVal > toFloat(rhs.iVal)
      else: discard
    of ntIdent:
      let lhs = c.getValue(lhs, scopetables)
      if likely(lhs != nil):
        return c.infixEvaluator(lhs, rhs, infixOp, scopetables)
    else: discard # handle float
  of GTE:
    case lhs.nt:
    of ntLitInt:
      case rhs.nt
      of ntLitInt:
        result = lhs.iVal >= rhs.iVal
      of ntLitFloat:
        result = toFloat(lhs.iVal) >= rhs.fVal
      else: discard
    of ntLitFloat:
      case rhs.nt
      of ntLitFloat:
        result = lhs.fVal >= rhs.fVal
      of ntLitInt:
        result = lhs.fVal >= toFloat(rhs.iVal)
      else: discard
    of ntIdent:
      let lhs = c.getValue(lhs, scopetables)
      if likely(lhs != nil):
        return c.infixEvaluator(lhs, rhs, infixOp, scopetables)
    else: discard # handle float
  of LT:
    case lhs.nt:
    of ntLitInt:
      case rhs.nt
      of ntLitInt:
        result = lhs.iVal < rhs.iVal
      of ntLitFloat:
        result = toFloat(lhs.iVal) < rhs.fVal
      else: discard
    of ntLitFloat:
      case rhs.nt
      of ntLitFloat:
        result = lhs.fVal < rhs.fVal
      of ntLitInt:
        result = lhs.fVal < toFloat(rhs.iVal)
      else: discard
    of ntIdent:
      let lhs = c.getValue(lhs, scopetables)
      if likely(lhs != nil):
        return c.infixEvaluator(lhs, rhs, infixOp, scopetables)
    else: discard
  of LTE:
    case lhs.nt:
    of ntLitInt:
      case rhs.nt
      of ntLitInt:
        result = lhs.iVal <= rhs.iVal
      of ntLitFloat:
        result = toFloat(lhs.iVal) <= rhs.fVal
      else: discard
    of ntLitFloat:
      case rhs.nt
      of ntLitFloat:
        result = lhs.fVal <= rhs.fVal
      of ntLitInt:
        result = lhs.fVal <= toFloat(rhs.iVal)
      else: discard
    of ntIdent:
      let lhs = c.getValue(lhs, scopetables)
      if likely(lhs != nil):
        return c.infixEvaluator(lhs, rhs, infixOp, scopetables)
    else: discard # handle float
  of AND:
    case lhs.nt
    of ntInfixExpr:
      result = c.infixEvaluator(lhs.infixLeft, lhs.infixRight, lhs.infixOp, scopetables)
      if result:
        case rhs.nt
        of ntInfixExpr:
          return c.infixEvaluator(rhs.infixLeft, rhs.infixRight, rhs.infixOp, scopetables)
        else: discard # todo
    else: discard
  of OR:
    case lhs.nt
    of ntInfixExpr:
      result = c.infixEvaluator(lhs.infixLeft, lhs.infixRight, lhs.infixOp, scopetables)
      if not result:
        case rhs.nt
        of ntInfixExpr:
          return c.infixEvaluator(rhs.infixLeft, rhs.infixRight, rhs.infixOp, scopetables)
        else: discard # todo
    else: discard # todo
  else: discard # todo

proc getValues(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): seq[Node] =
  add result, c.getValue(node.infixLeft, scopetables)
  add result, c.getValue(node.infixRight, scopetables)

proc getValue(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node =
  case node.nt
  of ntIdent:
    # evaluates an identifier
    let some = c.getScope(node.identName, scopetables)
    if likely(some.scopeTable != nil):
      return c.getValue(some.scopeTable[node.identName].varValue, scopetables)
    if node.identName == "this":
      return c.data["local"].toTimNode
    if node.identName == "app":
      return c.data["global"].toTimNode
    compileErrorWithArgs(undeclaredVariable, [node.identName])
  of ntAssignableSet, ntIndexRange:
    # return literal nodes
    result = node
  of ntInfixExpr:
    # evaluate infix expressions
    case node.infixOp
    of AMP:
      result = ast.newNode(ntLitString)
      let vNodes: seq[Node] = c.getValues(node, scopetables)
      for vNode in vNodes:
        add result.sVal, vNode.toString()
    else:
      result = ast.newNode(ntLitBool)
      result.bVal = c.infixEvaluator(node.infixLeft, node.infixRight, node.infixOp, scopetables)
  of ntDotExpr:
    # evaluate dot expressions
    result = c.dotEvaluator(node, scopetables)
  of ntBracketExpr:
    result = c.bracketEvaluator(node, scopetables)
  of ntMathInfixExpr:
    # evaluate a math expression and returns its value
    result = c.mathInfixEvaluator(node.infixMathLeft,
        node.infixMathRight, node.infixMathOp, scopetables)
  of ntCall:
    # evaluate a function call and return the result
    # if the retun type is not void, otherwise nil
    result = c.fnCall(node, scopetables)
  else: discard

template calcInfixEval() {.dirty.} =
  let lhs = c.mathInfixEvaluator(lhs.infixMathLeft, lhs.infixMathRight, lhs.infixMathOp, scopetables)
  if likely(lhs != nil):
    return c.mathInfixEvaluator(lhs, rhs, op, scopetables)

template calcInfixNest() {.dirty.} =
  let rhs = c.mathInfixEvaluator(rhs.infixMathLeft, rhs.infixMathRight, rhs.infixMathOp, scopetables)
  if likely(rhs != nil):
    return c.mathInfixEvaluator(lhs, rhs, op, scopetables)

template calcIdent {.dirty.} =
  let lhs = c.getValue(lhs, scopetables)
  if likely(lhs != nil):
    return c.mathInfixEvaluator(lhs, rhs, op, scopetables)

proc mathInfixEvaluator(c: var HtmlCompiler, lhs, rhs: Node,
    op: MathOp, scopetables: var seq[ScopeTable]): Node =
  ## Evaluates a math expression and returns a new Node
  case op
  of mPlus:
    case lhs.nt
    of ntLitFloat:
      result = newNode(ntLitFloat)
      case rhs.nt
      of ntLitFloat:
        result.fVal = lhs.fVal + rhs.fVal
      of ntLitInt:
        result.fVal = lhs.fVal + toFloat(rhs.iVal)
      of ntIdent:
        let rhs = c.getValue(rhs, scopetables)
        if likely(rhs != nil):
          return c.mathInfixEvaluator(lhs, rhs, op, scopetables) 
      of ntMathInfixExpr: calcInfixNest()
      else: discard
    of ntLitInt:
      case rhs.nt
      of ntLitFloat:
        result = newNode(ntLitFloat)
        result.fVal = toFloat(lhs.iVal) + rhs.fVal
      of ntLitInt:
        result = newNode(ntLitInt)
        result.iVal = lhs.iVal + rhs.iVal
      of ntIdent:
        let rhs = c.getValue(rhs, scopetables)
        if likely(rhs != nil):
          return c.mathInfixEvaluator(lhs, rhs, op, scopetables)    
      of ntMathInfixExpr: calcInfixNest()
      else: discard
    of ntIdent: calcIdent()
    of ntMathInfixExpr: calcInfixEval()
    else: discard
  of mMinus:
    case lhs.nt
    of ntLitFloat:
      result = newNode(ntLitFloat)
      case rhs.nt
      of ntLitFloat:
        result.fVal = lhs.fVal - rhs.fVal
      of ntLitInt:
        result.fVal = lhs.fVal - toFloat(rhs.iVal)
      of ntIdent:
        let rhs = c.getValue(rhs, scopetables)
        if likely(rhs != nil):
          return c.mathInfixEvaluator(lhs, rhs, op, scopetables) 
      of ntMathInfixExpr: calcInfixNest()
      else: discard
    of ntLitInt:
      case rhs.nt
      of ntLitFloat:
        result = newNode(ntLitFloat)
        result.fVal = toFloat(lhs.iVal) - rhs.fVal
      of ntLitInt:
        result = newNode(ntLitInt)
        result.iVal = lhs.iVal - rhs.iVal
      of ntIdent:
        let rhs = c.getValue(rhs, scopetables)
        if likely(rhs != nil):
          return c.mathInfixEvaluator(lhs, rhs, op, scopetables) 
      of ntMathInfixExpr: calcInfixNest()
      else: discard
    of ntIdent: calcIdent()
    of ntMathInfixExpr: calcInfixEval()
    else: discard
  of mMulti:
    case lhs.nt
    of ntLitFloat:
      result = newNode(ntLitFloat)
      case rhs.nt
      of ntLitFloat:
        result.fVal = lhs.fVal * rhs.fVal
      of ntLitInt:
        result.fVal = lhs.fVal * toFloat(rhs.iVal)
      of ntIdent:
        let rhs = c.getValue(rhs, scopetables)
        if likely(rhs != nil):
          return c.mathInfixEvaluator(lhs, rhs, op, scopetables) 
      of ntMathInfixExpr: calcInfixNest()
      else: discard
    of ntLitInt:
      case rhs.nt
      of ntLitFloat:
        result = newNode(ntLitFloat)
        result.fVal = toFloat(lhs.iVal) * rhs.fVal
      of ntLitInt:
        result = newNode(ntLitInt)
        result.iVal = lhs.iVal * rhs.iVal
      of ntIdent:
        let rhs = c.getValue(rhs, scopetables)
        if likely(rhs != nil):
          return c.mathInfixEvaluator(lhs, rhs, op, scopetables) 
      of ntMathInfixExpr: calcInfixNest()
      of ntDotExpr:
        let rhs = c.dotEvaluator(rhs, scopetables)
        return c.mathInfixEvaluator(lhs, rhs, op, scopetables)
      else: discard
    of ntIdent: calcIdent()
    of ntMathInfixExpr: calcInfixEval()
    else: discard
  of mDiv:
    # todo fix div
    case lhs.nt
    of ntLitFloat:
      result = newNode(ntLitFloat)
      case rhs.nt
      of ntLitFloat:
        result.fVal = lhs.fVal / rhs.fVal
      of ntLitInt:
        result.fVal = lhs.fVal / toFloat(rhs.iVal)
      of ntIdent:
        let rhs = c.getValue(rhs, scopetables)
        if likely(rhs != nil):
          return c.mathInfixEvaluator(lhs, rhs, op, scopetables) 
      of ntMathInfixExpr: calcInfixNest()
      else: discard
    of ntLitInt:
      case rhs.nt
      of ntLitFloat:
        result = newNode(ntLitFloat)
        result.fVal = toFloat(lhs.iVal) / rhs.fVal
      of ntLitInt:
        result = newNode(ntLitInt)
        result.iVal = lhs.iVal div rhs.iVal
      of ntIdent:
        let rhs = c.getValue(rhs, scopetables)
        if likely(rhs != nil):
          return c.mathInfixEvaluator(lhs, rhs, op, scopetables) 
      of ntMathInfixExpr: calcInfixNest()
      of ntDotExpr:
        let rhs = c.dotEvaluator(rhs, scopetables)
        return c.mathInfixEvaluator(lhs, rhs, op, scopetables)
      else: discard
    of ntIdent: calcIdent()
    of ntMathInfixExpr: calcInfixEval()
    else: discard
  else: discard

template evalBranch(branch: Node, body: untyped) =
  case branch.nt
  of ntInfixExpr, ntMathInfixExpr:
    if c.infixEvaluator(branch.infixLeft, branch.infixRight,
        branch.infixOp, scopetables):
      newScope(scopetables)
      body
      clearScope(scopetables)
      return # condition is thruty
  of ntIdent:
    if c.infixEvaluator(branch, boolDefault, EQ, scopetables):
      newScope(scopetables)
      body
      clearScope(scopetables)
      return # condition is thruty
  of ntDotExpr:
    let x = c.dotEvaluator(branch, scopetables)
    if likely(x != nil):
      if c.infixEvaluator(x, boolDefault, EQ, scopetables):
        newScope(scopetables)
        body
        clearScope(scopetables)
        return # condition is thruty
  else: discard

proc evalCondition(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node {.discardable.} =
  # Evaluates condition branches
  evalBranch node.condIfBranch.expr:
    result = c.walkNodes(node.condIfBranch.body, scopetables)
  if node.condElifBranch.len > 0:
    # handle `elif` branches
    for elifbranch in node.condElifBranch:
      evalBranch elifBranch.expr:
        result = c.walkNodes(elifbranch.body, scopetables)
  if node.condElseBranch.len > 0:
    # handle `else` branch
    result = c.walkNodes(node.condElseBranch, scopetables)

proc evalConcat(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  var x, y: Node
  x = c.getValue(node.infixLeft, scopetables)
  y = c.getValue(node.infixRight, scopetables)
  if likely(x != nil and y != nil):
    write x, true, false
    write y, true, false

template loopEvaluator(kv, items: Node) =
  case items.nt:
  of ntLitString:
    case kv.nt
    of ntVariableDef:
      for x in items.sVal:
        newScope(scopetables)
        node.loopItem.varValue = ast.Node(nt: ntLitString, sVal: $(x))
        c.varExpr(node.loopItem, scopetables)
        c.walkNodes(node.loopBody, scopetables)
        clearScope(scopetables)
        node.loopItem.varValue = nil
    else: discard # todo error
  of ntLitArray:
    case kv.nt
    of ntVariableDef:
      for x in items.arrayItems:
        newScope(scopetables)
        node.loopItem.varValue = x
        c.varExpr(node.loopItem, scopetables)
        c.walkNodes(node.loopBody, scopetables)
        clearScope(scopetables)
        node.loopItem.varValue = nil
    else: discard # todo error
  of ntLitObject:
    case kv.nt
    of ntVariableDef:
      for x, y in items.objectItems:
        newScope(scopetables)
        node.loopItem.varValue = y
        c.varExpr(node.loopItem, scopetables)
        c.walkNodes(node.loopBody, scopetables)
        clearScope(scopetables)
        node.loopItem.varValue = nil
    of ntIdentPair:
      for x, y in items.objectItems:
        newScope(scopetables)
        let kvar = ast.newNode(ntLitString)
        kvar.sVal = x
        node.loopItem.identPairs[0].varValue = kvar
        node.loopItem.identPairs[1].varValue = y
        c.varExpr(node.loopItem.identPairs[0], scopetables)
        c.varExpr(node.loopItem.identPairs[1], scopetables)
        c.walkNodes(node.loopBody, scopetables)
        clearScope(scopetables)
        node.loopItem.identPairs[0].varValue = nil
        node.loopItem.identPairs[1].varValue = nil
    else: discard
  else:
    let x = @[ntLitString, ntLitArray, ntLitObject]
    compileErrorWithArgs(typeMismatch, [$(items.nt), x.join(" ")])

proc evalLoop(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]) =
  # Evaluates a `for` loop
  case node.loopItems.nt
  of ntIdent:
    let some = c.getScope(node.loopItems.identName, scopetables)
    if likely(some.scopeTable != nil):
      let items = some.scopeTable[node.loopItems.identName]
      loopEvaluator(node.loopItem, items.varValue)
    else: compileErrorWithArgs(undeclaredVariable, [node.loopItems.identName])
  of ntDotExpr:
    let items = c.dotEvaluator(node.loopItems, scopetables)
    if likely(items != nil):
      loopEvaluator(node.loopItem, items)
    else:
      compileErrorWithArgs(undeclaredVariable, [node.loopItems.lhs.identName])
  of ntLitArray:
    loopEvaluator(node.loopItem, node.loopItems)
  of ntBracketExpr:
    let items = c.bracketEvaluator(node.loopItems, scopetables)
    loopEvaluator(node.loopItem, items)
  else:
    compileErrorWithArgs(invalidIterator)

proc typeCheck(c: var HtmlCompiler, x, node: Node): bool =
  if unlikely(x.nt != node.nt):
    case x.nt
    of ntMathInfixExpr, ntLitInt, ntLitFloat:
      return node.nt in {ntLitInt, ntLitFloat, ntMathInfixExpr} 
    else: discard
    compileErrorWithArgs(typeMismatch, [$(node.nt), $(x.nt)])
  result = true

proc typeCheck(c: var HtmlCompiler, node: Node, expect: NodeType): bool =
  if unlikely(node.nt != expect):
    compileErrorWithArgs(typeMismatch, [$(node.nt), $(expect)])
  result = true

#
# Compile Handlers
#
proc checkObjectStorage(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): bool =
  # Check object storage
  for k, v in node.objectItems.mpairs:
    case v.nt
    of ntIdent:
      var valNode = c.getValue(v, scopetables)
      if likely(valNode != nil):
        # todo something with safe var
        # if v.identSafe:
        #   v = valNode
        #   case v.nt
        #   of ntLitString:
        #     v.sVal = xmltree.escape(v.sVal)
        #   else: discard
        # else:
        v = valNode
      else: return
    else: discard
  result = true

proc checkArrayStorage(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): bool =
  # Check array storage
  for v in node.arrayItems.mitems:
    case v.nt
    of ntIdent:
      var valNode = c.getValue(v, scopetables)
      if likely(valNode != nil):
        v = valNode
      else: return
    else: discard
  result = true

proc varExpr(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  # Evaluates a variable
  if likely(not c.inScope(node.varName, scopetables)):
    case node.varValue.nt
    of ntLitObject:
      if c.checkObjectStorage(node.varValue, scopetables):
        c.stack(node.varName, node, scopetables)
    of ntLitArray:
      if c.checkArrayStorage(node.varValue, scopetables):
        c.stack(node.varName, node, scopetables)
    of ntIdent:
      if unlikely(not c.inScope(node.varValue.identName, scopetables)):
        compileErrorWithArgs(undeclaredVariable, [node.varValue.identName])
    else: discard
    c.stack(node.varName, node, scopetables)
  else: compileErrorWithArgs(varRedefine, [node.varName])

proc assignExpr(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  # Handle assignment expressions
  let some = c.getScope(node.asgnIdent, scopetables)
  if likely(some.scopeTable != nil):
    let varNode = some.scopeTable[node.asgnIdent]
    if likely(c.typeCheck(varNode.varValue, node.asgnVal)):
      if likely(not varNode.varImmutable):
        varNode.varValue = c.getValue(node.asgnVal, scopetables)
      else:
        compileErrorWithArgs(varImmutable, [varNode.varName])

proc fnDef(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  # Handle function definitions
  if likely(not c.inScope(node.fnIdent, scopetables)):
    if node.fnParams.len > 0:
      for k, p in node.fnParams:
        if p.pImplVal != nil:
          if p.pImplVal.nt != p.pType:
            compileErrorWithArgs(typeMismatch, [$(p.pImplVal.nt), $p.pType], p.meta)
    # if node.fnReturnType != ntUnknown:
      # check if function has a return type
      # where tkUnknown acts like a void
      
    c.stack(node.fnIdent, node, scopetables)
  else: compileErrorWithArgs(fnRedefine, [node.fnIdent])

proc fnCall(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node =
  # Handle function calls
  let some = c.getScope(node.callIdent, scopetables)
  if likely(some.scopeTable != nil):
    newScope(scopetables)
    let fnNode = some.scopeTable[node.callIdent]
    if fnNode.fnParams.len > 0:
      # add params to the stack
      for k, p in fnNode.fnParams:
        var x = ast.newVariable(k, p.pImplVal, p.meta)
        c.stack(k, x, scopetables)
    if node.callArgs.len == fnNode.fnParams.len:
      # checking if the number of given args
      # is matching the number of parameters
      if node.callArgs.len > 0:
        var i = 0
        for k, p in fnNode.fnParams:
          case node.callArgs[i].nt
          of ntIdent, ntMathInfixExpr, ntInfixExpr:
            var valNode = c.getValue(node.callArgs[i], scopetables)
            if not c.typeCheck(valNode, p.pType):
              return # error > type mismatch
            let someParam = c.getScope(k, scopetables)
            if likely(someParam.scopeTable != nil):
              someParam.scopeTable[k].varValue = valNode
          else:
            if c.typeCheck(node.callArgs[i], p.pType):
              let someParam = c.getScope(k, scopetables)
              echo node.callArgs[i]
              someParam.scopeTable[k].varValue = node.callArgs[i]
            else: return
          inc i
    elif node.callArgs.len > fnNode.fnParams.len:
      compileErrorWithArgs(fnExtraArg, [$(node.callArgs.len), $(fnNode.fnParams.len)])
    elif node.callArgs.len < fnNode.fnParams.len:
      # check if function parameters has any implicit values
      var i = 0
      for k, p in fnNode.fnParams:
        if p.pImplVal != nil:
          let someParam = c.getScope(k, scopetables)
          someParam.scopeTable[k].varValue = p.pImplVal
        else:
          compileErrorWithArgs(typeMismatch, ["none", $p.pType], p.meta)
        inc i
    result = c.walkNodes(fnNode.fnBody, scopetables)
    if result != nil:
      if unlikely(not c.typeCheck(result, fnNode.fnReturnType)):
        clearScope(scopetables)
        return nil
    clearScope(scopetables)
  else: compileErrorWithArgs(fnUndeclared, [node.callIdent])

#
# Html Handler
#
proc getId(c: HtmlCompiler, node: Node): string =
  # Get ID html attribute
  add result, indent("id=", 1) & "\""
  let attrNode = node.attrs["id"][0]
  case attrNode.nt
  of ntLitString:
    add result, attrNode.sVal
  else: discard # todo
  add result, "\""

proc getAttrs(c: var HtmlCompiler, attrs: HtmlAttributes,
    scopetables: var seq[ScopeTable], xel = newStringOfCap(0)): string =
  # Write HTMLAttributes
  var i = 0
  var skipQuote: bool
  let len = attrs.len
  for k, attrNodes in attrs:
    var attrStr: seq[string]
    if not c.isClientSide:
      add result, indent("$1=" % [k], 1) & "\""
    for attrNode in attrNodes:
      case attrNode.nt
      of ntAssignableSet:
        add attrStr, c.toString(attrNode, scopetables)
      of ntIdent:
        let xVal = c.getValue(attrNode, scopetables)
        if likely(xVal != nil):
          add attrStr, xVal.toString()
        else: return # undeclaredVariable
      of ntCall:
        let xVal = c.fnCall(attrNode, scopetables)
        if likely(xVal != nil):
          add attrStr, xVal.toString()
      of ntDotExpr:
        let xVal = c.dotEvaluator(attrNode, scopetables)
        if likely(xVal != nil):
          add attrStr, xVal.toString()
        else: return # undeclaredVariable
      else: discard
    if not c.isClientSide:
      add result, attrStr.join(" ")
      if not skipQuote and i != len:
        add result, "\""
      else:
        skipQuote = false
      inc i
    else:
      add result, domSetAttribute % [xel, k, attrStr.join(" ")]

const voidElements = [tagArea, tagBase, tagBr, tagCol,
  tagEmbed, tagHr, tagImg, tagInput, tagLink, tagMeta,
  tagParam, tagSource, tagTrack, tagWbr, tagCommand,
  tagKeygen, tagFrame]

template htmlblock(x: Node, body) =
  block:
    case c.minify:
    of false:
      if c.stickytail == true:
        c.stickytail = false
      add c.output, c.getIndent(node.meta)
      if c.start:
        c.start = false # todo find a better method to exclude inserting \n at start
    else: discard
    let t = x.getTag()
    add c.output, "<"
    add c.output, t
    if x.attrs != nil:
      if x.attrs.hasKey("id"):
        add c.output, c.getId(x)
        x.attrs.del("id") # not needed anymore
      if x.attrs.len > 0:
        add c.output, c.getAttrs(x.attrs, scopetables)
    add c.output, ">"
    body
    case x.tag
    of voidElements:
      discard
    else:
      case c.minify:
      of false:
        add c.output, c.getIndent(node.meta) 
      else: discard
      add c.output, "</"
      add c.output, t
      add c.output, ">"
      c.stickytail = false

proc htmlElement(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  # Handle HTML element
  htmlblock node:
    c.walkNodes(node.nodes, scopetables, ntHtmlElement)

proc evaluatePartials(c: var HtmlCompiler, includes: seq[string], scopetables: var seq[ScopeTable]) =
  # Evaluate included partials
  for x in includes:
    if likely(c.ast.partials.hasKey(x)):
      c.walkNodes(c.ast.partials[x][0].nodes, scopetables)

#
# JS API
#
proc createHtmlElement(c: var HtmlCompiler, x: Node, scopetables: var seq[ScopeTable], pEl: string) =
  ## Create a new HtmlElement
  let xel = "el" & $(c.jsCountEl)
  add c.jsOutputCode, domCreateElement % [xel, x.getTag()]
  if x.attrs != nil:
    add c.jsOutputCode, c.getAttrs(x.attrs, scopetables, xel)
  inc c.jsCountEl
  if x.nodes.len > 0:
    c.walkNodes(x.nodes, scopetables, xel = xel)
  if pEl.len > 0:
    add c.jsOutputCode,
      domInsertAdjacentElement % [pEl, xel]
  else:
    add c.jsOutputCode,
      domInsertAdjacentElement % ["document.querySelector('" & c.jsTargetElement & "')", xel]

#
# Main nodes walker
#
proc walkNodes(c: var HtmlCompiler, nodes: seq[Node],
    scopetables: var seq[ScopeTable], parentNodeType: NodeType = ntUnknown,
    xel = newStringOfCap(0)): Node {.discardable.} =
  # Evaluate a seq[Node] nodes
  for i in 0..nodes.high:
    case nodes[i].nt
    of ntHtmlElement:
      if not c.isClientSide:
        c.htmlElement(nodes[i], scopetables)
      else:
        c.createHtmlElement(nodes[i], scopetables, xel)
    of ntIdent:
      let x: Node = c.getValue(nodes[i], scopetables)
      if not c.isClientSide:
        write x, true, nodes[i].identSafe
      else:
        add c.jsOutputCode, domInnerText % [xel, x.toString()]
    of ntDotExpr:
      let x: Node = c.dotEvaluator(nodes[i], scopetables)
      if not c.isClientSide:
        write x, true, false
      else:
        add c.jsOutputCode, domInnerText % [xel, x.toString()]
    of ntVariableDef:
      c.varExpr(nodes[i], scopetables)
    of ntCommandStmt:
      case nodes[i].cmdType
      of cmdReturn:
        return c.evalCmd(nodes[i], scopetables)
      else:
        discard c.evalCmd(nodes[i], scopetables)
    of ntAssignExpr:
      c.assignExpr(nodes[i], scopetables)
    of ntConditionStmt:
      result = c.evalCondition(nodes[i], scopetables)
      if result != nil:
        return # a resulted ntCommandStmt Node of type cmdReturn
    of ntLoopStmt:
      c.evalLoop(nodes[i], scopetables)
    of ntLitString, ntLitInt, ntLitFloat, ntLitBool:
      if not c.isClientSide:
        write nodes[i], true, false
      else:
        add c.jsOutputCode, domInnerText % [xel, nodes[i].toString()]
    of ntMathInfixExpr:
      let x: Node = c.mathInfixEvaluator(nodes[i].infixMathLeft,
                      nodes[i].infixMathRight, nodes[i].infixMathOp, scopetables)
      write x, true, false
    of ntLitFunction:
      c.fnDef(nodes[i], scopetables)
    of ntInfixExpr:
      case nodes[i].infixOp
      of AMP:
        c.evalConcat(nodes[i], scopetables)
      else: discard # todo
    of ntViewLoader:
      c.head = c.output
      reset(c.output)
    of ntCall:
      case parentNodeType
      of ntHtmlElement:
        let returnNode = c.fnCall(nodes[i], scopetables)
        if likely(returnNode != nil):
          write returnNode, true, false
      else:
        discard c.fnCall(nodes[i], scopetables)
    of ntInclude:
      c.evaluatePartials(nodes[i].includes, scopetables)
    of ntJavaScriptSnippet:
      add c.jsOutput, nodes[i].snippetCode
    of ntJsonSnippet:
      try:
        add c.jsonOutput,
          jsony.toJson(jsony.fromJson(nodes[i].snippetCode))
      except jsony.JsonError as e:
        compileErrorWithArgs(internalError, nodes[i].meta, [e.msg])
    of ntClientBlock:
      c.jsTargetElement = nodes[i].clientTargetElement
      c.isClientSide = true
      c.walkNodes(nodes[i].clientStmt, scopetables)
      add c.jsOutputCode, "}"
      add c.jsOutput,
        "document.addEventListener('DOMContentLoaded', function(){"
      add c.jsOutput, c.jsOutputCode
      add c.jsOutput, "});"
      c.jsOutputCode = "{"
      setLen(c.jsTargetElement, 0)
      reset(c.jsCountEl)
      c.isClientSide = false
    else: discard

#
# Public API
#

when not defined timStandalone:
  proc newCompiler*(engine: TimEngine, ast: Ast, tpl: TimTemplate, minify = true,
      indent = 2, data: JsonNode = newJObject()): HtmlCompiler =
    ## Create a new instance of `HtmlCompiler`
    assert indent in [2, 4]
    data["global"] = engine.getGlobalData()
    result =
      HtmlCompiler(
        ast: ast,
        tpl: tpl,
        start: true,
        tplType: tpl.getType,
        logger: Logger(filePath: tpl.getSourcePath()),
        data: data,
        minify: minify
      )
    if minify: setLen(result.nl, 0)
    var scopetables = newSeq[ScopeTable]()
    result.walkNodes(result.ast.nodes, scopetables)
else:
  proc newCompiler*(ast: Ast, tpl: TimTemplate,
      minify = true, indent = 2): HtmlCompiler =
    ## Create a new instance of `HtmlCompiler`
    assert indent in [2, 4]
    result =
      HtmlCompiler(
        ast: ast,
        tpl: tpl,
        start: true,
        tplType: tpl.getType,
        logger: Logger(filePath: tpl.getSourcePath()),
        minify: minify
      )
    if minify: setLen(result.nl, 0)
    var scopetables = newSeq[ScopeTable]()
    result.walkNodes(result.ast.nodes, scopetables)

proc newCompiler*(ast: Ast, minify = true, indent = 2): HtmlCompiler =
  ## Create a new instance of `HtmlCompiler
  assert indent in [2, 4]
  var c = HtmlCompiler(
    ast: ast,
    start: true,
    tplType: ttView,
    logger: Logger(),
    minify: minify
  )
  if minify: setLen(result.nl, 0)
  var scopetables = newSeq[ScopeTable]()
  c.walkNodes(c.ast.nodes, scopetables)
  return c

proc getHtml*(c: HtmlCompiler): string =
  ## Get the compiled HTML
  if c.tplType == ttView and c.jsonOutput.len > 0:
    add result, "\n" & "<script type=\"application/json\">"
    add result, c.jsonOutput
    add result, "</script>"
  add result, c.output
  if c.tplType == ttView and c.jsOutput.len > 0:
    add result, "\n" & "<script type=\"text/javascript\">"
    add result, c.jsOutput
    add result, "</script>"

proc getHead*(c: HtmlCompiler): string =
  ## Returns the top of a split layout
  assert c.tplType == ttLayout
  result = c.head

proc getTail*(c: HtmlCompiler): string =
  ## Retruns the tail of a layout
  assert c.tplType == ttLayout
  if c.jsOutput.len > 0:
    result = "\n" & "<script type=\"text/javascript\">"
    add result, c.jsOutput
    add result, "\n" & "</script>"
    add result, c.getHtml
  else:
    result = c.getHtml