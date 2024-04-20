# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

{.warning[ImplicitDefaultValue]:off.}
import std/[macros, macrocache, streams, lexbase,
  strutils, sequtils, re, tables, os, with]

import ./meta, ./tokens, ./ast, ./logging
import ./std

import pkg/kapsis/cli
import pkg/importer

type
  Parser* = object
    lvl: int # parser internals
    lex: Lexer
      # A pkg/toktok instance
    prev, curr, next: TokenTuple
      # Lexer internals
    engine: TimEngine
      # TimEngine instance
    tpl: TimTemplate
      # A `TimTemplate` instance that represents the
      # currently parsing template
    logger*: Logger
      ## Store warning and errors while parsing
    hasErrors*, nilNotError, hasLoadedView,
      isMain, refreshAst: bool
    parentNode: seq[Node]
      # Parser internals
    includes: Table[string, Meta]
      # A table to store all `@include` statements
    tree: Ast
      # The generated Abstract Syntax Tree

  PrefixFunction = proc(p: var Parser, excludes, includes: set[TokenKind] = {}): Node {.gcsafe.}
  InfixFunction = proc(p: var Parser, lhs: Node): Node {.gcsafe.}

const
  tkCompSet = {tkEQ, tkNE, tkGT, tkGTE, tkLT, tkLTE, tkAmp, tkAndAnd}
  tkMathSet = {tkPlus, tkMinus, tkAsterisk, tkDivide}
  tkAssignableSet = {
    tkString, tkBacktick, tkBool, tkFloat, tkIdentifier,
    tkInteger, tkIdentVar, tkIdentVarSafe, tkLC, tkLB
  }
  tkComparable = tkAssignableSet
  tkTypedLiterals = {
    tkLitArray, tkLitBool, tkLitFloat, tkLitFunction,
    tkLitInt, tkLitObject, tkLitString
  }

#
# Forward Declaration
#
proc getPrefixFn(p: var Parser, excludes,
    includes: set[TokenKind] = {}): PrefixFunction {.gcsafe.}

proc getInfixFn(p: var Parser, excludes,
    includes: set[TokenKind] = {}): InfixFunction {.gcsafe.}

proc parseInfix(p: var Parser, lhs: Node): Node {.gcsafe.}

proc getPrefixOrInfix(p: var Parser, includes,
    excludes: set[TokenKind] = {}, infix: Node = nil): Node {.gcsafe.}

proc parsePrefix(p: var Parser,
    excludes, includes: set[TokenKind] = {}): Node {.gcsafe.}

proc pAnoArray(p: var Parser, excludes,
    includes: set[TokenKind] = {}): Node {.gcsafe.}

proc pAnoObject(p: var Parser, excludes,
    includes: set[TokenKind] = {}): Node {.gcsafe.}

proc pAssignable(p: var Parser): Node {.gcsafe.}

proc parseBracketExpr(p: var Parser, lhs: Node): Node {.gcsafe.}

proc parseDotExpr(p: var Parser, lhs: Node): Node {.gcsafe.}

proc pFunctionCall(p: var Parser, excludes,
    includes: set[TokenKind] = {}): Node {.gcsafe.}

proc parseMathExp(p: var Parser, lhs: Node): Node {.gcsafe.}
proc parseCompExp(p: var Parser, lhs: Node): Node {.gcsafe.}
proc parseTernaryExpr(p: var Parser, lhs: Node): Node {.gcsafe.}

proc parseModule(engine: TimEngine, moduleName: string,
    code: SourceCode = SourceCode("")): Ast {.gcsafe.}

template caseNotNil(x: Node, body): untyped =
  if likely(x != nil):
    body
  else: return nil

template caseNotNil(x: Node, body, then): untyped =
  if likely(x != nil):
    body
  else: then

#
# Error API
#
proc hasError*(p: Parser): bool = p.hasErrors

#
# Parse Utils
#
proc isChild(tk, parent: TokenTuple): bool {.inline.} =
  tk.pos > parent.pos and (tk.line > parent.line and tk.kind != tkEOF)

proc isInfix(p: var Parser): bool {.inline.} =
  p.curr.kind in tkCompSet + tkMathSet 

proc isInfix(tk: TokenTuple): bool {.inline.} =
  tk.kind in tkCompSet + tkMathSet 

proc `isnot`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind != kind

proc `is`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind == kind

proc `in`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind in kind

proc `notin`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind notin kind

proc isFnCall(p: var Parser): bool {.inline.} =
  p.curr is tkIdentifier and p.next is tkLP and p.next.wsno == 0

template isRange: untyped =
  (
    (p.curr is tkDot and p.next is tkDot) and
      (p.curr.line == tk.line and p.next.line == tk.line)
  )

template expectWalk(kind: TokenKind) =
  if likely(p.curr is kind):
    walk p
  else: return nil

template expect(kind: TokenKind, body) =
  if likely(p.curr is kind):
    body
  else: return nil

template expect(kind: set[TokenKInd], body) =
  if likely(p.curr in kind):
    body
  else: return nil

proc isIdent(tk: TokenTuple, anyIdent, anyStringKey = false): bool =
  result = tk is tkIdentifier
  if result or (anyIdent and tk.kind != tkString):
    return tk.value.validIdentifier
  if result or anyStringKey:
    return tk.value.validIdentifier

proc skipNextComment(p: var Parser) =
  while true:
    case p.next.kind
    of tkComment:
      p.next = p.lex.getToken() # skip inline comments
    else: break

proc walk(p: var Parser, offset = 1) {.gcsafe.} =
  var i = 0
  while offset > i:
    inc i
    p.prev = p.curr
    p.curr = p.next
    p.next = p.lex.getToken()
    p.skipNextComment()

proc skipComments(p: var Parser) =
  while p.curr is tkComment:
    walk p

macro prefixHandle(name: untyped, body: untyped) =
  # Create a new prefix procedure with `name` and `body`
  name.newProc(
    [
      ident("Node"), # return type
      nnkIdentDefs.newTree(
        ident("p"),
        nnkVarTy.newTree(ident("Parser")),
        newEmptyNode()
      ),
      nnkIdentDefs.newTree(
        ident("excludes"),
        ident("includes"),
        nnkBracketExpr.newTree(ident("set"), ident("TokenKind")),
        newNimNode(nnkCurly)
      ),
    ],
    body,
    pragmas = nnkPragma.newTree(ident("gcsafe"))
  )

proc includePartial(p: var Parser, node: Node, s: string) =
  # node.meta = [p.curr.line, p.curr.pos, p.curr.col]
  add node.includes, "/" & s & ".timl"
  p.includes[p.engine.getPath(s & ".timl", ttPartial)] = node.meta

proc getStorageType(p: var Parser): StorageType =
  if p.curr.value in ["this", "app"]:
    p.tpl.jitEnable()
    if p.curr.value == "this":
      return localStorage
    result = globalStorage

proc getType(p: var Parser): NodeType =
  result =
    case p.curr.kind:
    of tkLitString: ntLitString
    of tkLitInt: ntLitInt
    of tkLitFloat: ntLitFloat
    of tkLitBool: ntLitBool
    of tkLitArray: ntLitArray
    of tkLitObject: ntLitObject
    of tkLitFunction: ntFunction
    of tkIdentifier:
      ntHtmlElement
    else: ntUnknown

#
# Parse Handlers
#
prefixHandle pString:
  # parse a single/double quote string
  result = ast.newString(p.curr)
  walk p

prefixHandle pStringConcat:
  walk p # tkAmp
  result = p.getPrefixOrInfix()

prefixHandle pBacktick:
  # parse template literals enclosed by backticks
  # todo
  result = ast.newString(p.curr)
  walk p

prefixHandle pInt:
  # parse an interger
  let v =
    try:
      parseInt(p.curr.value)
    except ValueError:
      return nil
  result = ast.newInteger(v, p.curr)
  walk p

prefixHandle pFloat:
  # parse a float number
  let v =
    try:
      parseFloat(p.curr.value)
    except ValueError:
      return nil
  result = ast.newFloat(v, p.curr)
  walk p

prefixHandle pBool:
  # parse bool literal
  let v =
    try:
      parseBool(p.curr.value)
    except ValueError:
      return nil
  result = ast.newBool(v, p.curr)
  walk p

proc parseVarDef(p: var Parser, ident: TokenTuple, varType: TokenKind): Node {.gcsafe.} =
  # parse a new variable definition
  result = ast.newNode(ntVariableDef, ident)
  result.varName = ident.value
  result.varImmutable = varType == tkConst

proc parseDotExpr(p: var Parser, lhs: Node): Node {.gcsafe.} =
  # parse dot expression
  result = ast.newNode(ntDotExpr, p.prev)
  result.lhs = lhs
  walk p # tkDot
  if p.isFnCall():
    let fnCallNode = p.pFunctionCall()
    caseNotNil fnCallNode:
      result.rhs = fnCallNode
  elif p.curr is tkIdentifier:
    result.rhs = ast.newIdent(p.curr)
    walk p
  else: return nil
  while true:
    case p.curr.kind
    of tkDot:
      if p.curr.line == result.meta[0]:
        result = p.parseDotExpr(result)
      else: break
    of tkLB:
      if p.curr.line == result.meta[0]:
        result = p.parseBracketExpr(result)
      else: break
    else:
      break # todo handle infix expressions

proc parseBracketExpr(p: var Parser, lhs: Node): Node {.gcsafe.} =
  # parse bracket expression
  let tk = p.curr; walk p # tkLB
  let index = p.getPrefixOrInfix()
  result = ast.newNode(ntBracketExpr, p.curr)
  result.bracketLHS = lhs
  caseNotNil index:
    if p.curr is tkRB:
      walk p # tkRB
      result.bracketIndex = index
      while true:
        case p.curr.kind
        of tkDot:
          if p.curr.line == result.meta[0]:
            result = p.parseDotExpr(result)
          else: break
        of tkLB:
          if p.curr.line == result.meta[0]:
            result = p.parseBracketExpr(result)
          else: break
        else:
          break # todo handle infix expressions
    elif isRange:
      walk p, 2 # tkDOT * 2
      let lastIndex =
        if p.curr is tkCaret:
          walk p; true
        else: false
      expect {tkInteger, tkIdentVar}:
        let rhs = p.parsePrefix()
        caseNotnil rhs:
          let rangeNode = ast.newNode(ntIndexRange)
          rangeNode.rangeNodes = [index, rhs]
          rangeNode.rangeLastIndex = lastIndex
          result.bracketIndex = rangeNode
      expectWalk tkRB

prefixHandle pIdent:
  # parse an identifier
  result = ast.newIdent(p.curr)
  let storageType = p.getStorageType()
  walk p
  if p.curr.line == result.meta[0]:
    case p.curr.kind
    of tkDot:
      # handle dot expressions
      if unlikely(p.next is tkDot):
        return # result
      result = p.parseDotExpr(result)
      caseNotNil result:
        case result.nt
        of ntDotExpr:
          result.storageType = storageType
        of ntBracketExpr:
          result.bracketStorageType = storageType
        else: discard
    of tkLB:
      # handle bracket expressions
      result = p.parseBracketExpr(result)
      caseNotNil result:
        case result.nt
        of ntDotExpr:
          result.storageType = storageType
        of ntBracketExpr:
          result.bracketStorageType = storageType
        else: discard
      if p.curr is tkDot and p.curr.line == result.meta[0]:
        result = p.parseDotExpr(result)
    of tkTernary:
      result = p.parseTernaryExpr(result)
    else: discard

prefixHandle pIdentOrAssignment:
  let ident = p.curr
  if p.next is tkAssign:
    walk p, 2 # tkAssign
    let varValue = p.getPrefixOrInfix()
    caseNotNil varValue:
      return ast.newAssignment(ident, varValue)
  result = p.pIdent()
  if result.nt == ntIdent:
    result.identSafe = ident.kind == tkIdentVarSafe

prefixHandle pAssignment:
  # parse assignment
  let ident = p.next
  let varType = p.curr.kind
  walk p, 2
  expectWalk tkAssign
  result = 
    case p.curr.kind:
    of tkAssignableSet:
      var varDef = p.parseVarDef(ident, varType)
      caseNotNil varDef:
        let varValue = p.getPrefixOrInfix()
        caseNotNil varValue:
          varDef.varValue = varvalue
          varDef
    else: nil

prefixHandle pEchoCommand:
  # parse `echo` command
  let tk = p.curr
  walk p
  var varNode: Node
  case p.curr.kind
  of tkAssignableSet:
    if p.curr in {tkIdentVar, tkIdentVarSafe}:
      let safeEscape = p.curr is tkIdentVarSafe
      if p.next.isInfix:
        varNode = p.getPrefixOrInfix()
      else:
        varNode = p.pIdent()
        case varNode.nt 
        of ntIdent:
          varNode.identSafe = safeEscape
        of ntDotExpr:
          varNode.lhs.identSafe = safeEscape
        else: discard
        if p.curr.isInfix and p.curr.line == p.prev.line:
          # todo move line checker to `isInfix`
          varNode = p.parseInfix(varNode)
    else:
      varNode = p.getPrefixOrInfix()
    caseNotNil varNode:
      return ast.newCommand(cmdEcho, varNode, tk)
  else: errorWithArgs(unexpectedToken, p.curr, [p.curr.value])

prefixHandle pReturnCommand:
  # parse `return` command
  let tk = p.curr
  if p.next in tkAssignableSet:
    walk p
    let valNode = p.getPrefixOrInfix()
    return ast.newCommand(cmdReturn, valNode, tk)

prefixHandle pDiscardCommand:
  # parse a `discard` command
  let tk = p.curr; walk p
  let valNode = p.getPrefixOrInfix()
  result = ast.newCommand(cmdDiscard, valNode, tk)

prefixHandle pBreakCommand:
  # parse a `break` command
  result = ast.newCommand(cmdBreak, nil, p.curr)
  walk p

template anyAttrIdent: untyped =
  (
    (p.curr in {tkString, tkIdentifier, tkIf, tkFor,
      tkElif, tkElse, tkOr, tkIn} and p.next is tkAssign) or
    (p.curr is tkIdentifier and (p.curr.line == el.line or (p.curr.isChild(el) and p.next is tkAssign)))
  )

proc parseAttributes(p: var Parser,
    attrs: var HtmlAttributes, el: TokenTuple) {.gcsafe.} =
  # parse HTML element attributes
  while true:
    case p.curr.kind
    of tkEOF: break
    of tkDot:
      let attrKey = "class"
      if attrs.hasKey(attrKey):
        add attrs[attrKey], ast.newString(p.next)
      else:
        attrs[attrKey] = @[ast.newString(p.next)]
      walk p, 2
    of tkID:
      let attrKey = "id"
      walk p
      if not attrs.hasKey(attrKey):
        attrs[attrKey] = @[ast.newString(p.curr)]
        walk p
      else:
        errorWithArgs(duplicateAttribute, p.curr, ["id"])
    else:
      if anyAttrIdent():
        let attrKey = p.curr
        walk p
        if p.curr is tkAssign: walk p
        if not attrs.hasKey(attrKey.value):
          case p.curr.kind
          of tkString, tkInteger, tkFloat, tkBool:
            var attrValue = ast.newString(p.curr)
            attrs[attrKey.value] = @[attrValue]
            walk p
            if p.curr is tkAmp:
              while p.curr is tkAmp:
                attrValue = p.pStringConcat()
                if likely(attrValue != nil):
                  add attrs[attrKey.value][^1].sVals, attrValue
          of tkBacktick:
            let attrValue = ast.newString(p.curr)
            attrs[attrKey.value] = @[attrValue]
            walk p
          of tkLB:
            let v = p.pAnoArray()
            caseNotNil v:
              attrs[attrKey.value] = @[v]
            do: return
          of tkLC:
            let v = p.pAnoObject()
            caseNotNil v:
              attrs[attrKey.value] = @[v]
            do: return
          else:
            var x: Node
            if p.next is tkLP and p.next.wsno == 0:
              x = p.pFunctionCall()
            else:
              x = p.pIdent()
            caseNotNil x:
              attrs[attrKey.value] = @[x]
            do:
              discard
        else: errorWithArgs(duplicateAttribute, attrKey, [attrKey.value])
      else: break
      # errorWithArgs(invalidAttribute, p.prev, [p.prev.value])

prefixHandle pGroupExpr:
  walk p # tkLP
  result = p.getPrefixOrInfix(includes = tkAssignableSet)
  expectWalk tkRP

prefixHandle pElement:
  # parse HTML Element
  let this = p.curr
  let tag = htmlTag(this.value)
  result = ast.newHtmlElement(tag, this)
  walk p
  if result.meta[1] != 0:
    # set real indentation size
    result.meta[1] = p.lvl * 4
  if p.parentNode.len == 0:
    add p.parentNode, result
  else:
    if result.meta[0] > p.parentNode[^1].meta[0]:
      add p.parentNode, result
  # parse HTML attributes
  case p.curr.kind
  of tkDot, tkID:
    result.attrs = HtmlAttributes()
    p.parseAttributes(result.attrs, this)
  of tkIdentifier:
    result.attrs = HtmlAttributes()
    p.parseAttributes(result.attrs, this)
  of tkIdentVar, tkIdentVarSafe:
    let x = p.pIdent()
    caseNotNil x:
      case x.nt
      of ntConditionStmt:
        discard
      else:
        discard # todo
  of tkLP:
    discard # todo
    # let groupNode = p.pGroupExpr()
    # caseNotNil groupNode:
    #   add result.attr, groupNode
  else:
    if p.curr.line == this.line:
      result.attrs = HtmlAttributes()
      p.parseAttributes(result.attrs, this)

  case p.curr.kind
  of tkColon:
    walk p
    if likely(p.curr in tkAssignableSet):
      case tag
      of tagStyle:
        p.curr.value = multiReplace(p.curr.value, [
          (re"\s+", " "), 
          (re";(?=\s*})", ""),
        ])
        p.curr.value = p.curr.value.replacef(re"(\s+)(\/\*(.*?)\*\/)(\s+)", "$2")
        p.curr.value = p.curr.value.replacef(re"(,|:|;|\{|}|\*\/|>) ", "$1")
        p.curr.value = p.curr.value.replacef(re"(:| )0\.([0-9]+)(%|em|ex|px|in|cm|mm|pt|pc)", "${1}.${2}${3}")
        p.curr.value = p.curr.value.replacef(re"(:| )(\.?)0(%|em|ex|px|in|cm|mm|pt|pc)", "${1}0")
        p.curr.value = replacef(p.curr.value, re"(,|:|;|\{|}|\*\/|>) ", "$1")
        p.curr.value = p.curr.value.replacef(re" (,|;|\{|}|>)", "$1")
      else: discard
      if p.curr isnot tkIdentifier or p.isFnCall():
        let valNode = p.getPrefixOrInfix()
        caseNotNil valNode:
          add result.nodes, valNode
  of tkGT:
    # parse inline HTML tags
    var node: Node
    while p.curr is tkGT:
      inc p.lvl
      if likely(p.next is tkIdentifier):
        walk p
        p.curr.pos = p.lvl
        node = p.pElement()
        caseNotNil node:
          if p.curr.kind != tkEOF and p.curr.pos != 0:
            if p.curr.line > node.meta[0]:
              let currentParent = p.parentNode[^1]
              while p.curr.pos > currentParent.meta[2]:
                if p.curr.kind == tkEOF: break
                var subNode = p.parsePrefix()
                caseNotNil subNode:
                  add node.nodes, subNode
                # if p.hasError(): break
                if p.curr.pos < currentParent.meta[2]:
                  dec p.lvl, currentParent.meta[2] div p.curr.pos
                  delete(p.parentNode, p.parentNode.high)
                  break
          add result.nodes, node
          if p.lvl != 0:
            dec p.lvl
          return result
  else: discard
  # parse nested nodes
  let currentParent = p.parentNode[^1]
  if p.curr.pos > currentParent.meta[2]:
    inc p.lvl
  while p.curr.pos > currentParent.meta[2]:
    if p.curr is tkEOF: break
    var subNode = p.parsePrefix()
    caseNotNil subNode:
      add result.nodes, subNode
    if p.curr is tkEOF or p.curr.pos == 0: break # prevent division by zero
    if p.curr.pos < currentParent.meta[2]:
      dec p.lvl
      delete(p.parentNode, p.parentNode.high)
      break
    elif p.curr.pos == currentParent.meta[2]:
      dec p.lvl
  if p.curr.pos == 0: p.lvl = 0 # reset level

proc parseCondBranch(p: var Parser, tk: TokenTuple): ConditionBranch {.gcsafe.} =
  walk p # `if` or `elif` token
  result.expr = p.getPrefixOrInfix()
  if p.curr is tkColon: walk p # colon is optional
  caseNotNil result.expr:
    while p.curr.isChild(tk):
      let node = p.getPrefixOrInfix()
      caseNotNil node:
        add result.body, node
      do: return
    if unlikely(result.body.len == 0):
      error(badIndentation, p.curr)
  do: return

prefixHandle pCondition:
  # parse `if`, `elif`, `else` condition statements
  var this = p.curr
  var elseBody: seq[Node]
  let ifbranch = p.parseCondBranch(this)
  caseNotNil ifbranch.expr:
    result = ast.newCondition(ifbranch, this)
    while p.curr is tkElif:
      # parse `elif` branches
      let eliftk = p.curr
      let condBranch = p.parseCondBranch(eliftk)
      caseNotNil condBranch.expr:
        if unlikely(condBranch.body.len == 0):
          return nil
        add result.condElifBranch, condBranch
    if p.curr is tkElse:
      # parse `else` branch, if any
      let elsetk = p.curr
      if p.next is tkColon: walk p, 2
      while p.curr.isChild(elsetk):
        let node = p.getPrefixOrInfix()
        caseNotNil node:
          add result.condElseBranch, node
      if unlikely(result.condElseBranch.len == 0):
        return nil

proc parseStatement(p: var Parser, parent: (TokenTuple, Node),
    excludes, includes: set[TokenKind]): Node {.gcsafe.} =
  ## Parse a statement node
  result = ast.newNode(ntStmtList)
  while p.curr isnot tkEOF:
    let tk = p.curr
    let node = p.parsePrefix(excludes, includes)
    caseNotNil node:
      add result.stmtList, node

prefixHandle pCase:
  # parse a conditional `case` block
  let tk = p.curr
  result = ast.newNode(ntCaseStmt)
  walk p
  let caseExpr = p.getPrefixOrInfix()
  caseNotNil caseExpr:
    let firstof = p.curr
    expectWalk tkOF
    while p.curr is tkOF and (p.curr.isChild(tk) and p.curr.pos > firstof.pos):
      let currOfToken = p.curr
      walk p # tkOF
      let caseValue = p.getPrefixOrInfix()
      caseNotNil caseValue:
        expectWalk tkColon
        let caseBody = p.parseStatement((currOfToken, result), excludes, includes)
        caseNotNil caseBody:
          discard
        # add result.caseBranch, caseBody
        
    # parse `else` branch

prefixHandle pFor:
  # parse `for` statement
  let tk = p.curr
  walk p
  case p.curr.kind
  of tkIdentVar:
    result = ast.newNode(ntLoopStmt, tk)
    # result.loopItem = p.pIdentOrAssignment()
    result.loopItem = ast.newNode(ntVariableDef, p.curr)
    result.loopItem.varName = p.curr.value
    result.loopItem.varImmutable = true
    walk p
    if p.curr is tkComma and p.next in {tkIdentVar, tkIdentVarSafe}:
      walk p
      let pairNode = ast.newNode(ntIdentPair, p.curr)
      pairNode.identPairs[0] = result.loopItem
      var vNode: Node
      vNode = ast.newNode(ntVariableDef, p.curr)
      vNode.varName = p.curr.value
      vNode.varImmutable = true
      pairNode.identPairs[1] = vNode
      result.loopItem = pairNode
      walk p
    let inx = p.curr
    expectWalk tkIN
    if p.curr in {tkIdentVar, tkString, tkLB} or p.isFnCall:
    # expect {tkIdentVar, tkString, tkLB, tkInteger}: # todo function call
      let items = p.parsePrefix()
      caseNotNil items:
        result.loopItems = items
    elif p.curr is tkInteger and p.curr.line == inx.line:
      let min = p.curr; walk p
      if likely(isRange()):
        walk p, 2
        expect tkInteger:
          result.loopItems = ast.newNode(ntIndexRange)
          result.loopItems.rangeNodes = [
            ast.newInteger(min.value.parseInt, min),
            ast.newInteger(p.curr.value.parseInt, p.curr)
          ]
          walk p
    if p.curr is tkColon: walk p
    while p.curr.isChild(tk):
      let node = p.getPrefixOrInfix()
      caseNotNil node:
        add result.loopBody, node
    if unlikely(result.loopBody.len == 0):
      error(badIndentation, p.curr)
  else: discard

prefixHandle pAnoObject:
  # parse an anonymous object
  result = ast.newNode(ntLitObject, p.curr)
  result.objectItems = newOrderedTable[string, Node]()
  walk p # tkLC
  while p.curr isnot tkRC and not p.hasErrors:
    if p.curr is tkEOF:
      errorWithArgs(eof, p.curr, [$tkRC])
    if p.curr.isIdent(anyIdent = true, anyStringKey = true) and
        p.next is tkColon:
      let k = p.curr
      walk p, 2 # key and colon
      if likely(not result.objectItems.hasKey(k.value)):
        var v: Node
        case p.curr.kind
        of tkLB:
          v = p.pAnoArray()
        of tkLC:
          v = p.pAnoObject()
        else:
          v = p.getPrefixOrInfix(includes = tkAssignableSet)
        caseNotNil v:
          result.objectItems[k.value] = v
          if p.curr is tkComma:
            walk p
          elif p.curr isnot tkRC:
            if p.curr.line == v.meta[0]:
              result = nil
              error(badIndentation, p.curr)
        do:
          result = nil
          break
      else: errorWithArgs(duplicateField, k, [k.value])
    else: return nil
  walk p # tkRC

prefixHandle pAnoArray:
  # parse an anonymous array
  let tk = p.curr
  walk p # [
  var items: seq[Node]
  while p.curr.kind != tkRB and not p.hasErrors:
    var item = p.pAssignable()
    caseNotNil item:
      add items, item
    do:
      if p.curr is tkLB:
        item = p.pAnoArray()
        caseNotNil item:
          add items, item
      elif p.curr is tkLC:
        item = p.pAnoObject()
        caseNotNil item:
          add items, item
      else: return nil # todo error
    if p.curr is tkComma:
      walk p
    else:
      if p.curr isnot tkRB and p.curr.line == item.meta[0]:
        error(badIndentation, p.curr)
  expectWalk tkRB
  result = ast.newNode(ntLitArray, tk)
  result.arrayItems = items

proc pAssignable(p: var Parser): Node {.gcsafe.} =
  case p.curr.kind
  of tkLB: p.pAnoArray()
  of tkLC: p.pAnoObject()
  else: p.getPrefixOrInfix()

prefixHandle pViewLoader:
  # parse `@view` magic call
  if p.tpl.getType != ttLayout:
    error(invalidViewLoader, p.curr)
  elif p.hasLoadedView:
    error(duplicateViewLoader, p.curr)
  result = ast.newNode(ntViewLoader, p.curr)
  p.tpl.setViewIndent(uint(result.meta[1]))
  p.hasLoadedView = true
  walk p

prefixHandle pInclude:
  # parse `@include` magic call.
  # TimEngine parse included files in separate threads
  # using pkg/importer
  if likely p.next is tkString:
    let tk = p.curr
    walk p
    result = ast.newNode(ntInclude, tk)
    # I guess this will fix indentation
    # inside partials (when not minified)
    result.meta[1] = p.lvl * 4
    result.meta[2] = (p.lvl * 4) + 1
    p.includePartial(result, p.curr.value)
    walk p
    while p.curr is tkComma:
      walk p
      if likely p.curr is tkString:
        p.includePartial(result, p.curr.value)
        walk p
      else: return nil

prefixHandle pImport:
  # parse `@import`
  {.gcsafe.}:
    if likely p.next is tkString:
      let tk = p.curr
      walk p
      result = ast.newNode(ntImport, tk)
      add result.modules, p.curr.value
      p.tree.modules[p.curr.value] =
        p.engine.parseModule(p.curr.value, std(p.curr.value)[1])
      p.tree.modules[p.curr.value].src = p.curr.value
      walk p

prefixHandle pSnippet:
  case p.curr.kind
  of tkSnippetJS:
    result = ast.newNode(ntJavaScriptSnippet, p.curr)
    result.snippetCode = p.curr.value
  of tkSnippetYaml:
    result = ast.newNode(ntYamlSnippet, p.curr)
    result.snippetCode = p.curr.value
  of tkSnippetJSON:
    result = ast.newNode(ntJsonSnippet, p.curr)
    result.snippetCode = p.curr.value    
  else: discard
  walk p

prefixHandle pClientSide:
  # parse tim template inside a `@client` block
  # statement in order to be transpiled to JavaScript
  # via engine/compilers/JSCompiler.nim
  let tk = p.curr; walk p # tkCLient
  expect tkIdentifier:
    if unlikely(p.curr.value != "target"):
      return nil
    walk p
    result = ast.newNode(ntClientBlock, tk)
    expectWalk tkAssign
    expect tkString:
      result.clientTargetElement = p.curr.value
      walk p
      while p.curr isnot tkEnd and p.curr.isChild(tk):
        let n: Node = p.getPrefixOrInfix()
        caseNotNil n:
          add result.clientStmt, n
      expectWalk tkEnd

prefixHandle pPlaceholder:
  # parse a placeholder
  let tk = p.curr; walk p
  expectWalk tkID
  expect tkIdentifier:
    result = ast.newNode(ntPlaceholder)
    result.placeholderName = p.curr.value; walk p

template handleImplicitDefaultValue {.dirty.} =
  # handle implicit default value
  walk p
  let implNode = p.getPrefixOrInfix(includes = tkAssignableSet)
  caseNotNil implNode:
    result.fnParams[pName.value].pImplVal = implNode

prefixHandle pFunction:
  # parse a function declaration
  let this = p.curr; walk p # tkFN
  expect tkIdentifier: # function identifier
    result = ast.newFunction(this, p.curr.value)
    walk p
    if p.curr is tkAsterisk:
      result.fnExport = true
      walk p
    expectWalk tkLP
    while p.curr isnot tkRP:
      case p.curr.kind
      of tkIdentifier:
        let pName = p.curr
        walk p
        if p.curr is tkColon:
          if likely(result.fnParams.hasKey(pName.value) == false):
            walk p # tkColon
            case p.curr.kind
            of tkTypedLiterals:
              let pType = p.getType
              result.fnParams[pName.value] =
                (pName.value, pType, nil, [p.curr.line, p.curr.pos, p.curr.col]) # todo parse implicit value
              walk p
              if p.curr is tkAssign:
                handleImplicitDefaultValue()
            else: break
        elif p.curr is tkAssign:
          result.fnParams[pName.value] =
            (pName.value, ntLitVoid, nil, [0, 0, 0])
          handleImplicitDefaultValue()
          result.fnParams[pName.value].meta = implNode.meta
        if p.curr is tkComma and p.next isnot tkRP:
          walk p
        elif p.curr isnot tkRP:
          return nil
      else: return nil
    walk p # tkRP
    if p.curr is tkColon:
      walk p
      case p.curr.kind
      of tkIdentifier:
        if p.curr.value == "Html":
          walk p; expectWalk(tkLB)
          result.fnReturnType = p.getType
          result.fnReturnHtmlElement = htmlTag(p.curr.value)
          walk p; expectWalk(tkRB)
        else: discard # todo error
      of tkLitVoid:
        result.fnReturnType = ntLitVoid
        walk p
      else:
        expect tkTypedLiterals:
          # set a return type
          result.fnReturnType = p.getType
          walk p
    if p.curr is tkAssign:
      # begin function body
      walk p
      while p.curr.isChild(this):
        # todo disallow use of html inside a function
        # todo cleanup parser code and make use of includes/excludes
        let node = p.getPrefixOrInfix()
        caseNotNil node:
          add result.fnBody, node
      if unlikely(result.fnBody.len == 0):
        error(badIndentation, p.curr)
    else:
      if p.tree.src == "*":
        result.fnType = FunctionType.fnImportModule
      elif p.tree.src.startsWith("std"):
        result.fnType = FunctionType.fnImportSystem
      result.fnSource = p.tree.src
      result.fnFwdDecl = true

prefixHandle pFunctionCall:
  # parse a function call
  result = ast.newCall(p.curr)
  walk p, 2 # we know tkLP is next so we'll skip it
  while p.curr isnot tkRP:
    let argNode = p.getPrefixOrInfix(includes = tkAssignableSet)
    if p.curr is tkComma and p.next in tkAssignableSet:
      walk p
    elif p.curr isnot tkRP:
      return nil
    caseNotNil argNode:
      add result.identArgs, argNode
  walk p # tkRP

#
# Infix Main Handlers
#
proc parseCompExp(p: var Parser, lhs: Node): Node {.gcsafe.} =
  # parse logical expressions with symbols (==, !=, >, >=, <, <=)
  let op = getInfixOp(p.curr.kind, false)
  walk p
  let rhstk = p.curr
  let rhs = p.parsePrefix(includes = tkComparable)
  caseNotNil rhs:
    result = ast.newNode(ntInfixExpr, rhstk)
    result.infixLeft = lhs
    result.infixOp = op
    if p.curr.kind in tkMathSet:
      result.infixRight = p.parseMathExp(rhs)
    else:
      result.infixRight = rhs
    case p.curr.kind
    of tkOr, tkOrOr, tkAnd, tkAndAnd, tkAmp:
      let infixNode = ast.newNode(ntInfixExpr, p.curr)
      infixNode.infixLeft = result
      infixNode.infixOp = getInfixOp(p.curr.kind, true)
      walk p
      let rhs = p.getPrefixOrInfix()
      caseNotNil rhs:
        infixNode.infixRight = rhs
        return infixNode
    of tkTernary:
      discard p.parseTernaryExpr(result)
    else: discard

proc parseTernaryExpr(p: var Parser, lhs: Node): Node {.gcsafe.} =
  # parse an one line conditional using ternary operator
  discard

proc parseMathExp(p: var Parser, lhs: Node): Node {.gcsafe.} =
  # parse math expressions with symbols (+, -, *, /)
  let infixOp = getInfixMathOp(p.curr.kind, false)
  walk p
  let rhstk = p.curr
  let rhs = p.parsePrefix(includes = tkComparable)
  caseNotNil rhs:
    result = ast.newNode(ntMathInfixExpr, rhstk)
    result.infixMathOp = infixOp
    result.infixMathLeft = lhs
    case p.curr.kind
    of tkAsterisk, tkDivide:
      result.infixMathRight = p.parseMathExp(rhs)
    of tkPlus, tkMinus:
      result.infixMathRight = rhs
      result = p.parseMathExp(result)
    else:
      result.infixMathRight = rhs

proc getInfixFn(p: var Parser, excludes, includes: set[TokenKind] = {}): InfixFunction {.gcsafe.} =
  case p.curr.kind
  of tkCompSet: parseCompExp
  of tkMathSet: parseMathExp
  else: nil

proc parseInfix(p: var Parser, lhs: Node): Node {.gcsafe.} =
  var infixNode: Node # ntInfix
  let infixFn = p.getInfixFn()
  if likely(infixFn != nil):
    result = p.infixFn(lhs)
  if p.curr in tkCompSet:
    result = p.parseCompExp(result)

#
# Prefix Main Handlers
#
proc getPrefixFn(p: var Parser, excludes, includes: set[TokenKind] = {}): PrefixFunction {.gcsafe.} =
  if excludes.len > 0:
    if p.curr in excludes:
      errorWithArgs(invalidContext, p.curr, [p.curr.value])
  if includes.len > 0:
    if p.curr notin includes:
      errorWithArgs(invalidContext, p.curr, [p.curr.value])
  result =
    case p.curr.kind
    of tkVar, tkConst: pAssignment
    of tkString: pString
    of tkBacktick: pBacktick
    of tkInteger: pInt
    of tkFloat: pFloat
    of tkBool: pBool
    of tkIF: pCondition
    of tkCase: pCase
    of tkFor: pFor
    of tkIdentifier:
      if p.next is tkLP and p.next.wsno == 0:
        pFunctionCall # function call by ident
      else:
        pElement # parse HTML element
    of tkIdentVar, tkIdentVarSafe: pIdentOrAssignment
    of tkViewLoader: pViewLoader
    of tkSnippetJS, tkSnippetJSON, tkSnippetYaml: pSnippet
    of tkInclude: pInclude
    of tkImport: pImport
    of tkClient: pClientSide
    of tkLB: pAnoArray
    of tkLC: pAnoObject
    of tkFN, tkFunc: pFunction
    of tkEchoCmd: pEchoCommand
    of tkDiscardCmd: pDiscardCommand
    of tkBreakCmd: pBreakCommand
    of tkReturnCmd: pReturnCommand
    of tkPlaceholder: pPlaceholder
    else: nil

proc parsePrefix(p: var Parser, excludes,
    includes: set[TokenKind] = {}): Node {.gcsafe.} =
  let prefixFn = p.getPrefixFn(excludes, includes)
  if likely(prefixFn != nil):
    return p.prefixFn(excludes, includes)
  result = nil

proc getPrefixOrInfix(p: var Parser, includes,
    excludes: set[TokenKind] = {}, infix: Node = nil): Node {.gcsafe.} =
  let lhs = p.parsePrefix(excludes, includes)
  var infixNode: Node
  if p.curr.isInfix:
    caseNotNil lhs:
      infixNode = p.parseInfix(lhs)
      caseNotNil infixNode:
        return infixNode
  result = lhs

proc parseRoot(p: var Parser, excludes, includes: set[TokenKind] = {}): Node {.gcsafe.} =
  # Parse elements declared at root-level
  result =
    case p.curr.kind
    of tkVar,tkConst: p.pAssignment()
    of tkIdentVar, tkIdentVarSafe:
      if p.next is tkAssign:
        p.pIdentOrAssignment()
      elif p.next is tkDot:
        p.pIdent()
      else: nil
    of tkIF:          p.pCondition()
    of tkCase:        p.pCase()
    of tkFor:         p.pFor()
    of tkViewLoader:  p.pViewLoader()
    of tkIdentifier:
      if p.next is tkLP and p.next.wsno == 0:
        p.pFunctionCall()
      else:
        p.pElement()
    of tkSnippetJS:   p.pSnippet()
    of tkInclude:     p.pInclude()
    of tkImport:      p.pImport()
    of tkLB:          p.pAnoArray()
    of tkLC:          p.pAnoObject()
    of tkFN, tkFunc:  p.pFunction()
    of tkClient:      p.pClientSide()
    of tkEchoCmd:     p.pEchoCommand()
    of tkDiscardCmd:  p.pDiscardCommand()
    of tkPlaceholder: p.pPlaceholder()
    else: nil
  if unlikely(result == nil):
    let tk = if p.curr isnot tkEOF: p.curr else: p.prev
    errorWithArgs(unexpectedToken, tk, [tk.value])

# fwd
proc newParser*(engine: TimEngine, tpl: TimTemplate,
    isMainParser = true, refreshAst = false): Parser {.gcsafe.}
proc getAst*(p: Parser): Ast {.gcsafe.}

let partials = TimPartialsTable()
var jitMainParser: bool # force main parser enable JIT

proc parseHandle[T](i: Import[T], importFile: ImportFile,
    ticket: ptr TicketLock): seq[string] {.gcsafe, nimcall.} =
  # invoke other instances of `Parser` for parsing included partials
  withLock ticket[]:
    let fpath = importFile.getImportPath
    let path = fpath.replace(i.handle.engine.getSourcePath() / $(ttPartial) / "", "")
    var tpl: TimTemplate = i.handle.engine.getTemplateByPath(fpath)
    if likely(partials.hasKey(path) == false or i.handle.refreshAst):
      var cp: Parser = i.handle.engine.newParser(tpl, false)
      if likely(not cp.hasErrors):
        if cp.tpl.jitEnabled():
          jitMainParser = true
        when defined napiOrWasm:
          partials[path] = (cp.getAst(), @[])
        else:
          partials[path] = (cp.getAst(), cp.logger.errors.toSeq)
        result = cp.includes.keys.toSeq
        if not tpl.hasDep(i.handle.tpl.getSourcePath()):
          tpl.addDep(i.handle.tpl.getSourcePath())
      else:
        # this is weird, gotta do something different here
        i.handle.logger.errorLogs = i.handle.logger.errorLogs.concat(cp.logger.errorLogs)
        i.handle.hasErrors = true
        i.cancel()
    else:
      if not tpl.hasDep(i.handle.tpl.getSourcePath()):
        tpl.addDep(i.handle.tpl.getSourcePath())

template startParse(path: string): untyped =
  with p.handle:
    curr = p.handle.lex.getToken()
    next = p.handle.lex.getToken()
    logger = Logger(filePath: path)
  p.handle.skipComments() # if any
  while p.handle.curr isnot tkEOF:
    if unlikely(p.handle.lex.hasError):
      p.handle.logger.newError(internalError, p.handle.curr.line,
        p.handle.curr.col, false, p.handle.lex.getError)
    if unlikely(p.handle.hasErrors):
      # reset(p.handle.tree) # reset incomplete tree
      break
    let node = p.handle.parseRoot()
    caseNotNil node:
      add p.handle.tree.nodes, node
    do: discard
  lexbase.close(p.handle.lex)
  if isMainParser:
    if p.handle.includes.len > 0 and not p.handle.hasErrors:
      # continue parse other partials
      p.imports(p.handle.includes.keys.toSeq, parseHandle[Parser])

template collectImporterErrors =
  for err in p.importErrors:
    var emsg: logging.Message
    case err.reason
    of ImportErrorMessage.importNotFound:
      emsg = Message.importNotFound
    of ImportErrorMessage.importCircularError:
      emsg = Message.importCircularError
    else: discard
    let meta: Meta = p.handle.includes[err.fpath]
    p.handle.logger.newError(emsg, meta[0],
      meta[2], true, [err.fpath.replace(engine.getSourcePath(), "")])
    p.handle.hasErrors = true

proc parseModule(engine: TimEngine, moduleName: string,
    code: SourceCode = SourceCode("")): Ast {.gcsafe.} =
  {.gcsafe.}:
    var p = Parser(
      tree: Ast(src: moduleName),
      engine: engine,
      lex: newLexer(code.string, allowMultilineStrings = true),
      logger: Logger(filePath: "")
    )  
    p.curr = p.lex.getToken()
    p.next = p.lex.getToken()
    # p.skipComments() # if any
    while p.curr isnot tkEOF:
      if unlikely(p.lex.hasError):
        p.logger.newError(internalError, p.curr.line,
          p.curr.col, false, p.lex.getError)
      if unlikely(p.hasErrors):
        echo p.logger.errors.toSeq
        echo moduleName
        break
      let node = p.parseRoot()
      if node != nil:
        add p.tree.nodes, node
    p.lex.close()
    result = p.tree

proc initSystemModule(p: var Parser) =
  ## Make `std/system` available by default
  {.gcsafe.}:
    let x= "std/system"
    var sysNode = ast.newNode(ntImport)
    sysNode.modules.add(x)
    p.tree.nodes.add(sysNode)
    p.tree.modules = TimModulesTable()
    p.tree.modules[x] =
      p.engine.parseModule(x, std(x)[1])

  # var L = initTicketLock()
  # parseHandle[Parser](sysid, dirPath(p.tpl.sources), addr(p.imports),
  #           addr L, true, std(sysid)[1])

#
# Public API
#
proc newParser*(engine: TimEngine, tpl: TimTemplate,
    isMainParser = true, refreshAst = false): Parser {.gcsafe.} =
  ## Parse `tpl` TimTemplate
  var p = newImport[Parser](
    tpl.sources.src,
    engine.getSourcePath() / $(ttPartial),
    baseIsMain = true
  )
  with p.handle:
    tree = Ast()
    lex = newLexer(readFile(tpl.sources.src), allowMultilineStrings = true)
    engine = engine
    tpl = tpl
    isMain = isMainParser
    refreshAst = refreshAst
  initModuleSystem()
  p.handle.initSystemModule()
  startParse(tpl.sources.src)
  if isMainParser:
    {.gcsafe.}:
      if partials.len > 0:
        p.handle.tree.partials = partials
      if jitMainParser:
        p.handle.tpl.jitEnable
  collectImporterErrors()
  result = p.handle

proc parseSnippet*(id, code: string): Parser {.gcsafe.} =
  ## Parse static snippet `code` at runtime before
  ## calling the `precompile` handle
  var p = Parser(
    tree: Ast(),
    lex: newLexer(code, allowMultilineStrings = true),
    logger: Logger(filePath: id)
  )
  p.curr = p.lex.getToken()
  p.next = p.lex.getToken()
  # p.skipComments() # if any
  while p.curr isnot tkEOF:
    if unlikely(p.lex.hasError):
      p.logger.newError(internalError, p.curr.line,
        p.curr.col, false, p.lex.getError)
    if unlikely(p.hasErrors):
      reset(p.tree) # reset incomplete tree
      break
    let node = p.parseRoot()
    caseNotNil node:
      add p.tree.nodes, node
    do: discard
  lexbase.close(p.lex)
  result = p

proc parseSnippet*(snippetPath: string): Parser {.gcsafe.} =
  ## Parse a snippet code from a `snippetPath` file.
  var p = Parser(
    tree: Ast(),
    lex: newLexer(readFile(snippetPath), allowMultilineStrings = true),
    logger: Logger(filePath: snippetPath)
  )
  p.curr = p.lex.getToken()
  p.next = p.lex.getToken()
  # p.skipComments() # if any
  while p.curr isnot tkEOF:
    if unlikely(p.lex.hasError):
      p.logger.newError(internalError, p.curr.line,
        p.curr.col, false, p.lex.getError)
    if unlikely(p.hasErrors):
      reset(p.tree) # reset incomplete tree
      break
    let node = p.parseRoot()
    caseNotNil node:
      add p.tree.nodes, node
    do: discard
  lexbase.close(p.lex)
  result = p

proc getAst*(p: Parser): Ast {.gcsafe.} =
  ## Returns the constructed AST
  result = p.tree