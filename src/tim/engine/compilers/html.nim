# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, strutils, json,
  jsonutils, options, terminal, sequtils]

import pkg/jsony
import ./tim, ../std, ../parser

from ../meta import TimEngine, TimTemplate, TimTemplateType,
  getType, getSourcePath, getGlobalData

type
  HtmlCompiler* = object of TimCompiler
    ## Object of a TimCompiler to output `HTML`
    when not defined timStandalone:
      globalScope: ScopeTable = ScopeTable()
      data: JsonNode
      jsOutputCode: string = "{"
      jsOutputCodeDefer: string
      jsCountEl: uint
      jsTargetElement: string
    # jsComp: Table[string, JSCompiler] # todo

# Forward Declaration
proc newCompiler*(ast: Ast, minify = true, indent = 2, data = newJObject()): HtmlCompiler
proc getHtml*(c: HtmlCompiler): string

proc walkNodes(c: var HtmlCompiler, nodes: seq[Node],
    scopetables: var seq[ScopeTable], parentNodeType: NodeType = ntUnknown,
    xel = newStringOfCap(0)): Node {.discardable.}

proc typeCheck(c: var HtmlCompiler, x, node: Node, parent: Node = nil): bool

proc typeCheck(c: var HtmlCompiler, node: Node,
  expect: NodeType, parent: Node = nil): bool

proc mathInfixEvaluator(c: var HtmlCompiler, lhs,
    rhs: Node, op: MathOp, scopetables: var seq[ScopeTable]): Node

proc dotEvaluator(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable]): Node

proc infixEvaluator(c: var HtmlCompiler, lhs, rhs: Node,
    infixOp: InfixOp, scopetables: var seq[ScopeTable]): bool

proc getValue(c: var HtmlCompiler, node: Node,
  scopetables: var seq[ScopeTable]): Node

proc unsafeCall(c: var HtmlCompiler, node, fnNode: Node,
    scopetables: var seq[ScopeTable]): Node

proc fnCall(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node

proc hasError*(c: HtmlCompiler): bool = c.hasErrors # or c.logger.errorLogs.len > 0

proc bracketEvaluator(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node

proc baseIndent(c: HtmlCompiler, i: int): int =
  if c.indent == 2:
    if c.partialIndent == 0:
      int(i / c.indent)
    else:
      int((c.partialIndent + i) / c.indent) # fixing html indentation inside partials
  else: i

proc getIndent(c: HtmlCompiler, meta: Meta, skipbr = false): string =
  case meta[1]
  of 0:
    if not c.stickytail:
      if not skipbr:
        add result, c.nl
      if c.partialIndent != 0:
        add result, indent("", c.baseIndent(meta[1]))
  else:
    if not c.stickytail:
      add result, c.nl
      add result, indent("", c.baseIndent(meta[1]))

const
  domCreateElement = "let $1 = document.createElement('$2');"
  domSetAttribute = "$1.setAttribute('$2','$3');"
  domInsertAdjacentElement = "$1.insertAdjacentElement('beforeend',$2);"
  domInnerText = "$1.innerText=\"$2\";"
  stdlibPaths = ["std/system", "std/strings", "std/arrays", "std/os", "*"]

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
    of ntFunction:
      if node.fnSource notin stdlibPaths:
        if scopetables.len > 0:
          scopetables[^1][node.fnIdent] = node
        else: c.globalScope[node.fnIdent] = node
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

  proc inScope(c: HtmlCompiler, key: string,
      scopetables: var seq[ScopeTable]): bool =
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
    try:
      scopetables.delete(scopetables.high)
    except RangeDefect: discard

template notnil(x, body) =
  if likely(x != nil):
    body

template notnil(x, body, elseBody) =
  if likely(x != nil):
    body
  else:
    elseBody

# define default value nodes
let
  intDefault = ast.newNode(ntLitInt)
  strDefault = ast.newNode(ntLitString)
  boolDefault = ast.newNode(ntLitBool)
boolDefault.bVal = true

#
# Forward Declaration
#
proc varExpr(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable])

#
# AST Evaluators
#
proc dumpHook*(s: var string, v: seq[Node])
proc dumpHook*(s: var string, v: OrderedTableRef[string, Node])
# proc dumpHook*(s: var string, v: Color)

proc escapeValue(x: string): string =
  for c in x:
    case c
    of '<': add result, "&lt;"
    of '>': add result, "&gt;"
    of '&': add result, "&amp;"
    of '"': add result, "&quot;"
    of NewLines: add result, "\\n"
    of '\'': add result, "&apos;"
    else: add result, c

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
        if not escape:
          fromJson(jsony.toJson(node.objectItems)).pretty
        else:
          jsony.toJson(node.objectItems)
      of ntLitArray:
        if not escape:
          fromJson(jsony.toJson(node.arrayItems)).pretty
        else:
          jsony.toJson(node.arrayItems)
      of ntIdent:     node.identName
      else: ""
    if escape:
      result = escapeValue(result)

proc toString(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable], escape = false): string =
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
      if not escape:
        fromJson(jsony.toJson(node.objectItems)).pretty
      else:
        jsony.toJson(node.objectItems)
    of ntLitArray:
      if not escape:
        fromJson(jsony.toJson(node.arrayItems)).pretty
      else:
        jsony.toJson(node.arrayItems)
    else: ""
  if escape:
    result = escapeValue(result)

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

proc print(val: Node, identSafe = false) =
  let meta = " ($1:$2) " % [$val.meta[0], $val.meta[2]]
  stdout.styledWriteLine(
    fgGreen, "Debug",
    fgDefault, meta,
    fgMagenta, $(val.nt),
    fgDefault, "\n" & toString(val, identSafe)
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
    else: compileErrorWithArgs(invalidAccessorStorage,
        rhs.meta, [rhs.toString, $lhs.nt])
  of ntDotExpr:
    let lhs = c.walkAccessorStorage(lhs.lhs, lhs.rhs, scopetables)
    notnil lhs:
      case lhs.nt
      of ntLitObject:
        result = c.walkAccessorStorage(lhs, rhs, scopetables)
      else:
        case rhs.nt
        of ntIdent:
          rhs.identArgs.insert(lhs, 0)
          result = c.fnCall(rhs, scopetables)
          rhs.identArgs.del(0)
        else:
          result = c.walkAccessorStorage(lhs, rhs, scopetables)
  of ntIdent:
    let lhs = c.getValue(lhs, scopetables)
    notnil lhs:
      case lhs.nt
      of ntLitObject:
        return c.walkAccessorStorage(lhs, rhs, scopetables)
      else:
        case rhs.nt
        of ntIdent:
          let some = c.getScope(rhs.identName, scopetables)
          if likely(some.scopeTable != nil):
            rhs.identArgs.insert(lhs, 0)
            result = c.fnCall(rhs, scopetables) 
            rhs.identArgs.del(0)
          else: discard
        else:
          return c.walkAccessorStorage(lhs, rhs, scopetables)
  of ntBracketExpr:
    let lhs = c.bracketEvaluator(lhs, scopetables)
    if likely(lhs != nil):
      return c.walkAccessorStorage(lhs, rhs, scopetables)
  of ntLitString:
    case rhs.nt
    of ntLitInt:
      try:
        return ast.newString($(lhs.sVal[rhs.iVal]))
      except Defect:
        compileErrorWithArgs(indexDefect, lhs.meta,
          [$(rhs.iVal), "0.." & $(lhs.arrayItems.high)])
    of ntIndexRange:
      let
        l = c.getValue(rhs.rangeNodes[0], scopetables)
        r = c.getValue(rhs.rangeNodes[1], scopetables)
      if likely(l != nil and r != nil):
        let l = l.iVal
        let r = r.iVal
        try:
          case rhs.rangeLastIndex
          of false:
            result = ast.newString($(lhs.sVal[l..r]))
          of true:
            result = ast.newString($(lhs.sVal[l..^r]))
        except Defect:
          let someRange =
            if rhs.rangeLastIndex: $(l) & "..^" & $(r)
            else: $(l) & ".." & $(r)
          compileErrorWithArgs(indexDefect, lhs.meta,
            [someRange, "0.." & $(lhs.sVal.high)])
    else: discard
  of ntLitArray:
    case rhs.nt
    of ntLitInt:
      try:
        result = lhs.arrayItems[rhs.iVal]
      except Defect:
        compileErrorWithArgs(indexDefect, lhs.meta,
          [$(rhs.iVal), "0.." & $(lhs.arrayItems.high)])
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
          compileErrorWithArgs(indexDefect, lhs.meta,
            [someRange, "0.." & $(lhs.arrayItems.high)])
      else: discard # todo error?
    else:
      case rhs.nt
      of ntIdent:
        let some = c.getScope(rhs.identName, scopetables)
        if likely(some.scopeTable != nil):
          case some.scopeTable[rhs.identName].nt
          of ntFunction:
            # evaluate a function call and return the result
            # if the retun type is not void, otherwise nil
            return c.unsafeCall(lhs, some.scopeTable[rhs.identName], scopetables)
          else: discard
      else: discard
      compileErrorWithArgs(invalidAccessorStorage,
        rhs.meta, [rhs.toString, $lhs.nt])
  else: discard

proc dotEvaluator(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node =
  # Evaluate dot expressions
  case node.storageType
  of localStorage, globalStorage:
    let x = c.evalStorage(node)
    if likely(x != nil):
      return x.toTimNode
    result = getVoidNode()
  of scopeStorage:
    return c.walkAccessorStorage(node.lhs, node.rhs, scopetables)

proc bracketEvaluator(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node =
  case node.bracketStorageType
  of localStorage, globalStorage:
    let index = c.getValue(node.bracketIndex, scopetables)
    notnil index:
      var x = c.evalStorage(node.bracketLHS)
      notnil x:
        result = x.toTimNode
        return c.walkAccessorStorage(result, index, scopetables)
  of scopeStorage:
    let index = c.getValue(node.bracketIndex, scopetables)
    notnil index:
      result = c.walkAccessorStorage(node.bracketLHS, index, scopetables)

proc writeDotExpr(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable]) =
  # Handle dot expressions
  let someValue: Node = c.dotEvaluator(node, scopetables)
  if likely(someValue != nil):
    add c.output, someValue.toString()
    c.stickytail = true

proc evalCmd(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable],
    parentNodeType: NodeType = ntUnknown): Node =
  # Evaluate a command
  case node.cmdType
  of cmdBreak:
    return node
  else:
    if parentNodeType == ntFunction:
      return node.cmdValue
    else:
      var val = c.getValue(node.cmdValue, scopetables)
      notnil val:
        case node.cmdType
        of cmdEcho:
          val.meta = node.cmdValue.meta
          case node.cmdValue.nt
          of ntIdent:
            print(val, node.cmdValue.identSafe)
          else:
            print(val)
        of cmdReturn:
          return val
        else: discard

proc infixEvaluator(c: var HtmlCompiler, lhs, rhs: Node,
    infixOp: InfixOp, scopetables: var seq[ScopeTable]): bool =
  # Evaluates comparison expressions
  if unlikely(lhs == nil or rhs == nil): return
  let lhs = c.getValue(lhs, scopetables)
  let rhs = c.getValue(rhs, scopetables)
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
      result = c.infixEvaluator(lhs.infixLeft,
          lhs.infixRight, lhs.infixOp, scopetables)
      if result:
        case rhs.nt
        of ntInfixExpr:
          return c.infixEvaluator(rhs.infixLeft,
              rhs.infixRight, rhs.infixOp, scopetables)
        else:
          result = rhs.bVal == true
    else:
      result = lhs.bVal == true and rhs.bVal == true
  of OR:
    case lhs.nt
    of ntInfixExpr:
      result = c.infixEvaluator(lhs.infixLeft,
          lhs.infixRight, lhs.infixOp, scopetables)
      if not result:
        case rhs.nt
        of ntInfixExpr:
          return c.infixEvaluator(rhs.infixLeft,
              rhs.infixRight, rhs.infixOp, scopetables)
        else:
          result = rhs.bVal == true
    else: 
      result = lhs.bVal == true or rhs.bVal == true
  else: discard # todo

proc getValues(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): seq[Node] =
  add result, c.getValue(node.infixLeft, scopetables)
  add result, c.getValue(node.infixRight, scopetables)

proc getValue(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node =
  if unlikely(node == nil): return
  case node.nt
  of ntIdent:
    # evaluates an identifier
    let some = c.getScope(node.identName, scopetables)
    if likely(some.scopeTable != nil):
      case some.scopeTable[node.identName].nt
      of ntFunction:
        return c.unsafeCall(node, some.scopeTable[node.identName], scopetables)
      of ntVariableDef:
        return c.getValue(some.scopeTable[node.identName].varValue, scopetables)
      else: return
    if node.identName == "this":
      return c.data["local"].toTimNode
    if node.identName == "app":
      return c.data["global"].toTimNode
    if node.identArgs.len > 0:
      compileErrorWithArgs(fnUndeclared, [node.identName])
    compileErrorWithArgs(undeclaredVariable, [node.identName])
  of ntEscape:
    result = c.getValue(node.escapeIdent, scopetables)
    notnil result:
      result.sVal = result.sVal.escapeValue
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
        notnil vNode:
          add result.sVal, c.toString(vNode, scopetables)
        do: break
    else:
      result = ast.newNode(ntLitBool)
      result.bVal = c.infixEvaluator(node.infixLeft, node.infixRight, node.infixOp, scopetables)
      result.meta = node.meta
  of ntDotExpr:
    # evaluate dot expressions
    # result = c.dotEvaluator(node, scopetables)
    result = c.walkAccessorStorage(node.lhs, node.rhs, scopetables)
  of ntBracketExpr:
    result = c.bracketEvaluator(node, scopetables)
    if likely(result != nil):
      case result.nt
      of ntInfixExpr, ntDotExpr:
        return c.getValue(result, scopetables)
      else: discard
  of ntMathInfixExpr:
    # evaluate a math expression and returns its value
    result = c.mathInfixEvaluator(node.infixMathLeft,
        node.infixMathRight, node.infixMathOp, scopetables)
  else: discard

template calcInfixEval() {.dirty.} =
  let lhs = c.mathInfixEvaluator(lhs.infixMathLeft,
      lhs.infixMathRight, lhs.infixMathOp, scopetables)
  if likely(lhs != nil):
    return c.mathInfixEvaluator(lhs, rhs, op, scopetables)

template calcInfixNest() {.dirty.} =
  let rhs = c.mathInfixEvaluator(rhs.infixMathLeft,
    rhs.infixMathRight, rhs.infixMathOp, scopetables)
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

proc evalCondition(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable], xel: string): Node {.discardable.} =
  # Evaluates condition branches
  evalBranch node.condIfBranch.expr:
    result = c.walkNodes(node.condIfBranch.body, scopetables, xel = xel)
  if node.condElifBranch.len > 0:
    # handle `elif` branches
    for elifbranch in node.condElifBranch:
      evalBranch elifBranch.expr:
        result = c.walkNodes(elifbranch.body, scopetables, xel = xel)
  if node.condElseBranch.len > 0:
    # handle `else` branch
    result = c.walkNodes(node.condElseBranch, scopetables, xel = xel)

proc evalConcat(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  var x, y: Node
  x = c.getValue(node.infixLeft, scopetables)
  y = c.getValue(node.infixRight, scopetables)
  if likely(x != nil and y != nil):
    write x, true, false
    write y, true, false

template handleBreakCommand(x: Node) {.dirty.} =
  if x != nil:
    case x.nt
    of ntCommandStmt:
      if x.cmdType == cmdBreak:
        break
    else: discard

template loopEvaluator(kv, items: Node, xel: string) =
  case items.nt:
  of ntLitString:
    case kv.nt
    of ntVariableDef:
      for x in items.sVal:
        newScope(scopetables)
        node.loopItem.varValue =
          ast.Node(nt: ntLitString, sVal: $(x)) # todo implement `ntLitChar`
        c.varExpr(node.loopItem, scopetables)
        let x = c.walkNodes(node.loopBody, scopetables, xel = xel)
        clearScope(scopetables)
        node.loopItem.varValue = nil
        handleBreakCommand(x)
    else: discard # todo error
  of ntLitArray:
    case kv.nt
    of ntVariableDef:
      for x in items.arrayItems:
        newScope(scopetables)
        node.loopItem.varValue = x
        c.varExpr(node.loopItem, scopetables)
        let x = c.walkNodes(node.loopBody, scopetables, xel = xel)
        clearScope(scopetables)
        node.loopItem.varValue = nil
        handleBreakCommand(x)
    else: discard # todo error
  of ntLitObject:
    case kv.nt
    of ntVariableDef:
      for k, y in items.objectItems:
        newScope(scopetables)
        node.loopItem.varValue = y
        c.varExpr(node.loopItem, scopetables)
        let x = c.walkNodes(node.loopBody, scopetables, xel = xel)
        clearScope(scopetables)
        node.loopItem.varValue = nil
        handleBreakCommand(x)
    of ntIdentPair:
      for x, y in items.objectItems:
        newScope(scopetables)
        let kvar = ast.newNode(ntLitString)
        kvar.sVal = x
        node.loopItem.identPairs[0].varValue = kvar
        node.loopItem.identPairs[1].varValue = y
        c.varExpr(node.loopItem.identPairs[0], scopetables)
        c.varExpr(node.loopItem.identPairs[1], scopetables)
        let x = c.walkNodes(node.loopBody, scopetables, xel = xel)
        clearScope(scopetables)
        node.loopItem.identPairs[0].varValue = nil
        node.loopItem.identPairs[1].varValue = nil
        handleBreakCommand(x)
    else: discard
  of ntIndexRange:
    for i in items.rangeNodes[0].iVal .. items.rangeNodes[1].iVal:
      newScope(scopetables)
      node.loopItem.varValue = ast.newInteger(i)
      c.varExpr(node.loopItem, scopetables)
      let x = c.walkNodes(node.loopBody, scopetables, xel = xel)
      clearScope(scopetables)
      node.loopItem.varValue = nil
      handleBreakCommand(x)
  else:
    let x = @[ntLitString, ntLitArray, ntLitObject]
    compileErrorWithArgs(typeMismatch, [$(items.nt), x.join(" ")])

proc evalLoop(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable], xel: string) =
  # Evaluates a `for` loop
  case node.loopItems.nt
  of ntIdent:
    let some = c.getScope(node.loopItems.identName, scopetables)
    if likely(some.scopeTable != nil):
      var items: Node
      case some.scopeTable[node.loopItems.identName].nt
      of ntFunction:
        items = c.unsafeCall(node.loopItems,
          some.scopeTable[node.loopItems.identName], scopetables)
      of ntVariableDef:
        items = some.scopeTable[node.loopItems.identName].varValue
      else: discard # error ?
      loopEvaluator(node.loopItem, items, xel)
    else: compileErrorWithArgs(undeclaredVariable, [node.loopItems.identName])
  of ntDotExpr:
    let items = c.dotEvaluator(node.loopItems, scopetables)
    if likely(items != nil):
      loopEvaluator(node.loopItem, items, xel)
    else:
      compileErrorWithArgs(undeclaredVariable, [node.loopItems.lhs.identName])
  of ntLitArray:
    loopEvaluator(node.loopItem, node.loopItems, xel)
  of ntBracketExpr:
    let items = c.bracketEvaluator(node.loopItems, scopetables)
    loopEvaluator(node.loopItem, items, xel)
  of ntLitString, ntIndexRange:
    loopEvaluator(node.loopItem, node.loopItems, xel)
  else:
    compileErrorWithArgs(invalidIterator)

proc typeCheck(c: var HtmlCompiler,
    x, node: Node, parent: Node = nil): bool =
  if unlikely(x == nil):
    compileErrorWithArgs(typeMismatch, ["none", $(node.nt)])
  if unlikely(x.nt != node.nt):
    case x.nt
    of ntMathInfixExpr, ntLitInt, ntLitFloat:
      return node.nt in {ntLitInt, ntLitFloat, ntMathInfixExpr} 
    else: discard
    compileErrorWithArgs(typeMismatch, [$(node.nt), $(x.nt)])
  result = true

proc typeCheck(c: var HtmlCompiler, node: Node,
    expect: NodeType, parent: Node = nil): bool =
  if unlikely(node == nil):
    let node = parent
    compileErrorWithArgs(typeMismatch, ["none", $(expect)])
  if unlikely(node.nt != expect):
    compileErrorWithArgs(typeMismatch, [$(node.nt), $(expect)])
  result = true

proc typeCheck(c: var HtmlCompiler, node: Node, expect: HtmlTag): bool =
  if unlikely(node.tag != expect):
    let x = $(expect)
    compileErrorWithArgs(typeMismatch, [node.getTag, toLowerAscii(x[3..^1])])
  result = true

#
# Compile Handlers
#
proc checkArrayStorage(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable]): bool

proc checkObjectStorage(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable]): bool

proc checkObjectStorage(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable]): bool =
  # a simple checker and ast modified for object storages
  for k, v in node.objectItems.mpairs:
    case v.nt
    of ntLitArray:
      if unlikely(not c.checkArrayStorage(v, scopetables)):
        return false
    else:
      var valNode = c.getValue(v, scopetables)
      if likely(valNode != nil):
        v = valNode
      else: discard # todo error
  result = true

proc checkArrayStorage(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable]): bool =
  # a simple checker and ast modified for array storages
  for v in node.arrayItems.mitems:
    var valNode = c.getValue(v, scopetables)
    if likely(valNode != nil):
      v = valNode
    else: discard # todo error
  result = true

proc varExpr(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]) =
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
        compileErrorWithArgs(undeclaredVariable,
          [node.varValue.identName])
    else: discard
    c.stack(node.varName, node, scopetables)
  else: compileErrorWithArgs(varRedefine, [node.varName])

proc assignExpr(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable]) =
  # Handle assignment expressions
  let some = c.getScope(node.asgnIdent, scopetables)
  if likely(some.scopeTable != nil):
    let varNode = some.scopeTable[node.asgnIdent]
    if likely(c.typeCheck(varNode.varValue, node.asgnVal)):
      if likely(not varNode.varImmutable):
        varNode.varValue = c.getValue(node.asgnVal, scopetables)
      else:
        compileErrorWithArgs(varImmutable, [varNode.varName])

proc fnDef(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]) =
  # Handle function definitions
  if likely(not c.inScope(node.fnIdent, scopetables)):
    if node.fnParams.len > 0:
      for k, p in node.fnParams:
        if p.pImplVal != nil:
          if p.pImplVal.nt != p.pType:
            compileErrorWithArgs(typeMismatch,
              [$(p.pImplVal.nt), $p.pType], p.meta)
    c.stack(node.fnIdent, node, scopetables)
  else:
    compileErrorWithArgs(fnRedefine, [node.fnIdent])

proc unsafeCall(c: var HtmlCompiler, node, fnNode: Node,
    scopetables: var seq[ScopeTable]): Node =
  let params = fnNode.fnParams.keys.toSeq()
  var asgnValArgs: seq[Node]
  if node.identArgs.len == fnNode.fnParams.len:
    # checking if the number of given args
    # is matching the total number of parameters
    if node.identArgs.len > 0:
      var i = 0
      if fnNode.fnType in {fnImportSystem, fnImportModule}:
        var args: seq[std.Arg]
        for i in 0..node.identArgs.high:
          try:
            let param = fnNode.fnParams[params[i]]
            let argValue = c.getValue(node.identArgs[i], scopetables)
            notnil argValue:
              if c.typeCheck(argValue, param[1]):
                add args, (param[0][1..^1], argValue)
              else: return # typeCheck returns `typeMismatch`
            do:
              compileErrorWithArgs(fnReturnVoid, [node.identArgs[i].identName])
          except Defect:
            compileErrorWithArgs(fnExtraArg,
              [node.identName, $(params.len), $(node.identArgs.len)])
        try:
          result = std.call(fnNode.fnSource, node.identName, args)
          assert result != nil
          if result != nil:
            case result.nt
            of ntRuntimeCode:
              {.gcsafe.}:
                var p: Parser = parser.parseSnippet("", result.runtimeCode)
                let phc = newCompiler(p.getAst)
                if not phc.hasErrors:
                  add c.output, phc.getHtml()
                return nil
            else: discard
            return # result
        except SystemModule as e:
          compileErrorWithArgs(internalError,
            [e.msg, fnNode.fnSource, fnNode.fnIdent], node.meta)
      else:
        for k, p in fnNode.fnParams:
          var argValue = c.getValue(node.identArgs[i], scopetables)
          notnil argValue:
            if not c.typeCheck(argValue, p.pType):
              return  # typeCheck returns `typeMismatch`
            add asgnValArgs, argValue
          do:
            return # undeclaredIdentifier
          inc i
  elif node.identArgs.len > fnNode.fnParams.len:
    compileErrorWithArgs(fnExtraArg,
      [$(node.identArgs.len), $(fnNode.fnParams.len)])
  elif node.identArgs.len < fnNode.fnParams.len:
    # check if function parameters has any implicit values
    var i = 0
    for k, p in fnNode.fnParams:
      if p.pImplVal != nil:
        let someParam = c.getScope(k, scopetables)
        someParam.scopeTable[k].varValue = p.pImplVal
      else:
        compileErrorWithArgs(typeMismatch,
          ["none", $p.pType], p.meta)
      inc i

  if fnNode.fnParams.len > 0:
    # stack provided argument values
    newScope(scopetables)
    var i = 0
    for k, p in fnNode.fnParams:
      var x = ast.newVariable(k, p.pImplVal, p.meta)
      x.varValue = asgnValArgs[i]
      c.stack(k, x, scopetables)
      inc i
  result = c.walkNodes(fnNode.fnBody, scopetables, ntFunction)
  if result != nil:
    case result.nt
    of ntHtmlElement:
      if c.typeCheck(result, fnNode.fnReturnHtmlElement):
        result = c.walkNodes(@[result], scopetables)
      else:
        result = nil
    else:
      let x = c.getValue(result, scopetables)
      if likely(x != nil):
        if unlikely(c.typeCheck(x, fnNode.fnReturnType, x)):
          result = x
        else:
          result = nil
  else: discard # ?
    # if unlikely(not c.typeCheck(result, fnNode.fnReturnType, fnNode)):
      # clearScope(scopetables)
      # return nil
  clearScope(scopetables)

proc fnCall(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node =
  # Handle function calls
  let some = c.getScope(node.identName, scopetables)
  if likely(some.scopeTable != nil):
    return c.unsafeCall(node, some.scopeTable[node.identName], scopetables)
  else: compileErrorWithArgs(fnUndeclared, [node.identName])

#
# Html Handler
#
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
      of ntLitString, ntLitInt, ntLitFloat, ntLitBool:
        add attrStr, c.toString(attrNode, scopetables)
      of ntLitObject, ntLitArray:
        add attrStr, c.toString(attrNode, scopetables, escape = true)
      of ntEscape:
        let xVal = c.getValue(attrNode, scopetables)
        notnil xVal:
          add attrStr, xVal.toString.escapeValue
      of ntIdent:
        let xVal = c.getValue(attrNode, scopetables)
        notnil xVal:
          add attrStr, xVal.toString(xVal.nt in [ntLitObject, ntLitArray])
      of ntDotExpr:
        let xVal = c.dotEvaluator(attrNode, scopetables)
        notnil xVal:
          add attrStr, xVal.toString()
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

proc htmlElement(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]) =
  # Handle HTML element
  htmlblock node:
    c.walkNodes(node.nodes, scopetables, ntHtmlElement)

proc evaluatePartials(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable]) =
  # Evaluate included partials
  c.partialIndent = node.meta[1]
  for x in node.includes:
    if likely(c.ast.partials.hasKey(x)):
      c.walkNodes(c.ast.partials[x][0].nodes, scopetables)
  c.partialIndent = 0

proc evaluatePlaceholder(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]) =
  ## Evaluate a placehodler
  if c.engine.hasPlaceholder(node.placeholderName):
    var i = 0
    for tree in c.engine.snippets(node.placeholderName):
      let phc = newCompiler(tree)
      if not phc.hasErrors:
        add c.output, phc.getHtml()
      else:
        echo "ignore snippet"
        c.engine.deleteSnippet(node.placeholderName, i)
      inc i
#
# JS API
#
proc createHtmlElement(c: var HtmlCompiler, x: Node,
    scopetables: var seq[ScopeTable], pEl: string) =
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
      domInsertAdjacentElement %
        ["document.querySelector('" & c.jsTargetElement & "')", xel]

#
# Main nodes walker
#
proc walkNodes(c: var HtmlCompiler, nodes: seq[Node],
    scopetables: var seq[ScopeTable], parentNodeType: NodeType = ntUnknown,
    xel = newStringOfCap(0)): Node {.discardable.} =
  # Evaluate a seq[Node] nodes
  for i in 0..nodes.high:
    let node = nodes[i]
    case node.nt
    of ntHtmlElement:
      if parentNodeType == ntFunction:
        return node
      if not c.isClientSide:
        c.htmlElement(node, scopetables)
      else:
        c.createHtmlElement(node, scopetables, xel)
    of ntIdent:
      # case parentNodeType
      # of ntHtmlElement:
      #   echo node
        # let returnNode = c.fnCall(node, scopetables)
        # if likely(returnNode != nil):
          # write returnNode, true, false
      # else:
      #   discard
      #   let x = c.fnCall(node, scopetables)
      #   if unlikely x != nil:
      #     if parentNodeType != ntFunction and x.nt != ntHtmlElement:
      #       compileErrorWithArgs(fnReturnMissingCommand, [node.identName, $(x.nt)])
      let x: Node = c.getValue(node, scopetables)
      notnil x:
        if not c.isClientSide:
          write x, true, node.identSafe
        else:
          add c.jsOutputCode, domInnerText % [xel, c.toString(x, scopetables)]
    of ntDotExpr:
      let x: Node = c.dotEvaluator(node, scopetables)
      notnil x:
        if not c.isClientSide:
          write x, true, false
        else:
          add c.jsOutputCode, domInnerText % [xel, c.toString(x, scopetables)]
    of ntVariableDef:
      c.varExpr(node, scopetables)
    of ntCommandStmt:
      case node.cmdType
      of cmdReturn:
        return c.evalCmd(node, scopetables, parentNodeType)
      of cmdBreak:
        return c.evalCmd(node, scopetables)
      else:
        discard c.evalCmd(node, scopetables)
    of ntAssignExpr:
      c.assignExpr(node, scopetables)
    of ntConditionStmt:
      result = c.evalCondition(node, scopetables, xel)
      if result != nil:
        return # a resulted ntCommandStmt Node of type cmdReturn
    of ntLoopStmt:
      c.evalLoop(node, scopetables, xel)
    of ntLitString, ntLitInt, ntLitFloat, ntLitBool:
      if unlikely(c.isClientSide):
        add c.jsOutputCode, domInnerText % [xel, c.toString(node, scopetables)]
      else:
        write node, true, false
    of ntMathInfixExpr:
      let x: Node = c.mathInfixEvaluator(node.infixMathLeft,
                      node.infixMathRight, node.infixMathOp, scopetables)
      write x, true, false
    of ntFunction:
      # Handle function calls
      c.fnDef(node, scopetables)
    of ntInfixExpr:
      # Handle infix expressions
      let x = c.getValue(node, scopetables)
      notnil x:
        if unlikely(c.isClientSide):
          add c.jsOutputCode, domInnerText % [xel, x.toString()]
        else:
          write x, true, false
    of ntViewLoader:
      # Handle `@view` placeholder
      c.head = c.output
      reset(c.output)
    of ntInclude:
      # Handle `@include` statements
      c.evaluatePartials(node, scopetables)
    of ntJavaScriptSnippet:
      # Handle `@js` blocks
      add c.jsOutput, node.snippetCode
    of ntJsonSnippet:
      # Handle `@json` blocks
      try:
        add c.jsonOutput,
          jsony.toJson(jsony.fromJson(node.snippetCode))
      except jsony.JsonError as e:
        compileErrorWithArgs(internalError, node.meta, [e.msg])
    of ntClientBlock:
      # Handle `@client` blocks
      c.jsTargetElement = node.clientTargetElement
      c.isClientSide = true
      c.walkNodes(node.clientStmt, scopetables)
      add c.jsOutputCode, "}"
      add c.jsOutput,
        "document.addEventListener('DOMContentLoaded', function(){"
      add c.jsOutput, c.jsOutputCode
      add c.jsOutput, "});"
      c.jsOutputCode = "{"
      setLen(c.jsTargetElement, 0)
      reset(c.jsCountEl)
      c.isClientSide = false
    of ntPlaceholder:
      # Handle placeholders
      c.evaluatePlaceholder(node, scopetables)
    else: discard


#
# Public API
#
when not defined timStandalone:
  proc newCompiler*(engine: TimEngine, ast: Ast,
      tpl: TimTemplate, minify = true, indent = 2,
      data: JsonNode = newJObject()): HtmlCompiler =
    ## Create a new instance of `HtmlCompiler`
    assert indent in [2, 4]
    assert ast != nil
    data["global"] = engine.getGlobalData()
    result =
      HtmlCompiler(
        engine: engine,
        tpl: tpl,
        start: true,
        tplType: tpl.getType,
        logger: Logger(filePath: tpl.getSourcePath()),
        data: data,
        minify: minify,
        ast: ast,
      )
    if minify: setLen(result.nl, 0)
    var scopetables = newSeq[ScopeTable]()
    for moduleName, moduleAst in result.ast.modules:
      result.walkNodes(moduleAst.nodes, scopetables)
    result.walkNodes(result.ast.nodes, scopetables)
else:
  proc newCompiler*(ast: Ast, tpl: TimTemplate,
      minify = true, indent = 2): HtmlCompiler =
    ## Create a new instance of `HtmlCompiler`
    assert indent in [2, 4]
    assert ast != nil
    result =
      HtmlCompiler(
        engine: engine,
        tpl: tpl,
        start: true,
        tplType: tpl.getType,
        logger: Logger(filePath: tpl.getSourcePath()),
        minify: minify,
        ast: ast,
      )
    if minify: setLen(result.nl, 0)
    var scopetables = newSeq[ScopeTable]()
    result.walkNodes(result.ast.nodes, scopetables)

proc newCompiler*(ast: Ast, minify = true, indent = 2, data = newJObject()): HtmlCompiler =
  ## Create a new instance of `HtmlCompiler
  assert indent in [2, 4]
  assert ast != nil
  var c = HtmlCompiler(
    ast: ast,
    start: true,
    tplType: ttView,
    logger: Logger(filePath: ast.src),
    minify: minify,
    data: data
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
    var indentSize: int
    if not c.minify:
      indentSize = c.indent * 2
    result = "\n" & indent("<script type=\"text/javascript\">", indentSize)
    add result, indent(c.jsOutput, indentSize + 2)
    add result, "\n" & indent("</script>", indentSize)
    add result, c.getHtml
  else:
    result = c.getHtml