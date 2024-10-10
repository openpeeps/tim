# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, critbits, strutils, json, options,
    terminal, sequtils, hashes, macros,  enumutils]

import pkg/jsony
import ./tim, ../std, ../parser, ../ast

from ../meta import TimEngine, TimTemplate, TimTemplateType,
  TimEngineSnippets, getType, getSourcePath,
  getGlobalData, placeholderLocker

type
  HtmlCompiler* = object of TimCompiler
    ## Object of a TimCompiler to output `HTML`
    globalScope: ScopeTable = ScopeTable()
    data: JsonNode
    jsOutputCode: string = "{"
    jsOutputComponents: OrderedTable[string, string]
    jsCountEl: uint
    jsTargetElement: string
    placeholders: TimEngineSnippets

# Forward Declaration
proc newCompiler*(ast: Ast, minify = true,
    indent = 2, data: JsonNode = nil,
    placeholders: TimEngineSnippets = nil
): HtmlCompiler

proc walkNodes(c: var HtmlCompiler, nodes: seq[Node],
    scopetables: var seq[ScopeTable],
    parentNodeType: NodeType = ntUnknown, xel = newStringOfCap(0),
    includes, excludes: set[NodeType] = {}
): Node {.discardable.}

proc walkStreamStorage(c: var HtmlCompiler, streamNode: Node, rhs: Node): JsonNode

proc walkFunctionBody(c: var HtmlCompiler, fnNode, fnBody: Node,
    scopetables: var seq[ScopeTable], xel = newStringOfCap(0),
    includes, excludes: set[NodeType] = {}
): Node {.discardable.}

proc getDataType(node: Node): DataType

proc unwrapArgs(c: var HtmlCompiler, args: seq[Node],
    scopetables: var seq[ScopeTable]): tuple[resolvedArgs, htmlAttributes: seq[Node]]

proc unwrap(identName: string, args: seq[Node]): string

proc getHtml*(c: HtmlCompiler): string

proc typeCheck(c: var HtmlCompiler, aNode, bNode: Node,
    scopetables: var seq[ScopeTable]): bool

proc typeCheck(c: var HtmlCompiler, node: Node,
  expect: NodeType, parent: Node = nil): bool

proc mathInfixEvaluator(c: var HtmlCompiler, lhs,
    rhs: Node, op: MathOp, scopetables: var seq[ScopeTable]): Node

proc dotEvaluator(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable]): Node

proc infixEvaluator(c: var HtmlCompiler, lhs, rhs: Node,
    infixOp: InfixOp, scopetables: var seq[ScopeTable]): bool

proc getValue(c: var HtmlCompiler, node: Node,
  scopetables: var seq[ScopeTable],
  xel = newStringOfCap(0),
  parentNodeType: NodeType = ntUnknown): Node

proc functionCall(c: var HtmlCompiler, node, fnNode: Node,
    args: seq[Node], scopetables: var seq[ScopeTable],
    htmlAttrs: seq[Node] = @[], xel = newStringOfCap(0),
    parentNodeType: NodeType = ntUnknown): Node

proc componentCall(c: var HtmlCompiler, componentNode: Node,
    scopetables: var seq[ScopeTable]): Node

proc unwrapBlock(c: var HtmlCompiler, node, blockNode: Node,
  scopetables: var seq[ScopeTable]): Node

# proc fnCall(c: var HtmlCompiler, node: Node,
#     scopetables: var seq[ScopeTable]): Node

proc evalCondition(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable], xel: string,
    parentNodeType: NodeType = ntUnknown): Node {.discardable.}

proc hasError*(c: HtmlCompiler): bool = c.hasErrors # or c.logger.errorLogs.len > 0

proc bracketEvaluator(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node

proc checkArrayStorage(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable], needsCopy = false): (bool, Node)

proc checkObjectStorage(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable], needsCopy = false): (bool, Node)

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
  domInsertAdjacentElement = "$1.insertAdjacentElement('beforeend', $2);"
  domInnerText = "$1.innerText=\"$2\";"
  domInnerHtml = "$1.innerHTML=`$2`;"
  stdlibPaths = ["std/system", "std/strings", "std/arrays", "std/os", "*"]

proc getHashedIdent(key: string): Hash =
  if key.len > 1:
    hash(key[0] & key[1..^1].toLowerAscii)
  else:
    hash(key)

# Scope API, available for library version of TimEngine 
proc globalScope(c: var HtmlCompiler, key: string, node: Node) =
  # Add `node` to global scope
  let key = key.getHashedIdent()
  add c.globalScope.data[key], node

proc newStackSeq(c: var HtmlCompiler, key: string, scopetables: var seq[ScopeTable], toGlobalStack = false) =
  let key = key.getHashedIdent()
  if scopetables.len > 0 and toGlobalStack == false:
    scopetables[^1].data[key] = newSeq[Node]()
  else:
    c.globalScope.data[key] = newSeq[Node]()

proc stack(c: var HtmlCompiler, key: string, node: Node,
    scopetables: var seq[ScopeTable]) =
  # Add `node` to either local or global scope
  let key = key.getHashedIdent()
  case node.nt
  of ntAssignables + {ntVariableDef, ntReference}:
    if scopetables.len > 0:
      scopetables[^1].data[key] = @[node]
    else:
      c.globalScope.data[key] = @[node]
  of ntFunction, ntBlock:
    if node.fnSource notin stdlibPaths:
      if scopetables.len > 0:
        add scopetables[^1].data[key], node
      else:
        add c.globalScope.data[key], node
    else:
      add c.globalScope.data[key], node
  of ntComponent, ntTypeDef:
    if scopetables.len > 0:
      scopetables[^1].data[key] = @[node]
    else:
      c.globalScope.data[key] = @[node]
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
  # If found returns the ScopeTable and its position in the sequence.
  let key = key.getHashedIdent()
  if scopetables.len > 0:
    for i in countdown(scopetables.high, scopetables.low):
      if scopetables[i].data.hasKey(key):
        return (scopetables[i], i)
  if likely(c.globalScope.data.hasKey(key)):
    return (c.globalScope, 0)

proc getScope(c: var HtmlCompiler, node: Node,
    key: string, args: seq[Node],
    scopetables: var seq[ScopeTable]
  ): tuple[scopeTable: ScopeTable, index: int] =
#   # Walks (bottom-top) through available `scopetables` and finds
#   # the closest `ScopeTable` that contains a node for given ident `Node`.
  let key = key.getHashedIdent()
  if scopetables.len > 0:
    for i in countdown(scopetables.high, scopetables.low):
      if scopetables[i].data.hasKey(key):
        return (scopetables[i], i)
  if likely(c.globalScope.data.hasKey(key)):
    return (c.globalScope, 0)

proc inScope(c: HtmlCompiler, key: string,
    scopetables: var seq[ScopeTable]): bool =
  # Performs a quick search in the current `ScopeTable`
  let key = key.getHashedIdent()
  if scopetables.len > 0:
    result = scopetables[^1].data.hasKey(key)
  if not result:
    return c.globalScope.data.hasKey(key)

proc inGlobalScope(c: HtmlCompiler, key: string): bool =
  let key = key.getHashedIdent()
  result = c.globalScope.data.hasKey(key)

proc get(scopetable: ScopeTable, key: string): Node =
  ## Unsafe way to get a node by `key` from a specific `scopetable`
  let key = key.getHashedIdent()
  result = scopetable.data[key][0]

proc fromScope(c: var HtmlCompiler, key: string,
    scopetables: var seq[ScopeTable]): Node =
  # Retrieves a node by `key` from `scopetables`
  let some = c.getScope(key, scopetables)
  if some.scopeTable != nil:
    return some.scopeTable.get(key)

proc newScope(scopetables: var seq[ScopeTable]) =
  ## Create a new Scope
  add scopetables, ScopeTable()

proc clearScope(scopetables: var seq[ScopeTable]) =
  ## Clears the current (latest) ScopeTable
  try:
    # clear(scopetables[scopetables.high].data)
    scopetables.delete(scopetables.high)
  except RangeDefect: discard

proc mergeScope(c: var HtmlCompiler,
  scopetables: var seq[ScopeTable], scope: ScopeTable
) =
  ## Merge `scope` in current scope table
  if scopetables.len > 0:
    for x, n in scope.data:
      scopetables[^1].data[x] = n
  else:
    for x, n in scope.data:
      c.globalScope.data[x] = n

template notnil(x, body) =
  if likely(x != nil):
    body

template notnil(x, body, elseBody) =
  if likely(x != nil):
    body
  else:
    elseBody

let
  intDefault = ast.newNode(ntLitInt)
  strDefault = ast.newNode(ntLitString)
  boolDefault = ast.newNode(ntLitBool)
  boolDefaultCond = ast.newNode(ntLitBool)
boolDefaultCond.bVal = true

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


proc escapeValue*(x: string, escapeNewLines, escapeWhitespace = false): string =
  for c in x:
    case c
    of '<': add result, "&lt;"
    of '>': add result, "&gt;"
    of '&': add result, "&amp;"
    of '"': add result, "&quot;"
    of NewLines:
      if escapeNewLines: add result, "\\n"
      else: add result, c
    of ' ':
      if escapeWhitespace:
        add result, "&nbsp;"
      else: add result, c
    of '\'': add result, "&apos;"
    else: add result, c

proc unescapeValue*(x: string): string =
  var i = 0
  while i < x.len:
    case x[i]
    of '&':
      try:
        if x[i..(i + 3)] == "&lt;":
          add result, '<'
          inc i, 3
        elif x[i..(i + 3)] == "&gt;":
          add result, '>'
          inc i, 3
        elif x[i..(i + 4)] == "&amp;":
          add result, '&'
          inc i, 4
        elif x[i..(i + 5)] == "&quot;":
          add result, '"'
          inc i, 5
        elif x[i..(i + 5)] == "&nbsp;":
          add result, ' '
          inc i, 5
        elif x[i..(i + 5)] == "&apos;":
          add result, '\''
          inc i, 5
        else:
          add result, x[i]
      except IndexDefect:
        add result, x[i]
    else:
      add result, x[i]
    inc i

proc dumpHook*(s: var string, v: Node) =
  ## Dumps `v` node to stringified JSON using `pkg/jsony`
  case v.nt
  of ntLitString: s.add("\"" & $v.sVal & "\"")
  of ntLitFloat:  s.add($v.fVal)
  of ntLitInt:    s.add($v.iVal)
  of ntLitBool:   s.add($v.bVal)
  of ntLitObject: s.dumpHook(v.objectItems)
  of ntLitArray:  s.dumpHook(v.arrayItems)
  # of ntHtmlAttribute: s.dumpHook(v.attrValue) # todo find a way to output attributes
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
      of ntStream:    ast.toString(node.streamContent)
      of ntLitObject:
        if not escape:
          # fromJson(jsony.toJson(node.objectItems)).pretty
          jsony.toJson(node.objectItems)
        else:
          jsony.toJson(node.objectItems)
      of ntLitArray:
        if not escape:
          # fromJson(jsony.toJson(node.arrayItems)).pretty
          jsony.toJson(node.arrayItems)
        else:
          jsony.toJson(node.arrayItems)
      of ntIdent:
        node.identName
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
          notnil x:
            case x.nt
            of ntLitString:
              add concat, x.sVal
            else:
              add concat, x.toString
          do: break
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
    of ntStream:
      ast.toString(node.streamContent)
    else: ""
  if escape:
    result = escapeValue(result)

# proc toString(value: Value, escape = false): string =
#   result =
#     case value.kind
#     of jsonValue:
#       value.jVal.toString(escape)
#     of nimValue:
#       value.nVal.toString(escape)

proc getDataType(node: Node): DataType =
  # Get `DataType` from `NodeType`
  case node.nt
  of ntLitVoid:   typeVoid
  of ntLitInt:    typeInt
  of ntLitString: typeString
  of ntLitFloat:  typeFloat
  of ntLitBool:   typeBool
  of ntLitArray:  typeArray
  of ntLitObject: typeObject
  of ntFunction:  typeFunction
  of ntStream:    typeStream
  of ntBlock, ntStmtList:
    typeBlock
  of ntHtmlElement: typeHtmlElement
  else: typeNil

template write(x: Node, fixtail, escape: bool, indent = 0) =
  if likely(x != nil):
    add c.output,
      if indent > 0: x.toString(escape)
      else: x.toString(escape)
    c.stickytail = fixtail

proc print(val: Node, identSafe = false) =
  let meta = " ($1:$2) " % [$val.meta[0], $val.meta[2]]
  let v = toString(val, identSafe)
  let t = 
    case val.nt
    of ntLitString:
      $(val.nt) & "(" & $(v.len) & ")"
    else:
      $(val.nt)
  stdout.styledWriteLine(
    fgGreen, "Debug",
    fgDefault, meta,
    fgMagenta, t,
    fgDefault, "\n" & v
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

proc walkStorage(c: var HtmlCompiler,
    lhs, rhs: Node,
    scopetables: var seq[ScopeTable],
    asgnValue: Node = nil
): Node =
  case lhs.nt
  of ntLitObject:
    case rhs.nt
    of ntIdent:
      try:
        result = lhs.objectItems[rhs.identName]
        notnil result:
          case result.nt
          of ntFunction:
            let args = c.unwrapArgs(rhs.identArgs, scopetables)
            result = c.functionCall(rhs, result, args[0], scopetables)
          else: discard
      except KeyError:
        rhs.identArgs.insert(lhs, 0)
        result = c.getValue(rhs, scopetables)
        rhs.identArgs.del(0)
    of ntLitString:
      let strKey = c.toString(rhs, scopetables)
      notnil asgnValue:
        try:
          lhs.objectItems[strKey] = asgnValue
        except KeyError:
          compileErrorWithArgs(undeclaredField, rhs.meta, [strKey])
      do:
        try:
          result = lhs.objectItems[strKey]
        except KeyError:
          compileErrorWithArgs(undeclaredField, rhs.meta, [strKey])
    else:
      compileErrorWithArgs(invalidAccessorStorage,
        rhs.meta, [rhs.toString, $lhs.nt])
  of ntDotExpr:
    let lhs = c.walkStorage(lhs.lhs, lhs.rhs, scopetables)
    notnil lhs:
      case lhs.nt
      of ntLitObject, ntLitArray:
        result = c.walkStorage(lhs, rhs, scopetables)
      of ntStream:
        return ast.newStream(c.walkStreamStorage(lhs, rhs))
      else:
        case rhs.nt
        of ntIdent:
          rhs.identArgs.insert(lhs, 0)
          result = c.getValue(rhs, scopetables)
          rhs.identArgs.del(0)
        else:
          result = c.walkStorage(lhs, rhs, scopetables)
  of ntIdent:
    let lhs = c.getValue(lhs, scopetables)
    notnil lhs:
      case lhs.nt
      of ntLitObject, ntLitArray:
        return c.walkStorage(lhs, rhs, scopetables)
      of ntStream:
        return ast.newStream(c.walkStreamStorage(lhs, rhs))
      else:
        case rhs.nt
        of ntIdent:
          rhs.identArgs.insert(lhs, 0)
          result = c.getValue(rhs, scopetables) 
          rhs.identArgs.del(0)
          if unlikely(lhs.nt == ntLitArray):
            compileErrorWithArgs(invalidAccessorStorage,
              rhs.meta, [rhs.toString, $lhs.nt])
          # todo other errors
        else:
          return c.walkStorage(lhs, rhs, scopetables)
  of ntBracketExpr:
    let lhs = c.bracketEvaluator(lhs, scopetables)
    if likely(lhs != nil):
      return c.walkStorage(lhs, rhs, scopetables)
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
    of ntIdent:
      rhs.identArgs.insert(lhs, 0)
      result = c.getValue(rhs, scopetables)
      rhs.identArgs.del(0)
    else:
      compileErrorWithArgs(invalidAccessorStorage,
        rhs.meta, [rhs.toString, $lhs.nt])
  of ntStream:
    case rhs.nt
    of ntIdent:
      if likely(lhs.streamContent.hasKey(rhs.identName)):
        result = ast.newStream(lhs.streamContent[rhs.identName])
      else:
        compileErrorWithArgs(undeclaredField, rhs.meta, [rhs.identName])
    else: discard
  else: discard

proc walkStreamStorage(c: var HtmlCompiler, streamNode: Node, rhs: Node): JsonNode =
  notnil streamNode.streamContent:
    case streamNode.streamContent.kind
    of JObject:
      case rhs.nt
      of ntIdent:
        if likely(streamNode.streamContent.hasKey(rhs.identName)):
          return streamNode.streamContent[rhs.identName]
        result = newJNull()
      of ntDotExpr:
        if likely(streamNode.streamContent.hasKey(rhs.lhs.identName)):
          let nestStream = ast.newStream(streamNode.streamContent[rhs.lhs.identName])
          return c.walkStreamStorage(nestStream, rhs.rhs)
        result = newJNull()
      else: discard
    of JArray:
      case rhs.nt
      of ntLitInt:
        try:
          return streamNode.streamContent[rhs.iVal]
        except IndexDefect:
          compileErrorWithArgs(indexDefect, rhs.meta,
            [$(rhs.iVal), "0.." & $(streamNode.streamContent.len - 1)])
        result = newJNull()
      # of ntDotExpr:
        # debugEcho "????"
      else: discard
    else: discard
  do:
    streamNode.streamContent = newJNull()
    result = streamNode.streamContent

proc dotEvaluator(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node =
  # Evaluate dot expressions
  case node.storageType
  of localStorage, globalStorage:
    # let x = c.evalStorage(node)
    let lhs = c.getValue(node.lhs, scopetables)
    notnil lhs:
      return ast.newStream(c.walkStreamStorage(lhs, node.rhs))
  of scopeStorage:
    let lhs = c.getValue(node.lhs, scopetables)
    notnil lhs:
      case lhs.nt
      of ntStream:
        result = ast.newStream(c.walkStreamStorage(lhs, node.rhs))
      else:
        result = c.walkStorage(lhs, node.rhs, scopetables)

proc bracketEvaluator(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): Node =
  case node.bracketStorageType
  of localStorage, globalStorage:
    let index = c.getValue(node.bracketIndex, scopetables)
    notnil index:
      var x = c.evalStorage(node.bracketLHS)
      notnil x:
        result = x.toTimNode
        return c.walkStorage(result, index, scopetables)
  of scopeStorage:
    let index = c.getValue(node.bracketIndex, scopetables)
    notnil index:
      result = c.walkStorage(node.bracketLHS, index, scopetables)

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
  of cmdBreak, cmdContinue:
    return node
  of cmdAssert:
    let assertResult = c.getValue(node.cmdValue, scopetables)
    notnil assertResult:
      case assertResult.nt
      of ntLitBool:
        if likely(assertResult.bVal == true): 
          discard
        else:
          compileErrorWithArgs(assertionFailed, assertResult.meta, [])
      else: discard # todo error
    do:
      discard # todo error
  else:
    var val: Node
    case node.cmdValue.nt
    of ntStmtList:
      val = c.walkNodes(node.cmdValue.stmtList, scopetables)
    else:
      val = c.getValue(node.cmdValue, scopetables)
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

proc getFieldByNodeType(x: NodeType): Option[NimNode] {.compileTime.} =
  # get field name of a Node by NodeType at compile-time
  case x
  of ntLitString:
    some ident"sVal"
  of ntLitInt:
    some ident"iVal"
  of ntLitFloat:
    some ident"fVal"
  of ntLitBool:
    some ident"bVal"
  of ntLitArray:
    some ident"arrayItems"
  of ntLitObject:
    some ident"objectItems"
  of ntStream:
    some ident"streamContent"
  else: none(NimNode)

macro comp(lhs: untyped, op: static InfixOp,
  rhs: untyped, lhsType: static NodeType, typeBranches: static set[NodeType],
  jsonTypeBranches: static Option[set[JsonNodeKind]] = none(set[JsonNodeKind])
) =
  result = newStmtList()
  var caseStmt = nnkCaseStmt.newTree()
  add caseStmt, newDotExpr(rhs, ident"nt")
  for typeBranch in typeBranches:
    let
      lhsFieldIdent = getFieldByNodeType(lhsType)
      rhsFieldIdent = getFieldByNodeType(typeBranch)
      lhsid = lhsFieldIdent.get()
      rhsid = rhsFieldIdent.get()
    var lhsDotExpr, rhsDotExpr, infixExprNode: NimNode
    if typeBranch != ntStream:
      lhsDotExpr =
        if lhsType == ntLitInt and typeBranch == ntLitFloat:
          newCall(ident"toFloat", newDotExpr(lhs, lhsid))
        else:
          newDotExpr(lhs, lhsid)
      rhsDotExpr =
        if lhsType == ntLitFloat and typeBranch == ntLitInt:
          newCall(ident"toFloat", newDotExpr(rhs, rhsid))
        else:
          newDotExpr(rhs, rhsid)
      infixExprNode =
        nnkReturnStmt.newTree(
          nnkInfix.newTree(
            ident($(op)), lhsDotExpr, rhsDotExpr
          )
        )
    else:
      if jsonTypeBranches.isSome:
        infixExprNode = nnkCaseStmt.newTree()
        add infixExprNode, newDotExpr(newDotExpr(rhs, rhsid), ident"kind")
        for jsonTypeBranch in jsonTypeBranches.get():
          lhsDotExpr =
            if lhsType == ntLitInt and jsonTypeBranch == JFloat:
              newCall(ident"toFloat", newDotExpr(lhs, lhsid))
            else:
              newDotExpr(lhs, lhsid)
          let jsonFieldName = 
            case jsonTypeBranch
            of JInt: ident"num"
            of JFloat: ident"fnum"
            of JString: ident"str"
            of JBool: ident"bval"
            else: newEmptyNode()
          if jsonFieldName.kind != nnkEmpty:
            rhsDotExpr = newDotExpr(newDotExpr(rhs, rhsid), jsonFieldName)
            if lhsType == ntLitFloat and jsonTypeBranch == JInt:
              rhsDotExpr = newCall(ident"toFloat", rhsDotExpr)
          add infixExprNode, nnkOfBranch.newTree(
            ident(symbolName(jsonTypeBranch)),
            nnkStmtList.newTree(
              nnkReturnStmt.newTree(
                nnkInfix.newTree(
                  ident($(op)),
                  lhsDotExpr,
                  rhsDotExpr
                )
              )
            )
          )
        add infixExprNode,
          nnkElse.newTree(
            nnkStmtList.newTree(
              nnkDiscardStmt.newTree(newEmptyNode())
            )
          )
    add caseStmt, nnkOfBranch.newTree(
      ident(symbolName(typeBranch)),
      nnkStmtList.newTree(
        infixExprNode
      )
    )
  add caseStmt,
    nnkElse.newTree(newStmtList().add(
      nnkDiscardStmt.newTree(newEmptyNode()))
    )
  add result, caseStmt
  # echo caseStmt.repr

proc infixEvaluator(c: var HtmlCompiler, lhs, rhs: Node,
    infixOp: InfixOp, scopetables: var seq[ScopeTable]): bool =
  # Evaluates comparison expressions
  if unlikely(lhs == nil or rhs == nil): return
  let
    lhs = c.getValue(lhs, scopetables)
    rhs = c.getValue(rhs, scopetables)
  if unlikely(lhs == nil and rhs == nil): return
  case infixOp:
  of EQ:
    case lhs.nt:
    of ntLitBool:
      comp(lhs, EQ, rhs, ntLitBool,
        typeBranches = {ntLitBool, ntStream},
        jsonTypeBranches = some({JBool}))
    of ntLitString:
      comp(lhs, EQ, rhs, ntLitString,
        typeBranches = {ntLitString, ntStream},
        jsonTypeBranches = some({JString}))
    of ntLitInt:
      comp(lhs, EQ, rhs, ntLitInt,
        typeBranches = {ntLitInt, ntLitFloat, ntStream},
        jsonTypeBranches = some({JInt, JFloat}))
    of ntLitFloat:
      comp(lhs, EQ, rhs, ntLitFloat,
        typeBranches = {ntLitInt, ntLitFloat, ntStream},
        jsonTypeBranches = some({JInt, JFloat}))
    of ntIdent:
      let lhs = c.getValue(lhs, scopetables)
      if likely(lhs != nil):
        return c.infixEvaluator(lhs, rhs, infixOp, scopetables)
    of ntDotExpr:
      let x = c.dotEvaluator(lhs, scopetables)
      notnil x:
        result = c.infixEvaluator(x, rhs, infixOp, scopetables)
    of ntStream:
      case rhs.nt
      of ntLitString:
        case lhs.streamContent.kind
        of JString:
          return lhs.streamContent.str == rhs.sVal
        else: discard
      of ntLitInt:
        case lhs.streamContent.kind
        of JInt:
          return lhs.streamContent.num == rhs.iVal
        of JFloat:
          return lhs.streamContent.fnum == toFloat(rhs.iVal)
        else: discard
      of ntLitBool:
        case lhs.streamContent.kind
        of JBool:
          return lhs.streamContent.bval == rhs.bVal
        else: discard
      else: discard
    else: discard
  of NE:
    case lhs.nt:
    of ntLitBool:
      comp(lhs, NE, rhs, ntLitBool,
        typeBranches = {ntLitBool, ntStream},
        jsonTypeBranches = some({JBool}))
    of ntLitString:
      comp(lhs, NE, rhs, ntLitString,
        typeBranches = {ntLitString, ntStream},
        jsonTypeBranches = some({JString}))
    of ntLitInt:
      comp(lhs, NE, rhs, ntLitInt,
        typeBranches = {ntLitInt, ntLitFloat, ntStream},
        jsonTypeBranches = some({JInt, JFloat}))
    of ntLitFloat:
      comp(lhs, NE, rhs, ntLitFloat,
        typeBranches = {ntLitFloat, ntLitFloat, ntStream},
        jsonTypeBranches = some({JInt, JFloat}))
    of ntIdent:
      let lhs = c.getValue(lhs, scopetables)
      if likely(lhs != nil):
        return c.infixEvaluator(lhs, rhs, infixOp, scopetables)
    of ntDotExpr:
      let x = c.dotEvaluator(lhs, scopetables)
      notnil x:
        result = c.infixEvaluator(x, rhs, infixOp, scopetables)
    of ntStream:
      case rhs.nt
      of ntLitString:
        case lhs.streamContent.kind
        of JString:
          return lhs.streamContent.str != rhs.sVal
        else: discard
      of ntLitInt:
        case lhs.streamContent.kind
        of JInt:
          return lhs.streamContent.num != rhs.iVal
        of JFloat:
          return lhs.streamContent.fnum != toFloat(rhs.iVal)
        else: discard
      else: discard
    else: discard
  of GT:
    case lhs.nt:
    of ntLitInt:
      comp(lhs, GT, rhs, ntLitInt,
        typeBranches = {ntLitInt, ntLitFloat, ntStream},
        jsonTypeBranches = some({JInt, JFloat}))
    of ntLitFloat:
      comp(lhs, GT, rhs, ntLitFloat,
        typeBranches = {ntLitFloat, ntLitInt, ntStream},
        jsonTypeBranches = some({JInt, JFloat}))
    of ntIdent:
      let lhs = c.getValue(lhs, scopetables)
      if likely(lhs != nil):
        return c.infixEvaluator(lhs, rhs, infixOp, scopetables)
    of ntStream:
      case rhs.nt
      of ntLitInt:
        case lhs.streamContent.kind
        of JInt:
          return lhs.streamContent.num > rhs.iVal
        of JFloat:
          return lhs.streamContent.fnum > toFloat(rhs.iVal)
        else: discard
      of ntLitFloat:
        case lhs.streamContent.kind
        of JInt:
          return toFloat(lhs.streamContent.num) > rhs.fVal
        of JFloat:
          return lhs.streamContent.fnum > rhs.fVal
        else: discard
      else: discard
    else: discard
  of GTE:
    case lhs.nt:
    of ntLitInt:
      comp(lhs, GTE, rhs, ntLitInt,
        typeBranches = {ntLitInt, ntLitFloat, ntStream},
        jsonTypeBranches = some({JInt, JFloat}))
    of ntLitFloat:
      comp(lhs, GTE, rhs, ntLitFloat,
        typeBranches = {ntLitFloat, ntLitInt, ntStream},
        jsonTypeBranches = some({JInt, JFloat}))
    of ntIdent:
      let lhs = c.getValue(lhs, scopetables)
      if likely(lhs != nil):
        return c.infixEvaluator(lhs, rhs, infixOp, scopetables)
    else: discard # handle float
  of LT:
    case lhs.nt:
    of ntLitInt:
      comp(lhs, LT, rhs, ntLitInt,
        typeBranches = {ntLitInt, ntLitFloat, ntStream},
        jsonTypeBranches = some({JInt, JFloat}))
    of ntLitFloat:
      comp(lhs, LT, rhs, ntLitFloat,
        typeBranches = {ntLitFloat, ntLitInt, ntStream},
        jsonTypeBranches = some({JInt, JFloat}))
    of ntIdent:
      let lhs = c.getValue(lhs, scopetables)
      if likely(lhs != nil):
        return c.infixEvaluator(lhs, rhs, infixOp, scopetables)
    else: discard
  of LTE:
    case lhs.nt:
    of ntLitInt:
      comp(lhs, LTE, rhs, ntLitInt,
        typeBranches = {ntLitInt, ntLitFloat, ntStream},
        jsonTypeBranches = some({JInt, JFloat}))
    of ntLitFloat:
      comp(lhs, LTE, rhs, ntLitFloat,
        typeBranches = {ntLitFloat, ntLitInt, ntStream},
        jsonTypeBranches = some({JInt, JFloat}))
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
          result = c.infixEvaluator(rhs.infixLeft,
              rhs.infixRight, rhs.infixOp, scopetables)
        else:
          result = rhs.bVal
    else:
      result = lhs.bVal == true or rhs.bVal == true
  else: discard # todo

proc getValues(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]): seq[Node] =
  add result, c.getValue(node.infixLeft, scopetables)
  add result, c.getValue(node.infixRight, scopetables)

proc getValue(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable],
    xel = newStringOfCap(0),
    parentNodeType: NodeType = ntUnknown
): Node =
  if unlikely(node == nil): return
  case node.nt
  of ntIdent, ntBlockIdent:
    # evaluates an identifier
    let args = c.unwrapArgs(node.identArgs, scopetables)
    let id = node.identName.unwrap(args[0])
    let some = c.getScope(node, node.identName, args[0], scopetables)
    if likely(some.scopeTable != nil):
      let scopedNode: Node = some.scopeTable.get(node.identName)
      case scopedNode.nt
      of ntFunction:
        return c.functionCall(node, scopedNode, args[0], scopetables, xel = xel, parentNodeType = parentNodeType)
      of ntBlock:
        return c.functionCall(node, scopedNode, args[0], scopetables, args[1], xel, parentNodeType)
      of ntComponent:
        return c.componentCall(scopedNode, scopetables)
      of ntVariableDef:
        return c.getValue(scopedNode.varValue, scopetables, xel, parentNodeType)
      of ntReference:
        return c.getValue(scopedNode.refValue, scopetables, xel, parentNodeType)
      of ntAssignables:
        return scopedNode
      of ntTypeDef:
        # debugEcho scopedNode
        return args.resolvedArgs[0]
      else: discard
    else: discard
    # if node.identName == "this":
    #   return c.data["local"].toTimNode
    # if node.identName == "app":
    #   return c.data["global"].toTimNode
    # debugEcho node
    compileErrorWithArgs(
      (if node.identArgs.len > 0: fnUndeclared
        else: undeclaredIdentifier), [node.identName])
  of ntEscape:
    var valNode = c.getValue(node.escapeIdent, scopetables)
    notnil valNode:
      return ast.newString(toString(valNode).escapeValue)
  of ntAssignableSet, ntIndexRange:
    # return literal nodes
    result = node
  of ntHtmlAttribute:
    result = newNode(ntHtmlAttribute)
    result.attrName = node.attrName
    let attrValue = c.getValue(node.attrValue, scopetables)
    notnil attrValue:
      if likely(c.typeCheck(attrValue, ntLitString)):
        result.attrValue = attrValue
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
    result = c.walkStorage(node.lhs, node.rhs, scopetables)
    # result = c.dotEvaluator(node, scopetables)
  of ntConditionStmt:
    result = c.evalCondition(node, scopetables, xel, parentNodeType)
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
  of ntStmtList:
    let lastScope:
      # pops the last ScopeTable from scopetables
      # to prevent direct access to `ntBlock` scope
      #
      # block whatever(x: string, y: block) =
      #   div: $x
      #   $y
      # @whatever, "Hello":
      #   p: "a "
      ScopeTable = scopetables.pop()
    # debugEcho node.meta
    scopetables.newScope() # `ntStmtList` scope
    result = c.walkNodes(node.stmtList, scopetables, parentNodeType, xel)
    scopetables.clearScope()
    add scopetables, lastScope # adding the last ScopeTable back to tables
  of ntHtmlElement, ntStream, ntFunction:
    return node
  of ntLitObject:
    let someObject = c.checkObjectStorage(node, scopetables, false)
    if likely(someObject[0]):
      return someObject[1]
  of ntLitArray:
    let someArray = c.checkArrayStorage(node, scopetables, false)
    if likely(someArray[0]):
      return someArray[1]
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
      of ntParGroupExpr:
        let rhs = c.getValue(rhs.groupExpr, scopetables)
        # debugEcho rhs
        return c.mathInfixEvaluator(lhs, rhs, op, scopetables)
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
      of ntParGroupExpr:
        let rhs = c.getValue(rhs.groupExpr, scopetables)
        return c.mathInfixEvaluator(lhs, rhs, op, scopetables)
      else: discard
    of ntIdent:
      let lhs = c.getValue(lhs, scopetables)
      result = c.mathInfixEvaluator(lhs, rhs, op, scopetables)
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
        notnil rhs:
          result = c.mathInfixEvaluator(lhs, rhs, op, scopetables)
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
          result = c.mathInfixEvaluator(lhs, rhs, op, scopetables) 
      of ntMathInfixExpr: calcInfixNest()
      of ntDotExpr:
        let rhs = c.dotEvaluator(rhs, scopetables)
        notnil rhs:
          result = c.mathInfixEvaluator(lhs, rhs, op, scopetables)
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
    if c.infixEvaluator(branch, boolDefaultCond, EQ, scopetables):
      newScope(scopetables)
      body
      clearScope(scopetables)
      return # condition is thruty
  of ntDotExpr:
    let x = c.dotEvaluator(branch, scopetables)
    notnil x:
      if c.infixEvaluator(x, boolDefaultCond, EQ, scopetables):
        newScope(scopetables)
        body
        clearScope(scopetables)
        return # condition is thruty
  else: discard

proc evalCondition(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable],
    xel: string,
    parentNodeType: NodeType = ntUnknown
): Node {.discardable.} =
  # Evaluates condition branches
  evalBranch node.condIfBranch.expr:
    result =
      c.walkNodes(node.condIfBranch.body.stmtList,
        scopetables, xel = xel,
        parentNodeType = parentNodeType)
  if node.condElifBranch.len > 0:
    # handle `elif` branches
    for elifbranch in node.condElifBranch:
      evalBranch elifBranch.expr:
        result =
          c.walkNodes(elifbranch.body.stmtList, scopetables,
            xel = xel,
            parentNodeType = parentNodeType
          )
  notnil node.condElseBranch:
    # handle `else` branch
    result =
      c.walkNodes(node.condElseBranch.stmtList,
        scopetables,
        xel = xel,
        parentNodeType = parentNodeType)
  if unlikely(result == nil and parentNodeType == ntVariableDef):
    compileErrorWithArgs(fnReturnMissingCommand, ["\"\"", $ntVariableDef])

proc evalCase(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable], xel: string
): Node {.discardable.} =
  # Evaluates a `case` statement
  let caseExpr: Node = c.getValue(node.caseExpr, scopetables)
  var
    i: int
    breakByError: bool
    hasCase: bool
  notnil caseExpr:
    for branch in node.caseBranch:
      let branchExpr = c.getValue(branch.expr, scopetables)
      if likely(c.typeCheck(caseExpr, branchExpr, scopetables = scopetables)):
        if c.infixEvaluator(caseExpr, branchExpr, InfixOp.EQ, scopetables):
          # marks a case then continue walk
          # in order to `typeCheck` the remaining
          # case branches
          hasCase = true
      else:
        hasCase = false
        breakByError = true
        break
      if not hasCase: inc i # then continue the incrementation
  if not breakByError and hasCase:
    newScope(scopetables)
    result = c.walkNodes(node.caseBranch[i].body.stmtList, scopetables, xel = xel)
    clearScope(scopetables)

proc evalConcat(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  var x, y: Node
  x = c.getValue(node.infixLeft, scopetables)
  y = c.getValue(node.infixRight, scopetables)
  if likely(x != nil and y != nil):
    write x, true, false
    write y, true, false

template handleBreakContinue(x: Node) {.dirty.} =
  if x != nil:
    case x.nt
    of ntCommandStmt:
      case x.cmdType
      of cmdBreak: break
      of cmdContinue: continue
      else: discard
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
        let resNode = c.walkNodes(node.loopBody.stmtList,
          scopetables, xel = xel, parentNodeType = ntLoopStmt)
        clearScope(scopetables)
        node.loopItem.varValue = nil
        handleBreakContinue(resNode)
    else: discard # todo error
  of ntLitArray:
    case kv.nt
    of ntVariableDef:
      for x in items.arrayItems:
        newScope(scopetables)
        node.loopItem.varValue = x
        c.varExpr(node.loopItem, scopetables)
        let resNode = c.walkNodes(node.loopBody.stmtList,
          scopetables, xel = xel, parentNodeType = ntLoopStmt)
        clearScope(scopetables)
        node.loopItem.varValue = nil
        handleBreakContinue(resNode)
    else: discard # todo error
  of ntLitObject:
    case kv.nt
    of ntVariableDef:
      for k, y in items.objectItems:
        newScope(scopetables)
        node.loopItem.varValue = y
        c.varExpr(node.loopItem, scopetables)
        let resNode = c.walkNodes(node.loopBody.stmtList,
          scopetables, xel = xel, parentNodeType = ntLoopStmt)
        clearScope(scopetables)
        node.loopItem.varValue = nil
        handleBreakContinue(resNode)
    of ntIdentPair:
      for x, y in items.objectItems:
        newScope(scopetables)
        let kvar = ast.newNode(ntLitString)
        kvar.sVal = x
        node.loopItem.identPairs[0].varValue = kvar
        node.loopItem.identPairs[1].varValue = y
        c.varExpr(node.loopItem.identPairs[0], scopetables)
        c.varExpr(node.loopItem.identPairs[1], scopetables)
        let resNode = c.walkNodes(node.loopBody.stmtList,
          scopetables, xel = xel, parentNodeType = ntLoopStmt)
        clearScope(scopetables)
        node.loopItem.identPairs[0].varValue = nil
        node.loopItem.identPairs[1].varValue = nil
        handleBreakContinue(resNode)
    else: discard
  of ntIndexRange:
    let x = c.getValue(items.rangeNodes[0], scopetables)
    let y = c.getValue(items.rangeNodes[1], scopetables)
    if unlikely(x == nil or y == nil): return
    let xmin = 
      case x.nt
      of ntStream: # todo check is Jint
        x.streamContent.num
      else: x.iVal
    let ymax = 
      case y.nt
      of ntStream: # todo check is Jint
        y.streamContent.num
      else: y.iVal
    for i in xmin .. ymax:
      let intNode = ast.newInteger(i)
      newScope(scopetables)
      node.loopItem.varValue = intNode
      c.varExpr(node.loopItem, scopetables)
      let resNode = c.walkNodes(node.loopBody.stmtList,
        scopetables, xel = xel, parentNodeType = ntLoopStmt)
      clearScope(scopetables)
      node.loopItem.varValue = nil
      handleBreakContinue(resNode)
  of ntStream:
    case kv.nt
    of ntVariableDef:
      case items.streamContent.kind
      of JObject:
        for k, v in items.streamContent:
          node.loopItem.varValue = ast.newStream(v)
          newScope(scopetables)
          c.varExpr(node.loopItem, scopetables)
          let resNode = c.walkNodes(node.loopBody.stmtList,
              scopetables, xel = xel, parentNodeType = ntLoopStmt)
          clearScope(scopetables)
          node.loopItem.varValue = nil
          handleBreakContinue(resNode)
      of JArray:
        for v in items.streamContent:
          node.loopItem.varValue = ast.newStream(v)
          newScope(scopetables)
          c.varExpr(node.loopItem, scopetables)
          let resNode = c.walkNodes(node.loopBody.stmtList,
            scopetables, xel = xel, parentNodeType = ntLoopStmt)
          clearScope(scopetables)
          node.loopItem.varValue = nil
          handleBreakContinue(resNode)
      else: discard # todo handle iterable array/objects from Json
    of ntIdentPair:
      for k, v in items.streamContent:
        newScope(scopetables)
        let kvar = ast.newNode(ntLitString)
        kvar.sVal = k
        node.loopItem.identPairs[0].varValue = kvar
        node.loopItem.identPairs[1].varValue = toTimNode(v)
        c.varExpr(node.loopItem.identPairs[0], scopetables)
        c.varExpr(node.loopItem.identPairs[1], scopetables)
        let resNode = c.walkNodes(node.loopBody.stmtList,
          scopetables, xel = xel, parentNodeType = ntLoopStmt)
        clearScope(scopetables)
        node.loopItem.identPairs[0].varValue = nil
        node.loopItem.identPairs[1].varValue = nil
        handleBreakContinue(resNode)
    else: discard
  else:
    compileErrorWithArgs(invalidIterator)

proc evaluateLoop(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable], xel: string) =
  # Evaluates a `for` statement
  case node.loopItems.nt
  of ntIdent:
    let itemsNode = c.getValue(node.loopItems, scopetables)
    notnil itemsNode:
      loopEvaluator(node.loopItem, itemsNode, xel)
    do: compileErrorWithArgs(undeclaredIdentifier, [node.loopItems.identName])
  of ntDotExpr:
    let items = c.dotEvaluator(node.loopItems, scopetables)
    notnil items:
      loopEvaluator(node.loopItem, items, xel)
  of ntLitArray, ntLitString, ntIndexRange:
    loopEvaluator(node.loopItem, node.loopItems, xel)
  of ntBracketExpr:
    let items = c.bracketEvaluator(node.loopItems, scopetables)
    notnil items:
      loopEvaluator(node.loopItem, items, xel)
  else:
    compileErrorWithArgs(invalidIterator)

proc evalWhile(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable], xel: string) =
  # Evaluates a `while` statement
  while true:
    let expr = c.getValue(node.whileExpr, scopetables)
    notnil expr:
      if likely(expr.nt == ntLitBool):
        if expr.bVal == true:
          newScope(scopetables)
          let x = c.walkNodes(node.whilebody.stmtList, scopetables)
          if unlikely(c.hasErrors):
            clearScope(scopetables)
            break
          notnil x:
            case x.cmdType
            of cmdBreak: break
            else: discard # todo return
          clearScope(scopetables)
        else: break
      else:
        compileErrorWithArgs(typeMismatch,
          [$(expr.nt), $(ntLitBool)])
    do: break

proc typeCheckObject(c: var HtmlCompiler, aNode, bNode: Node, scopetables: var seq[ScopeTable]): bool =
  result = aNode.typeStructDef.objectType.len == bNode.objectItems.len
  if result:
    let tyNode = aNode.typeStructDef
    for k, v in tyNode.objectType:
      if bNode.objectItems.hasKey(k):
        result = getDataType(bNode.objectItems[k]) == tyNode.objectType[k].fieldType
        if unlikely(not result): break
      else:
        return false

proc typeCheck(c: var HtmlCompiler, aNode, bNode: Node,
  scopetables: var seq[ScopeTable]): bool =
  if unlikely(aNode == nil):
    compileErrorWithArgs(typeMismatch, ["none", $(bNode.nt)], bNode.meta)
  if unlikely(aNode.nt != bNode.nt):
    var expectType = $(aNode.nt)
    case aNode.nt
    of ntMathInfixExpr, ntLitInt, ntLitFloat:
      result = bNode.nt in {ntLitInt, ntLitFloat, ntMathInfixExpr} 
    of ntTypeDef:
      notnil aNode.typeStructDef:
        case aNode.typeStructDef.dataType
        of typeObject:
          result = bNode.nt == ntLitObject
          expectType = aNode.typeIdent
          if result:
            result = c.typeCheckObject(aNode, bNode, scopetables)
          if unlikely(not result):
            compileErrorWithArgs(typeMismatchObject, [expectType], bNode.meta)
        else:
          echo "todoo"
          discard
    of ntVariableDef:
      notnil aNode.varValueType:
        let tyDefNode: Node =
          c.fromScope(aNode.varValueType.typeName, scopetables)
        return c.typeCheck(tyDefNode, bNode, scopetables)
    else: discard
    if not result:
      compileErrorWithArgs(typeMismatch, [$(bNode.nt), expectType], bNode.meta)
  result = true

proc typeCheck(c: var HtmlCompiler, node: Node,
    expect: NodeType, parent: Node = nil): bool =
  if unlikely(node == nil):
    let node = parent
    compileErrorWithArgs(typeMismatch, ["none", $(expect)])
  if unlikely(node.nt != expect):
    if node.nt == ntStmtList and expect == ntBlock:
      return true
    compileErrorWithArgs(typeMismatch, [$(node.nt), $(expect)])
  result = true

proc typeCheck(c: var HtmlCompiler, node: Node, expect: HtmlTag): bool =
  if unlikely(node.tag != expect):
    let x = $(expect)
    compileErrorWithArgs(typeMismatch, [node.getTag, toLowerAscii(x[3..^1])])
  result = true

proc typeCheck(c: var HtmlCompiler, aTyped: TypeDefinition, bTyped: DataType,
    scopetables: var seq[ScopeTable]): bool =
  # Check `aTyped` with `bTyped` TypeDefinition
  # and determine if type matches
  result = aTyped.datatype == bTyped

#
# Compile Handlers
#
proc checkObjectStorage(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable],
    needsCopy = false): (bool, Node) =
  # a simple checker and ast modified for object storages
  for k, v in node.objectItems.mpairs:
    case v.nt
    of ntLitInt, ntLitString, ntLitBool, ntLitFloat: discard
    of ntLitArray:
      let someArray = c.checkArrayStorage(v, scopetables)
      if likely(someArray[0]):
        discard
      else: return
    else:
      let v = c.getValue(v, scopetables)
      notnil v:
        discard
      do: return
  return (true, node)

proc checkArrayStorage(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable],
    needsCopy = false): (bool, Node) =
  # a simple checker and ast modified for array storages
  # let arrayNode =
  #   if needsCopy: deepCopy node
  #           else: node
  for v in node.arrayItems.mitems:
    let valNode = c.getValue(v, scopetables)
    notnil valNode:
      discard
    do: return (false, nil)
  return (true, node)

proc newReferenceVar(varNode, varValue: Node): Node =
  result = ast.newNode(ntReference)
  result.refNode = varNode
  result.refValue = varValue

proc getIdentName(x: Node): string =
  result = 
    case x.nt
      of ntDotExpr:
        x.lhs.identName
      of ntBracketExpr:
        x.bracketLHS.identName
      of ntIdent:
        x.identName
      else: ""

proc setVarValue(c: var HtmlCompiler, identName: string,
    isImmutable: bool, node, bNode: Node, scopetables: var seq[ScopeTable]) =
  # Modifies the current `node` value with `bNode` 
  if likely(c.typeCheck(node, bNode, scopetables = scopetables)):
    if likely(not isImmutable):
      case node.nt
      of ntLitString:
        node.sVal = bNode.sVal
      of ntLitInt:
        node.iVal = bNode.iVal
      of ntLitFloat:
        node.fVal = bNode.fVal
      of ntLitBool:
        node.bVal = bNode.bVal
      of ntLitObject:
        node.objectItems = bNode.objectItems
      of ntLitArray:
        node.arrayItems = bNode.arrayItems
      else: discard
    else:
      compileErrorWithArgs(varImmutable, [identName])

proc assignExpr(c: var HtmlCompiler,
    node: Node, scopetables: var seq[ScopeTable]) =
  # Handle assignment expressions
  let identName = node.asgnIdent.getIdentName()
  let some = c.getScope(identName, scopetables)
  if likely(some.scopeTable != nil):
    let varNode = some.scopeTable.get(identName)
    let asgnValue = c.getValue(node.asgnVal, scopetables)
    notnil asgnValue:
      case node.asgnIdent.nt
      of ntDotExpr:
        let initialValue = c.getValue(node.asgnIdent, scopetables)
        c.setVarValue(identName, varNode.refNode.varImmutable,
          initialValue, asgnValue, scopetables)
      of ntBracketExpr:
        case varNode.refValue.nt
        of ntLitObject:
          discard c.walkStorage(varNode.refValue,
            node.asgnIdent.bracketIndex, scopetables,
            asgnValue
          )
        else:
          let initialValue = c.getValue(node.asgnIdent, scopetables)
          notnil initialValue:
            c.setVarValue(identName, varNode.refNode.varImmutable,
              initialValue, asgnValue, scopetables)
          do:
            discard c.walkStorage(varNode.refValue,
              node.asgnIdent.bracketIndex, scopetables, asgnValue)
      else:
        var initialValue: Node
        case varNode.nt
        of ntReference:
          notnil varNode.refValue:
            case varNode.refValue.nt
            of ntLitObject, ntLitArray:
              initialValue = deepCopy(varNode.refValue)
            else:
              initialValue = varNode.refValue
          do:
            if likely(varNode.varValueType.datatype == typeIdentifier):
              initialValue = c.fromScope(varNode.varValueType.typeName, scopetables)
        of ntLitString, ntLitInt, ntLitFloat, ntLitBool:
          initialValue = varNode.refValue
        else: discard
        if likely(c.typeCheck(initialValue, asgnValue, scopetables = scopetables)):
          if likely(not varNode.refNode.varImmutable):
            varNode.refValue = asgnValue
          else:
            compileErrorWithArgs(varImmutable, [varNode.refNode.varName])

proc varExpr(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable]) =
  # Evaluates a variable
  if likely(not c.inScope(node.varName, scopetables)):
    notnil node.varValue:
      var checkedValue: bool
      var valNode: Node
      case node.varValue.nt
      of ntLitObject:
        let someObject = c.checkObjectStorage(node.varValue, scopetables, false)
        if someObject[0]:
          checkedValue = true
          valNode = someObject[1]
      of ntLitArray:
        let someArray = c.checkArrayStorage(node.varValue, scopetables, false)
        if someArray[0]:
          checkedValue = true
          valNode = someArray[1]
      of ntStream:
        valNode = c.getValue(node.varValue,
          scopetables, parentNodeType = ntVariableDef)
        notnil valNode:
          checkedValue = true
          node.varValue = valNode
      of ntIdent:
        valNode = c.getValue(node.varValue, scopetables,
                    parentNodeType = ntVariableDef)
        notnil valNode:
          checkedValue = true
          case valNode.nt
          of ntStream:
            node.varValue = valNode
          else:
            node.varValue = deepCopy(valNode)
      else:
        valNode = c.getValue(node.varValue,
          scopetables, parentNodeType = ntVariableDef)
        notnil valNode:
          checkedValue = true
          node.varValue = valNode
      if checkedValue:
        notnil node.varValueType:
          if unlikely(not c.typeCheck(node, valNode, scopetables)):
            return
        do: discard
        c.stack(node.varName, newReferenceVar(node, node.varValue), scopetables)
    do:
      if likely(node.varValueType.datatype == typeIdentifier):
        let distinctNode = c.fromScope(node.varValueType.typeName, scopetables)
        notnil distinctNode:
          node.varValue = getDefaultValue(distinctNode.typeStructDef.datatype)
          new(node.varValue.objectItems)
          for fname, fstruct in distinctNode.typeStructDef.objectType:
            notnil fstruct.fieldTypeImpl:
              node.varValue.objectItems[fname] = deepCopy(fstruct.fieldTypeImpl)
            do:
              node.varValue.objectItems[fname] = fstruct.fieldType.getDefaultValue()
          # debugEcho distinctNode
          c.stack(node.varName, node, scopetables)
        do:
          compileErrorWithArgs(undeclaredIdentifier, [node.varValueType.typeName])
  else: compileErrorWithArgs(identRedefine, [node.varName])

proc typeDef(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
  ## Handle `type` definition blocks
  # $(ord(node.typeStructDef.paramDataTypeValue))
  if likely(not c.inScope(node.typeIdent, scopetables)):
    c.stack(node.typeIdent, node, scopetables)
    c.stack(node.typeIdent & ":" & $ord(node.typeStructDef.datatype), node, scopetables)
  else:
    compileErrorWithArgs(identRedefine, [node.typeIdent])  

template strictCheck() =
  if excludes.len > 0:
    if unlikely(node.nt in excludes):
      compileErrorWithArgs(invalidContext, [$(node.nt)], node.meta)
  if includes.len > 0:
    if unlikely(node.nt notin includes):
      compileErrorWithArgs(invalidContext, [$(node.nt)], node.meta)

proc analyzeNode(c: var HtmlCompiler, node: var Node,
    fnNode: Node, scopetables: var seq[ScopeTable]) =
  # fnNode.fnLazyScope = ScopeTable()
  case node.nt
  of ntCommandStmt:
    case node.cmdType
    of cmdReturn:
      let x = node.cmdValue
      case x.nt
      of ntLitString, ntLitInt, ntLitFloat, ntLitBool:
        if unlikely(x.nt != fnNode.fnReturnType):
          compileErrorWithArgs(typeMismatch, [$(x.nt), $fnNode.fnReturnType])
      of ntIdent:
        let x = c.getValue(node.cmdValue, scopetables)
        notnil x:
          if unlikely(x.nt == fnNode.fnReturnType):
            node.cmdValue = x
          else:
            compileErrorWithArgs(typeMismatch, [$(x.nt), $fnNode.fnReturnType])
      else: discard
    of cmdEcho:
      case node.cmdValue.nt
      of ntIdent:
        let v: Node = c.getValue(node.cmdValue, scopetables)
        notnil v:
          node.cmdValue = v
      else: discard
    else: discard
  of ntVariableDef:
    # Handle variable definitions
    c.varExpr(node, scopetables)
    node = node.varValue
  of ntHtmlElement:
    for attr in node.htmlAttributes:
      case attr.nt
      of ntHtmlAttribute:
        notnil attr.attrValue:
          if attr.attrValue.nt == ntIdent:
            for arg in attr.attrValue.identArgs.mitems:
              let val = c.getValue(arg, scopetables)
              notnil val:
                let key =
                  if arg.identName.len > 1:
                    hash(arg.identName[0] & arg.identName[1..^1].toLowerAscii)
                  else: hash(arg.identName)
                arg = val
                # let lazyVarNode = newVariable(arg.identName, val, val.meta)
                # fnNode.fnLazyScope.data[key] = lazyVarNode
        do: discard
      else: discard
  else: discard

proc walkFunctionBody(c: var HtmlCompiler, fnNode, fnBody: Node,
    scopetables: var seq[ScopeTable],
    xel = newStringOfCap(0),
    includes, excludes: set[NodeType] = {}
): Node {.discardable.} =
  # Walk through function's body and analyze the nodes
  for node in fnBody.stmtList.mitems():
    strictCheck()
    c.analyzeNode(node, fnBody, scopetables)

proc getFunctionIdent(c: var HtmlCompiler, node: Node,
  scopetables: var seq[ScopeTable]): string =
  result = node.fnIdent.identName
  for arg in node.fnIdent.identArgs:
    let v = c.getValue(arg, scopetables)
    notnil v:
      add result, v.toString

proc functionDefinition(c: var HtmlCompiler, node: Node,
    scopetables: var seq[ScopeTable],
    parentNodeType: NodeType = ntUnknown
) =
  # Handle function definitions
  let node = 
    if parentNodeType in {ntLoopStmt}: deepCopy(node)
    else: node
  var
    identName = c.getFunctionIdent(node, scopetables)
    identNameNoImplicit = identName
    hasImplicitValues: bool
    strParams: seq[string]
  if node.fnParams.len > 0:
    # add identName, ":"
    if not hasImplicitValues:
      add identNameNoImplicit, ":"
    for k, p in node.fnParams.mpairs:
      add strParams, k
      notnil p.paramImplicitValue:
        # if parameter provides an implicit value
        # add identName, $(p.paramDataTypeValue.ord)
        let implValue = c.getValue(p.paramImplicitValue, scopetables)
        notnil implValue:
          if likely(p.paramType == ntUnknown):
            # determine type of the parameter from its implicit value
            p.paramType = implValue.nt
          elif unlikely(not c.typeCheck(implValue, p.paramType)):
            return
          add strParams[^1], " = " & p.paramImplicitValue.toString()
          hasImplicitValues = true
        do: return
      do:
        # add identName, $(p.paramDataTypeValue.ord)
        add strParams[^1], ": " & $(p.paramDataTypeValue)
        # add identNameNoImplicit, $(p.paramDataTypeValue.ord)
        if p.paramDataTypeValue == typeIdentifier:
          # handle parameter definition using distinct types
          let distinctNode = c.fromScope(p.pTypeName, scopetables)
          # notnil distinctNode:
            # add identName, p.pTypeName
          # do: compileErrorWithArgs(undeclaredIdentifier, [p.pTypeName])
  if parentNodeType in {ntLoopStmt} and node.fnBody != nil:
    c.walkFunctionBody(node, node.fnBody, scopetables)
    if likely(not c.inGlobalScope(identName)):
      c.newStackSeq(identName, scopetables, toGlobalStack = true)
      c.globalScope(identName, node)
    else:
      compileErrorWithArgs(identRedefine, [node.fnIdent.identName])
  else:
    if likely(not c.inScope(identName, scopetables)):
      c.newStackSeq(identName, scopetables)
      c.stack(identName, node, scopetables)

  # if hasImplicitValues:
  #   if likely(not c.inGlobalScope(identNameNoImplicit, scopetables)):
  #     c.stack(identNameNoImplicit, node, scopetables)
  #   else:
  #     let preview = "$1 $2($3)" % [$(node.nt), node.fnIdent.identName, strParams.join("; ")]
  #     compileErrorWithArgs(identRedefine, [preview])
  # if node.fnBody != nil:
  #   c.walkFunctionBody(node, node.fnBody.stmtList.addr, scopetables,
  #     excludes = {ntImport, ntComponent}
  #   )

# const jsComponent = """
# window.customElements.define('$1', class extends HTMLElement{constructor(){super();}})
# """
# proc componentDef(c: var HtmlCompiler, node: Node, scopetables: var seq[ScopeTable]) =
#   # Define a Component 
#   if likely(not c.inScope(node.componentIdent, scopetables)):
#     # c.stack(node.componentIdent, node, scopetables)
#     for x in node.componentName:
#       case x
#         of 'a'..'z', '-': continue
#         else: 
#           compileErrorWithArgs(invalidComponentName, [node.componentName])
#     c.isClientSide = true
#     c.jsOutputCode = ""
#     add c.jsOutputCode, jsComponent % [node.componentName]
#     newScope scopetables
#     discard c.walkNodes(node.componentBody.stmtList,
#       scopetables, includes = {ntFunction})
#     clearScope scopetables
#     c.jsOutputComponents[node.componentIdent] = c.jsOutputCode
#     echo c.jsOutputCode
#     setLen(c.jsOutputCode, 0)
#     c.isClientSide = false
#   else:
#     compileErrorWithArgs(identRedefine, [node.componentIdent])

proc unwrapBlock(c: var HtmlCompiler, node, blockNode: Node,
  scopetables: var seq[ScopeTable]): Node =
  # Unwraps a BlockIdentifier node
  let params = blockNode.fnParams.keys.toSeq()
  newScope(scopetables)
  if node.identArgs.len > 0:
    var i = 0
    for pName in params:
      let param = blockNode.fnParams[pName]
      try:
        case node.identArgs[i].nt
        of ntStmtList:
          let argValue = node.identArgs[i]
          let varNode = ast.newVariable(pName, argValue, argValue.meta)
          if not c.typeCheck(argValue, param.paramType):
            return # typeCheck returns `typeMismatch`
          c.stack(pName, varNode, scopetables)
        else:
          let argValue = c.getValue(node.identArgs[i], scopetables)
          let varNode = ast.newVariable(pName, argValue, argValue.meta)
          notnil argValue:
            if not c.typeCheck(argValue, param.paramType):
              return  # typeCheck returns `typeMismatch`
            c.stack(pName, varNode, scopetables)
      except IndexDefect:
        if likely(param.paramImplicitValue != nil):
          let varNodeImpl = ast.newVariable(pName, param.paramImplicitValue, param.meta)
          varNodeImpl.varValue = param.paramImplicitValue
          c.stack(pName, varNodeImpl, scopetables)
        else:
          compileErrorWithArgs(typeMismatch, ["none", $param.paramType], param.meta)
          return nil
      inc i
    if unlikely(i < node.identArgs.len):
      # check for extra arguments
      compileErrorWithArgs(fnExtraArg, [$(node.identArgs.len), $(params.len)])
    result = c.walkNodes(blockNode.fnBody.stmtList, scopetables, blockNode.nt)
    clearScope(scopetables)
  # reset(asgnValArgs)

proc unwrapArgs(c: var HtmlCompiler, args: seq[Node],
    scopetables: var seq[ScopeTable]): tuple[resolvedArgs, htmlAttributes: seq[Node]] =
  # Returns a sequence of Node values from available arguments
  for arg in args:
    case arg.nt
    of ntStmtList:
      add result[0], arg # `block` type expects ntStmtList
    of ntHtmlAttribute:
      add result[1], arg
    else:
      let v = c.getValue(arg, scopetables)
      notnil v:
        add result[0], v
      do:
        setLen(result[0], 0)

proc unwrap(identName: string, args: seq[Node]): string =
  result = identName
  if args.len > 0:
    add result, ":"
    for arg in args:
      add result, $(arg.getDataType.ord)

proc functionCall(c: var HtmlCompiler, node, fnNode: Node,
  args: seq[Node], scopetables: var seq[ScopeTable],
  htmlAttrs: seq[Node] = @[], xel = newStringOfCap(0),
  parentNodeType: NodeType = ntUnknown
): Node =
  # Evaluates calls of `function`, `block` and `component` nodes
  case fnNode.fnType
  of fnImportSystem:
    # Tim's Standard Library is based from Nim's stdlib,
    # so functions set as `fnImportSystem` don't need to 
    # have a function body in timl, as these will emit
    # Tim AST nodes
    var stdargs: seq[std.Arg]
    var i = 0
    for pName in fnNode.fnParams.keys:
      let param = fnNode.fnParams[pName]
      try:
        let arg = args[i]
        add stdargs, (param[0][1..^1], args[i])
      except IndexDefect:
        notnil param.paramImplicitValue:
          add stdargs, (param[0][1..^1], param.paramImplicitValue)
        do:
          compileErrorWithArgs(typeMismatch, ["none", $param.paramType], param.meta)
      inc i
    try:
      result = std.call(fnNode.fnSource, node.identName, stdargs)
      if result != nil:
        case result.nt
        of ntRuntimeCode:
          {.gcsafe.}:
            var p: Parser = parser.parseSnippet("", result.runtimeCode)
            let phc = newCompiler(parser.getAst(p))
            if not phc.hasErrors:
              add c.output, phc.getHtml()
            return nil
        else: discard
        return # result
    except SystemModule as e:
      compileErrorWithArgs(internalError,
        [e.msg, fnNode.fnSource, fnNode.fnIdent.identName], node.meta)
    # of fnImportModule:
    # Handle imports from packages. Importing a package's module
    # can be done using `pkg` prefix at import statemtent, for example
    # `@import "pkg/bootstrap"
    discard # todo
  else:
    if c.ast.src != fnNode.fnSource:
      if unlikely(not fnNode.fnExport):
        compileErrorWithArgs(fnUndeclared, [fnNode.fnIdent.identName])
    # Create a new scope for passing the arguments
    newScope(scopetables)
    notnil fnNode.fnParams:
      var i = 0
      for pName in fnNode.fnParams.keys:
        let param = fnNode.fnParams[pName]
        try:
          if not param.isMutable:
            let pVar = ast.newVariable(pName, args[i], args[i].meta)
            c.stack(pName, pVar, scopetables)
          else:
            discard # todo handle mutable variables
        except:
          if param.paramImplicitValue != nil:
            let pVar = ast.newVariable(pName, param.paramImplicitValue, param.paramImplicitValue.meta)
            c.stack(pName, pVar, scopetables)
          else:
            compileErrorWithArgs(typeMismatch, [$(typeNone), $(param.paramDataTypeValue)])
        inc i
    if fnNode.nt == ntBlock:
      # adds support for calling blocks by attaching classes,
      # id or any other custom Html attributes. then inside the block,
      # we can tretrieve the available attributes using the
      # `blockAttributes` variable
      let blockAttrs = ast.newArray()
      # `=sink`(blockAttrs.arrayItems, htmlAttrs[])
      if htmlAttrs.len > 0:
        blockAttrs.arrayItems = htmlAttrs
      let blockAttributes =
        ast.newVariable("blockAttributes", blockAttrs, node.meta)
      blockAttributes.varImmutable = true # blockAttributes cannot be changed
      c.stack("blockAttributes", blockAttributes, scopetables)
    let parentNodeType =
      if parentNodeType == ntUnknown: node.nt
      else: parentNodeType
    notnil fnNode.fnBody:
      result = c.walkNodes(fnNode.fnBody.stmtList,
          scopetables, parentNodeType, xel)
    do:
      compileErrorWithArgs(unimplementedForwardDeclaration,
        [fnNode.fnIdent.identName], fnNode.meta)
    notnil result:
      clearScope(scopetables)
      case result.nt
      of ntHtmlElement:
        if c.typeCheck(result, fnNode.fnReturnHtmlElement):
          return c.walkNodes(@[result], scopetables, xel = xel)
        result = nil
      else:
        let x = c.getValue(result, scopetables)
        notnil x:
          if unlikely(c.typeCheck(x, fnNode.fnReturnType, x)):
            return x
          result = nil
    do:
      clearScope(scopetables)

proc componentCall(c: var HtmlCompiler, componentNode: Node,
    scopetables: var seq[ScopeTable]): Node =
  # Transpile a Tim Component to JavaScript
  return componentNode

proc getAttrs(c: var HtmlCompiler, attrs: HtmlAttributesTable,
    scopetables: var seq[ScopeTable], xel = newStringOfCap(0)): string =
  var i = 0
  var skipQuote: bool
  let len = attrs.len
  for k, attrNodes in attrs:
    if not c.isClientSide:
      add result, indent("$1=" % k, 1) & "\""
    var attrValues: seq[string]
    for attrNode in attrNodes:
      case attrNode.nt
      of ntHtmlAttribute:
        add attrValues,
          c.toString(attrNode.attrValue, scopetables)
      else:
        add attrValues,
          c.toString(attrNode, scopetables)
    if not c.isClientSide:
      add result, attrValues.join(" ")
      if not skipQuote and i != len:
        add result, "\""
      else:
        skipQuote = false
      inc i
    else:
      add result, domSetAttribute % [xel, k, attrValues.join(" ")]

proc prepareHtmlAttributes(c: var HtmlCompiler,
    attrs: sink seq[Node], attrsTable: HtmlAttributesTable,
    scopetables: var seq[ScopeTable],
    xel = newStringOfCap(0)) =
  ## Evaluate available HTML Attributes of HtmlElement `node`
  for attr in attrs:
    case attr.nt
    of ntStmtList:
      c.prepareHtmlAttributes(attr.stmtList, attrsTable, scopetables)
    of ntHtmlAttribute:
      if attrsTable != nil:
        if not attrsTable.hasKey(attr.attrName):
          attrsTable[attr.attrName] = newSeq[Node]()
        notnil attr.attrValue:
          case attr.attrValue.nt
          of ntLitString, ntLitInt, ntLitBool, ntStream, ntDotExpr, ntBracketExpr:
            let val = c.getValue(attr.attrValue, scopetables)
            notnil val:
              add attrsTable[attr.attrName], val
          of ntIdent:
            if attr.attrValue.identArgs.len > 0:
              var strValue = attr.attrValue.identName
              for arg in attr.attrValue.identArgs:
                let val = c.getValue(arg, scopetables)
                notnil val:
                  add strValue, val.toString
              add attrsTable[attr.attrName],
                ast.newString(strValue)
            else:
              let val = c.getValue(attr.attrValue, scopetables)
              notnil val:
                add attrsTable[attr.attrName],
                  ast.newString(val.toString)
          else: discard # todo error?
        do: discard # attrValue can be nil when the attribute has no value
    of ntParGroupExpr:
      let attrNode = c.getValue(attr.groupExpr, scopetables)
      if not attrsTable.hasKey(attrNode.attrName):
        attrsTable[attrNode.attrName] = newSeq[Node]()
      notnil attrNode:
        add attrsTable[attrNode.attrName], attrNode.attrValue
    of ntConditionStmt:
      let x = c.evalCondition(attr, scopetables, xel)
      notnil x:
        if not attrsTable.hasKey(x.attrName):
          attrsTable[x.attrName] = newSeq[Node]()
          add attrsTable[x.attrName], x
    of ntIdent:
      let x = c.getValue(attr, scopetables, xel)
      notnil x:
        case x.nt
        of ntLitArray:
          c.prepareHtmlAttributes(x.arrayItems, attrsTable, scopetables)
        else: discard # todo handle objects
    else: discard

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
    if x.htmlAttributes.len > 0:
      let htmlAttributes = HtmlAttributesTable()
      c.prepareHtmlAttributes(x.htmlAttributes, htmlAttributes, scopetables)
      add c.output, c.getAttrs(htmlAttributes, scopetables)
    # if x.attrs != nil:
    #   if x.attrs.len > 0:
    #     add c.output, c.getAttrs(x.attrs, scopetables)
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
  if likely(node.htmlMultiplyBy == nil):
    htmlblock node:
      c.walkNodes(node.nodes, scopetables, ntHtmlElement)
    return
  newScope(scopetables)
  let multiplyVar = ast.newNode(ntVariableDef)
  multiplyVar.varName = "i"
  multiplyVar.varValue = ast.newNode(ntLitInt)
  c.varExpr(multiplyVar, scopetables)
  var multiplier: int
  case node.htmlMultiplyBy.nt
  of ntLitInt:
    multiplier = node.htmlMultiplyBy.iVal
  of ntIdent:
    let x = c.getValue(node.htmlMultiplyBy, scopetables)
    notnil x:
      if likely(x.nt == ntLitInt):
        multiplier = x.iVal
      else:
        compileErrorWithArgs(typeMismatch, [$(x.nt), $(ntLitInt)])
  else: compileErrorWithArgs(typeMismatch, [$(node.htmlMultiplyBy.nt), $(ntLitInt)])
  for i in 1..multiplier:
    multiplyVar.varValue.iVal = (i - 1)
    htmlblock node:
      c.walkNodes(node.nodes, scopetables, ntHtmlElement)
  clearScope(scopetables)

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
  if unlikely(c.placeholders == nil): return
  if c.placeholders.hasPlaceholder(node.placeholderName):
    var i = 0
    for tree in c.placeholders.snippets(node.placeholderName):
      let phc = newCompiler(tree)
      if not phc.hasErrors:
        add c.output, phc.getHtml()
      else:
        echo "ignore snippet"
        c.placeholders.deleteSnippet(node.placeholderName, i)
      inc i
#
# JS API
#
proc jsHtmlElement(c: var HtmlCompiler, x: Node,
    scopetables: var seq[ScopeTable], pEl: string,
    parentNodeType: NodeType
) =
  ## Create a new HtmlElement
  let xel = "el" & $(c.jsCountEl)
  add c.jsOutputCode, domCreateElement % [xel, x.getTag()]
  if x.htmlAttributes.len > 0:
    let htmlAttributes = HtmlAttributesTable()
    c.prepareHtmlAttributes(x.htmlAttributes, htmlAttributes, scopetables)
    add c.jsOutputCode, c.getAttrs(htmlAttributes, scopetables, xel)
  inc c.jsCountEl
  if x.nodes.len > 0:
    c.walkNodes(x.nodes, scopetables, parentNodeType, xel = xel)
  if pEl.len > 0:
    add c.jsOutputCode,
      domInsertAdjacentElement % [pEl, xel]
  else:
    add c.jsOutputCode,
      domInsertAdjacentElement %
        ["document.querySelector('" & c.jsTargetElement & "')", xel]

template writeBracketExpr =
  let x = c.bracketEvaluator(node, scopetables)
  notnil x:
    if not c.isClientSide:
      write x, true, false
    else:
      add c.jsOutputCode, domInnerText % [xel, c.toString(x, scopetables)]

template writeDotExpression =
  let x: Node = c.dotEvaluator(node, scopetables)
  notnil x:
    if not c.isClientSide:
      write x, true, false
    else:
      add c.jsOutputCode, domInnerText % [xel, c.toString(x, scopetables)]

proc walkNodes(c: var HtmlCompiler, nodes: seq[Node],
    scopetables: var seq[ScopeTable], parentNodeType: NodeType = ntUnknown,
    xel = newStringOfCap(0), includes, excludes: set[NodeType] = {}
): Node {.discardable.} =
  # Evaluate a sequence of nodes
  for i in 0..nodes.high:
    let node = nodes[i]
    strictCheck()
    case node.nt
    of ntHtmlElement:
      if parentNodeType == ntStmtList:
        return node
      if likely(not c.isClientSide):
        # Write HTMLElement
        c.htmlElement(node, scopetables)
      else:
        # Write HTMLElement via JavaScript
        # for client-side rendering
        c.jsHtmlElement(node, scopetables, xel, parentNodeType)
    of ntIdent, ntBlockIdent:
      # Handle variable/function/block calls
      let x: Node = c.getValue(node, scopetables, xel, parentNodeType)
      notnil x:
        if parentNodeType notin {ntFunction, ntHtmlElement, ntBlock, ntLoopStmt, ntClientBlock} and
          x.nt notin {ntHtmlElement, ntLitVoid}:
            compileErrorWithArgs(fnReturnMissingCommand, [node.identName, $(x.nt)])
        if not c.isClientSide:
          write x, true, node.identSafe
        else:
          # add c.jsOutputCode, domInnerText % [xel, c.toString(x, scopetables)]
          add c.jsOutputCode, domInnerHtml % [xel, c.toString(x, scopetables)]
    of ntDotExpr:     writeDotExpression()
    of ntBracketExpr: writeBracketExpr()
    of ntVariableDef:
      # Handle variable definitions
      c.varExpr(node, scopetables)
    of ntTypeDef:
      c.typeDef(node, scopetables)
    of ntCommandStmt:
      # Handle `echo`, `return` and `discard` command statements
      case node.cmdType
      of cmdReturn, cmdBreak, cmdContinue:
        return c.evalCmd(node, scopetables, parentNodeType)
      else:
        discard c.evalCmd(node, scopetables, parentNodeType)
    of ntAssignExpr:
      # Handle assignments
      c.assignExpr(node, scopetables)
    of ntConditionStmt:
      # Handle conditional statemetns
      result = c.evalCondition(node, scopetables, xel)
      notnil result:
        # ntCommandStmt Node resulted as cmdReturn
        return
      do: discard
    of ntCaseStmt:
      result = c.evalCase(node, scopetables, xel)
    of ntLoopStmt:
      # Handle `for` loop statements
      c.evaluateLoop(node, scopetables, xel)
    of ntWhileStmt:
      # Handle `while` loop statements
      c.evalWhile(node, scopetables, xel)
    of ntLitString, ntLitInt, ntLitFloat, ntLitBool:
      if parentNodeType == ntVariableDef:
        return node
      if likely(not c.isClientSide):
        # Handle literals
        write node, true, false
      else:
        # Handle literals for client-side rendering
        add c.jsOutputCode, domInnerText % [xel, c.toString(node, scopetables)]
    of ntMathInfixExpr:
      # Handle math expressions
      let x: Node =
        c.mathInfixEvaluator(node.infixMathLeft,
          node.infixMathRight, node.infixMathOp, scopetables)
      write x, true, false
    of ntFunction, ntBlock:
      # Handle function/block definitions
      c.functionDefinition(node, scopetables, parentNodeType)
    # of ntComponent:
      # Handle component definition
      # c.componentDef(node, scopetables)
    of ntEscape:
      # Handle escaped values
      var output: string
      let xVal = c.getValue(node, scopetables)
      notnil xVal:
        add output, xVal.toString
      add c.output, output
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
      if node.snippetCodeAttrs.len == 0:
        add c.jsOutput, node.snippetCode
      else:
        var values: seq[(string, string)]
        # todo fix dot/bracket expressions
        # debugEcho node.snippetCodeAttrs
        for attr in node.snippetCodeAttrs:
          # debugEcho attr[1]
          let x = c.getValue(attr[1], scopetables)
          notnil x:
            add values, ("%*" & attr[0], x.toString())
        add c.jsOutput, node.snippetCode.multiReplace(values)
    of ntJsonSnippet:
      # Handle `@json` blocks
      let id =
        if node.snippetId.len > 0:
          "id=\"" & node.snippetId & "\""
        else: ""
      try:
        add c.jsonOutput, "\n" & ("<script $1type=\"application/json\">" % id)
        add c.jsonOutput, jsony.toJson(jsony.fromJson(node.snippetCode))
        add c.jsonOutput, "</script>"
      except jsony.JsonError as e:
        compileErrorWithArgs(internalError, node.meta, [e.msg])
    of ntClientBlock:
      # Handle `@client` blocks
      c.jsTargetElement = node.clientTargetElement
      c.isClientSide = true
      #       add c.jsOutputCode, """
      # let tim = {
      #   el: (x) => document.createElement(x),
      #   q: (x) => document.querySelector(x),
      #   add: (pos, x, y) => x.insertAdjacentElement(pos, y)
      # }
      #       """
      c.walkNodes(node.clientStmt, scopetables, ntClientBlock, xel = xel)
      if node.clientBind != nil:
        add c.jsOutputCode,  "{" & node.clientBind.doBlockCode & "}"
      add c.jsOutputCode, "}"
      add c.jsOutput,
        "document.addEventListener('DOMContentLoaded', function(){"
      add c.jsOutput, c.jsOutputCode
      add c.jsOutput, "});"
      c.jsOutputCode = "{" # prepare block for next client-side process
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
proc newCompiler*(engine: TimEngine, ast: Ast,
    tpl: TimTemplate, minify = true, indent = 2,
    data: JsonNode = newJObject(),
    placeholders: TimEngineSnippets = nil): HtmlCompiler =
  ## Create a new instance of `HtmlCompiler`
  assert indent in [2, 4]
  if unlikely(ast == nil): return
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
      placeholders: placeholders
    )
  if minify: setLen(result.nl, 0)
  var scopetables = newSeq[ScopeTable]()
  var globalStorage, localStorage: JsonNode
  if data != nil:
    if data.hasKey"global":
      globalStorage = data["global"]
    else:
      globalStorage = newJObject()
    if data.hasKey"local":
      localStorage = data["local"]
    else:
      localStorage = newJObject()
  let
    globalScope = newVariable("app", newStream(globalStorage), [1, 0, 0])
    localScope = newVariable("this", newStream(localStorage), [1, 0, 0])
  globalScope.varImmutable = true
  localScope.varImmutable = true
  result.varExpr(globalScope, scopetables)
  result.varExpr(localScope, scopetables)
  for moduleName, moduleAst in result.ast.modules:
    result.walkNodes(moduleAst.nodes, scopetables)
  result.walkNodes(result.ast.nodes, scopetables)

proc newCompiler*(ast: Ast, minify = true, indent = 2,
  data: JsonNode = nil,
  placeholders: TimEngineSnippets = nil
): HtmlCompiler =
  ## Create a new instance of `HtmlCompiler
  assert indent in [2, 4]
  if unlikely(ast == nil): return
  result = HtmlCompiler(
    ast: ast,
    start: true,
    tplType: ttView,
    logger: Logger(filePath: ast.src),
    minify: minify,
    indent: indent,
    data: %*{
      "global": {},
      "local": {}
    },
    placeholders: placeholders
  )
  var scopetables = newSeq[ScopeTable]()
  var globalStorage, localStorage: JsonNode
  if data != nil:
    if data.hasKey"global":
      globalStorage = data["global"]
    else:
      globalStorage = newJObject()
    if data.hasKey"local":
      localStorage = data["local"]
    else:
      localStorage = newJObject()
  let
    globalScope = newVariable("app", newStream(globalStorage), [1, 0, 0])
    localScope = newVariable("this", newStream(localStorage), [1, 0, 0])
  globalScope.varImmutable = true
  localScope.varImmutable = true
  result.varExpr(globalScope, scopetables)
  result.varExpr(localScope, scopetables)
  if minify: setLen(result.nl, 0)
  for moduleName, moduleAst in result.ast.modules:
    result.walkNodes(moduleAst.nodes, scopetables)
  result.walkNodes(result.ast.nodes, scopetables)

proc getHtml*(c: HtmlCompiler): string =
  ## Get the compiled HTML
  if c.tplType == ttView and c.jsonOutput.len > 0:
    add result, c.jsonOutput
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

proc getComponents*(c: HtmlCompiler): string =
  ## Returns available JS components
  if c.jsOutputComponents.len > 0:
    for x, y in c.jsOutputComponents:
      add result, y

proc getComponent*(c: HtmlCompiler, key: string, inlineUsage = false): string =
  ## Return a specific JS component by `key`.
  ## Enable `inlineUsage` for making the component 
  ## available via event listener `DOMContentLoaded`
  if likely(c.jsOutputComponents.hasKey(key)):
    if inlineUsage:
      add result, "document.addEventListener('DOMContentLoaded', function(){\n"
      add result, c.jsOutputComponents[key]
      add result, "\n});\n"
      return # result
    return c.jsOutputComponents[key]
