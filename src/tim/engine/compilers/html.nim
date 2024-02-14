# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, strutils, json,
  jsonutils, options, terminal]

import pkg/jsony
import ../ast, ../logging, ./js

from std/xmltree import escape
from ../meta import TimEngine, TimTemplate, TimTemplateType,
  getType, getSourcePath

import ./tim # TimCompiler object

type
  HtmlCompiler* = object of TimCompiler
    ## Object of a TimCompiler to output `HTML`
    when not defined timStandalone:
      globalScope: ScopeTable = ScopeTable()
      data: JsonNode
    jsComp: seq[JSCompiler]

# Forward Declaration
proc evaluateNodes(c: var HtmlCompiler, nodes: seq[Node],
    scopetables: var seq[ScopeTable], parentNodeType: NodeType = ntUnknown): Node {.discardable.}
proc typeCheck(c: var HtmlCompiler, x, node: Node): bool
proc typeCheck(c: var HtmlCompiler, node: Node, expect: NodeType): bool
proc mathInfixEvaluator(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node
proc dotEvaluator(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node
proc getValue(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node
proc fnCall(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node
proc hasError*(c: HtmlCompiler): bool = c.hasErrors

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
        return
    of ntLitFunction:
      if scopetables.len > 0:
        scopetables[^1][node.fnIdent] = node
        return
    else: discard
    c.globalScope[key] = node

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

proc evalJson(c: var HtmlCompiler, storage: JsonNode, lhs, rhs: Node): JsonNode =
  # Evaluate a JSON node
  if lhs == nil:
    if likely(storage.hasKey(rhs.identName)):
      return storage[rhs.identName]
    else:
      c.logger.error(undeclaredField, rhs.meta[0], rhs.meta[1], [rhs.identName])
      c.hasErrors = true

proc evalStorage(c: var HtmlCompiler, node: Node): JsonNode =
  case node.lhs.nt
  of ntIdent:
    if node.lhs.identName == "this":
      return c.evalJson(c.data["local"], nil, node.rhs)
    if node.lhs.identName == "app":
      return c.evalJson(c.data["global"], nil, node.rhs)
  else: discard

proc walkAccessorStorage(c: var HtmlCompiler,
    lhs, rhs: Node, scopetables: var seq[ScopeTable]): Node =
  case lhs.nt
  of ntLitObject:
    try:
      result = lhs.objectItems[rhs.identName]
    except KeyError:
      c.logger.error(undeclaredField, rhs.meta[0], rhs.meta[1], [rhs.identName])
  of ntDotExpr:
    let x = c.walkAccessorStorage(lhs.lhs, lhs.rhs, scopetables)
    if likely(x != nil):
      return c.walkAccessorStorage(x, rhs, scopetables)
  of ntIdent:
    let x = c.fromScope(lhs.identName, scopetables)
    if likely(x != nil):
      result = c.walkAccessorStorage(x.varValue, rhs, scopetables)
  of ntLitArray:
    discard # todo handle accessor storage for arrays
  else: discard

proc dotEvaluator(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node =
  # Evaluate dot expressions
  case node.storageType
  of localStorage, globalStorage:
    let x = c.evalStorage(node)
    if likely(x != nil):
      result = toTimNode(x)
  of scopeStorage:
    return c.walkAccessorStorage(node.lhs, node.rhs, scopetables)

proc writeDotExpr(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  # Handle dot expressions
  let someValue: Node = c.dotEvaluator(node, scopetables)
  if likely(someValue != nil):
    add c.output, someValue.toString()
    c.stickytail = true

proc evalCmd(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node =
  # Evaluate a command
  var val: Node
  case node.cmdValue.nt
  of ntIdent:
    let some = c.getScope(node.cmdValue.identName, scopetables)
    if likely(some.scopeTable != nil):
      val = some.scopeTable[node.cmdValue.identName].varValue
    else:
      compileErrorWithArgs(undeclaredVariable, [node.cmdValue.identName])
  of ntAssignableSet:
    val = node.cmdValue
  of ntMathInfixExpr:
    val = c.mathInfixEvaluator(node.cmdValue, scopetables)
  of ntCall:
    val = c.fnCall(node.cmdValue, scopetables)
  of ntDotExpr:
    let someValue: Node = c.dotEvaluator(node.cmdValue, scopetables)
    if likely(someValue != nil):
      case node.cmdType
      of cmdEcho:
        print(someValue)
      else: discard
    return
  else: discard
  if val != nil:
    case node.cmdType
    of cmdEcho:
      val.meta = node.cmdValue.meta
      print(val)
    of cmdReturn:
      return val
    else: discard

proc infixEvaluator(c: var HtmlCompiler, lhs, rhs: Node,
    infixOp: InfixOp, scopetables: var seq[ScopeTable]): bool =
  # Evaluates infix expressions
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
      var lhs = c.fromScope(lhs.identName, scopetables)
      if lhs == nil or rhs == nil: return # false
      case rhs.nt
      of ntIdent:
        var rhs = c.fromScope(rhs.identName, scopetables)
        if rhs != nil:
          result = c.infixEvaluator(lhs.varValue, rhs.varValue, infixOp, scopetables)
      else:
        result = c.infixEvaluator(lhs.varValue, rhs, infixOp, scopetables)
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
    else: discard # handle float
  of AND:
    case lhs.nt
    of ntInfixExpr:
      var lh: bool = c.infixEvaluator(lhs.infixLeft, lhs.infixRight, lhs.infixOp, scopetables)
      var rh: bool
      if lh:
        case rhs.nt
        of ntInfixExpr:
          rh = c.infixEvaluator(rhs.infixLeft, rhs.infixRight, rhs.infixOp, scopetables)
        else: discard # todo
        if rh:
          return lh and rh
    else: discard
  of OR:
    case lhs.nt
    of ntInfixExpr:
      var lh: bool = c.infixEvaluator(lhs.infixLeft, lhs.infixRight, lhs.infixOp, scopetables)
      var rh: bool
      case rhs.nt
      of ntInfixExpr:
        rh = c.infixEvaluator(rhs.infixLeft, rhs.infixRight, rhs.infixOp, scopetables)
      else: discard # todo
      return lh or rh
    else: discard # todo
  else: discard # todo

proc getValues(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): seq[Node] =
  # lhs
  case node.infixLeft.nt
  of ntDotExpr:
    add result, c.dotEvaluator(node.infixLeft, scopetables)
  of ntAssignableSet:
    add result, node.infixLeft
  of ntInfixExpr:
    add result, c.getValue(node.infixLeft, scopetables)
  else: discard
  # rhs
  case node.infixRight.nt
  of ntDotExpr:
    add result, c.dotEvaluator(node.infixRight, scopetables)
  of ntAssignableSet:
    add result, node.infixRight
  of ntInfixExpr:
    add result, c.getValue(node.infixRight, scopetables)
  of ntMathInfixExpr:
    let someValue = c.mathInfixEvaluator(node.infixRight, scopetables)
    if likely(someValue != nil):
      add result, someValue
  else: discard

proc getValue(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node =
  # Get a literal node from ntIdent, ntDotExpr, ntCall, ntInfixExpr
  case node.nt
  of ntIdent:
    let some = c.getScope(node.identName, scopetables)
    if likely(some.scopeTable != nil):
      return some.scopeTable[node.identName].varValue
    compileErrorWithArgs(undeclaredVariable, [node.identName])
  of ntInfixExpr:
    case node.infixOp
    of AMP:
      result = ast.newNode(ntLitString)
      let vNodes: seq[Node] = c.getValues(node, scopetables)
      for vNode in vNodes:
        add result.sVal, vNode.sVal
    else: discard # todo
  else: discard

proc mathInfixEvaluator(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]): Node =
  ## Evaluates a math expression and returns
  ## the total as a Node value
  case node.infixMathOp
  of mPlus:
    case node.infixMathLeft.nt
    of ntLitFloat:
      result = newNode(ntLitFloat)
      case node.infixMathRight.nt
      of ntLitFloat:
        result.fVal = node.infixMathLeft.fVal + node.infixMathRight.fVal
      of ntLitInt:
        result.fVal = node.infixMathLeft.fVal + toFloat(node.infixMathRight.iVal)
      else: discard
    of ntLitInt:
      case node.infixMathRight.nt
      of ntLitFloat:
        result = newNode(ntLitFloat)
        result.fVal = toFloat(node.infixMathLeft.iVal) + node.infixMathRight.fVal
      of ntLitInt:
        result = newNode(ntLitInt)
        result.iVal = node.infixMathLeft.iVal + node.infixMathRight.iVal
      else: discard
    of ntIdent:
      let x = c.getValue(node.infixMathLeft, scopetables)
      # if likely(x != nil):
        # case x.nt
        # of ntLitInt:
        # else: discard # error
    else: discard
  else: discard

# define default value nodes
let
  intDefault = ast.newNode(ntLitInt)
  strDefault = ast.newNode(ntLitString)
  boolDefault = ast.newNode(ntLitBool)
boolDefault.bVal = true

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
    result = c.evaluateNodes(node.condIfBranch.body, scopetables)
  if node.condElifBranch.len > 0:
    # handle `elif` branches
    for elifbranch in node.condElifBranch:
      evalBranch elifBranch.expr:
        result = c.evaluateNodes(elifbranch.body, scopetables)
  if node.condElseBranch.len > 0:
    # handle `else` branch
    result = c.evaluateNodes(node.condElseBranch, scopetables)

proc evalConcat(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  case node.infixLeft.nt
  of ntDotExpr:
    c.writeDotExpr(node.infixLeft, scopetables)
  of ntAssignableSet:
    add c.output, node.infixLeft.toString()
  of ntInfixExpr:
    c.evalConcat(node.infixLeft, scopetables)
  else: discard

  case node.infixRight.nt
  of ntDotExpr:
    c.writeDotExpr(node.infixRight, scopetables)
  of ntAssignableSet:
    add c.output, node.infixRight.toString()
  of ntInfixExpr:
    c.evalConcat(node.infixRight, scopetables)
  of ntMathInfixExpr:
    let someValue = c.mathInfixEvaluator(node.infixRight, scopetables)
    if likely(someValue != nil):
      add c.output, someValue.toString()
  else: discard

template loopEvaluator(items: Node) =
  case items.nt:
    of ntLitString:
      for x in items.sVal:
        newScope(scopetables)
        node.loopItem.varValue = ast.Node(nt: ntLitString, sVal: $(x))
        c.varExpr(node.loopItem, scopetables)
        c.evaluateNodes(node.loopBody, scopetables)
        clearScope(scopetables)
    of ntLitArray:
      for x in items.arrayItems:
        newScope(scopetables)
        node.loopItem.varValue = x
        c.varExpr(node.loopItem, scopetables)
        c.evaluateNodes(node.loopBody, scopetables)
        clearScope(scopetables)
    of ntLitObject:
      for x, y in items.objectItems:
        newScope(scopetables)
        node.loopItem.varValue = y
        c.varExpr(node.loopItem, scopetables)
        c.evaluateNodes(node.loopBody, scopetables)
        clearScope(scopetables)
    else:
      let x = @[ntLitString, ntLitArray, ntLitObject]
      compileErrorWithArgs(typeMismatch, [$(items.nt), x.join(" ")])

proc evalLoop(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  # Evaluates a `for` loop
  case node.loopItems.nt
  of ntIdent:
    let some = c.getScope(node.loopItems.identName, scopetables)
    if likely(some.scopeTable != nil):
      let items = some.scopeTable[node.loopItems.identName]
      loopEvaluator(items.varValue)
    else: compileErrorWithArgs(undeclaredVariable, [node.loopItems.identName])
  of ntDotExpr:
    let items = c.dotEvaluator(node.loopItems, scopetables)
    if likely(items != nil):
      loopEvaluator(items)
    else:
      compileErrorWithArgs(undeclaredVariable, [node.loopItems.lhs.identName])
  else: return

proc typeCheck(c: var HtmlCompiler, x, node: Node): bool =
  if unlikely(x.nt != node.nt):
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
    else:
      c.stack(node.varName, node, scopetables)
  else: compileErrorWithArgs(varRedefine, [node.varName])

proc assignExpr(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  # Handle assignment expressions
  let some = c.getScope(node.asgnIdent, scopetables)
  if likely(some.scopeTable != nil):
    let varNode = some.scopeTable[node.asgnIdent]
    if likely(c.typeCheck(varNode.varValue, node.asgnVal)):
      if likely(not varNode.varImmutable):
        varNode.varValue = node.asgnVal
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
      # add available param definition
      # to current stack
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
          of ntIdent:
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
    result = c.evaluateNodes(fnNode.fnBody, scopetables)
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

proc getAttrs(c: var HtmlCompiler, attrs: HtmlAttributes, scopetables: var seq[ScopeTable]): string =
  # Write HTMLAttributes
  var i = 0
  var skipQuote: bool
  let len = attrs.len
  for k, attrNodes in attrs:
    var attrStr: seq[string]
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
    add result, attrStr.join(" ")
    if not skipQuote and i != len:
      add result, "\""
    else:
      skipQuote = false
    inc i

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
    c.evaluateNodes(node.nodes, scopetables, ntHtmlElement)

proc evaluatePartials(c: var HtmlCompiler, includes: seq[string], scopetables: var seq[ScopeTable]) =
  # Evaluate included partials
  for x in includes:
    if likely(c.ast.partials.hasKey(x)):
      c.evaluateNodes(c.ast.partials[x][0].nodes, scopetables)

proc evaluateNodes(c: var HtmlCompiler, nodes: seq[Node],
    scopetables: var seq[ScopeTable], parentNodeType: NodeType = ntUnknown): Node {.discardable.} =
  # Evaluate a seq[Node] nodes
  for i in 0..nodes.high:
    case nodes[i].nt
    of ntHtmlElement:
      c.htmlElement(nodes[i], scopetables)
    of ntIdent:
      let x = c.getValue(nodes[i], scopetables)
      if likely(x != nil):
        add c.output, x.toString(nodes[i].identSafe)
        c.stickytail = true
    of ntDotExpr:
      let someValue: Node = c.dotEvaluator(nodes[i], scopetables)
      if likely(someValue != nil):
        add c.output, someValue.toString()
        c.stickytail = true
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
      add c.output, nodes[i].toString
      c.stickytail = true
    of ntLitFunction:
      c.fnDef(nodes[i], scopetables)
    of ntInfixExpr:
      case nodes[i].infixOp
      of AMP:
        c.evalConcat(nodes[i], scopetables)
      else: discard # todo
    of ntViewLoader:
      # add c.output, c.getIndent(nodes[i].meta)
      c.head = c.output
      reset(c.output)
    of ntCall:
      case parentNodeType
      of ntHtmlElement:
        return c.fnCall(nodes[i], scopetables)
      else:
        discard c.fnCall(nodes[i], scopetables)
    of ntInclude:
      c.evaluatePartials(nodes[i].includes, scopetables)
    of ntJavaScriptSnippet:
      add c.jsOutput, nodes[i].snippetCode
    of ntJsonSnippet:
      add c.jsonOutput, nodes[i].snippetCode
    of ntClientBlock:
      var jsCompiler = js.newCompiler(nodes[i].clientStmt, nodes[i].clientTargetElement)
      # add c.jsComp, jsCompiler
      add c.jsOutput, "document.addEventListener('DOMContentLoaded', function(){"
      add c.jsOutput, jsCompiler.getOutput()
      add c.jsOutput, "})"
    else: discard

#
# Public API
#

when not defined timStandalone:
  proc newCompiler*(ast: Ast, tpl: TimTemplate, minify = true,
      indent = 2, data: JsonNode = newJObject()): HtmlCompiler =
    ## Create a new instance of `HtmlCompiler`
    assert indent in [2, 4]
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
    result.evaluateNodes(result.ast.nodes, scopetables)
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
    result.evaluateNodes(result.ast.nodes, scopetables)

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
  c.evaluateNodes(c.ast.nodes, scopetables)
  return c

proc getHtml*(c: HtmlCompiler): string =
  ## Get the compiled HTML
  result = c.output
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