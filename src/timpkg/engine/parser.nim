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
import pkg/importer/resolver

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
    tkLitInt, tkLitObject, tkLitString, tkBlock, tkLitStream
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
proc parseTernaryExpr(p: var Parser, infixExpr: Node): Node {.gcsafe.}

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
  p.curr.kind in tkCompSet + tkMathSet + {tkAssign}

proc isInfix(tk: TokenTuple): bool {.inline.} =
  tk.kind in tkCompSet + tkMathSet + {tkAssign}

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
  if anyStringKey:
    return tk.value[0] in IdentChars
  if result or (anyIdent and tk.kind != tkString):
    result = tk.value.validIdentifier

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
        ident"p",
        nnkVarTy.newTree(
          ident"Parser"
        ),
        newEmptyNode()
      ),
      nnkIdentDefs.newTree(
        ident"excludes",
        ident"includes",
        nnkBracketExpr.newTree(
          ident"set",
          ident"TokenKind"
        ),
        newNimNode(nnkCurly)
      ),
    ],
    body,
    pragmas = nnkPragma.newTree(ident("gcsafe"))
  )

proc includePartial(p: var Parser, node: Node, s: string) =
  # node.meta = [p.curr.line, p.curr.pos, p.curr.col]
  add node.includes, "/" & s & ".timl"
  let partialPath = p.engine.getPath(s & ".timl", ttPartial)
  p.includes[p.engine.getPath(s & ".timl", ttPartial)] = node.meta
  p.engine.importsHandle.incl(p.tree.src, partialPath, [node.meta[0], node.meta[2]])

proc getStorageType(p: var Parser): StorageType =
  if p.curr.value in ["this", "app"]:
    p.tpl.jitEnable()
    if p.curr.value == "this":
      return localStorage
    result = globalStorage

proc getType(kind: TokenKind): NodeType =
  result =
    case kind:
    of tkLitString: ntLitString
    of tkLitInt: ntLitInt
    of tkLitFloat: ntLitFloat
    of tkLitBool: ntLitBool
    of tkLitArray: ntLitArray
    of tkLitObject: ntLitObject
    of tkLitFunction: ntFunction
    of tkLitStream: ntStream
    of tkBlock: ntBlock
    of tkIdentifier:
      ntHtmlElement
    else: ntUnknown

proc getDataType(p: var Parser): DataType =
  result =
    case p.curr.kind:
    of tkLitString: typeString
    of tkLitInt: typeInt
    of tkLitFloat: typeFloat
    of tkLitBool: typeBool
    of tkLitArray: typeArray
    of tkLitObject: typeObject
    of tkLitFunction: typeFunction
    of tkLitStream: typeStream
    of tkBlock: typeBlock
    of tkIdentifier:
      typeHtmlElement
    else: typeNil

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

proc parseStatement(p: var Parser, parent: TokenTuple,
    excludes, includes: set[TokenKind] = {},
    defaultBodyMarker = tkColon): Node {.gcsafe.} =
  ## Parse a statement node
  var isIndentBlock: bool
  if p.curr is defaultBodyMarker:
    isIndentBlock = true
    walk p
  elif p.curr is tkLC:
    isIndentBlock = false
    walk p
  else: return nil
  result = ast.newNode(ntStmtList)
  if isIndentBlock:
    while p.curr isnot tkEOF and p.curr.isChild(parent):
      let tk = p.curr
      let node = p.parsePrefix(excludes, includes)
      caseNotNil node:
        add result.stmtList, node
      do:
        return nil
  else:
    while p.curr notin {tkEOF, tkRC}:
      let tk = p.curr
      let node = p.parsePrefix(excludes, includes)
      caseNotNil node:
        add result.stmtList, node
      do:
        return nil
  if unlikely(result.stmtlist.len > 0 == false):
    return nil # empty stmtlist
  if unlikely(not isIndentBlock):
    expectWalk(tkRC)

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
    else: break

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
      expect {tkInteger, tkIdentVar, tkIdentifier}:
        if p.curr is tkIdentifier:
          if p.isFnCall(): discard
          else: return nil
        let rhs = p.parsePrefix()
        caseNotnil rhs:
          let rangeNode = ast.newNode(ntIndexRange)
          rangeNode.rangeNodes = [index, rhs]
          rangeNode.rangeLastIndex = lastIndex
          result.bracketIndex = rangeNode
      expectWalk tkRB

prefixHandle pHtmlAttribute:
  # parse a pair of `key = value` html attribute
  result = ast.newNode(ntHtmlAttribute)
  result.attrName = p.curr.value
  result.meta = p.curr.trace
  walk p
  expectWalk tkAssign
  result.attrValue = p.getPrefixOrInfix()

prefixHandle pIdent:
  # parse an identifier
  var isEscaped = p.curr is tkIdentVarSafe
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
        if p.curr.isInfix:
          result = p.parseInfix(result)
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
      caseNotNil result:
        if p.curr.isInfix:
          result = p.parseInfix(result)
    else: 
      if p.curr.isInfix and p.next in tkAssignableSet - {tkIdentifier}:
        # excluding tkIdentifier to avoid
        # `h1 x=$x > span: ""` conflicts
        result = p.parseInfix(result)
  if isEscaped:
    var safeVarNode = ast.newNode(ntEscape)
    safeVarNode.escapeIdent = result
    return safeVarNode

prefixHandle pIdentOrAssignment:
  let ident = p.curr
  if p.next is tkAssign:
    walk p, 2 # tkAssign
    let varValue = p.getPrefixOrInfix()
    caseNotNil varValue:
      return ast.newAssignment(ident, varValue)
  result = p.pIdent()
  # if result.nt == ntIdent:
  #   result.identSafe = ident.kind == tkIdentVarSafe

template getAssignedValue: Node {.dirty.} = 
  case p.curr.kind:
  of tkAssignableSet:
    var varDef = p.parseVarDef(identToken, varType)
    caseNotNil varDef:
      let varValue = p.getPrefixOrInfix()
      caseNotNil varValue:
        varDef.varValue = varvalue
        varDef
  else: nil

prefixHandle pAssignment:
  # parse assignment
  let identToken = p.next
  let varType = p.curr.kind
  walk p, 2
  case p.curr.kind
  of tkAssign:
    walk p # tkAssing
    result = getAssignedValue()
  of tkColon:
    walk p # tkColon
    case p.curr.kind
    of tkTypedLiterals:
      let varValueType = p.getDataType
      walk p
      if p.curr is tkAssign:
        walk p
        return getAssignedValue()
      result = p.parseVarDef(identToken, varType)
      result.varValueType = varValueType
      if result.varValue == nil:
        result.varValue = ast.getDefaultValue(result.varValueType)
    else: discard # `unexpectedToken`
  else: discard # `unexpectedToken`


prefixHandle pEchoCommand:
  # parse `echo` command
  let tk = p.curr
  walk p
  var varNode: Node
  var isEscaped: bool
  case p.curr.kind
  of tkAssignableSet:
    if p.curr in {tkIdentVar, tkIdentVarSafe}:
      isEscaped = p.curr is tkIdentVarSafe
      if p.next.isInfix:
        varNode = p.getPrefixOrInfix()
      else:
        varNode = p.pIdent()
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
    result = ast.newCommand(cmdReturn, valNode, tk)

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
    (
      (p.curr is tkIdentifier and p.curr.value[0] in IdentChars) and
      (p.curr.line == el.line or (p.curr.isChild(el) and p.next is tkAssign))
    )
  )

prefixHandle pGroupExpr:
  # parse a group expression
  walk p # tkLP
  result = ast.newNode(ntParGroupExpr)
  result.meta = p.prev.trace
  result.groupExpr = p.getPrefixOrInfix(includes = tkAssignableSet)
  caseNotNil result.groupExpr:
    expectWalk tkRP

proc parseAttributes(p: var Parser, attrs: var seq[Node],
    el: TokenTuple) {.gcsafe.} =
  # parse HTML element attributes
  while true:
    case p.curr.kind
    of tkEOF: break
    of tkDot:
      walk p
      if likely(anyAttrIdent()):
        let attrKey = "class"
        add attrs,
          ast.newHtmlAttribute("class", ast.newString(p.curr), p.curr)
        walk p
      else: return
    of tkID:
      walk p
      if likely(anyAttrIdent()):
        add attrs,
          ast.newHtmlAttribute("id", ast.newString(p.curr), p.curr)
        walk p
      else: return
    else:
      if anyAttrIdent():
        let attrKey = p.curr; walk p
        var emptyAttr: bool
        if p.curr is tkAssign:
          walk p
        else:
          emptyAttr = true
        if unlikely(emptyAttr):
          add attrs,
            ast.newHtmlAttribute(attrKey.value, nil, attrKey)
          continue # accept attributes without assigned values. e.g. `readonly`
        case p.curr.kind
        of tkString, tkInteger, tkFloat, tkBool:
          add attrs,
            ast.newHtmlAttribute(attrKey.value,
              ast.newString(p.curr), attrKey)
          walk p
          if p.curr is tkAmp:
            while p.curr is tkAmp:
              let attrNode = p.pStringConcat()
              caseNotNil attrNode:
                add attrs[^1].attrValue.sVals, attrNode
              do: return
        of tkLP:
          let exprNode = p.pGroupExpr()
          caseNotNil exprNode:
            add attrs, exprNode
          do: return
        # of tkBacktick:
        #   let attrValue = ast.newString(p.curr)
        #   attrs[attrKey.value] = @[attrValue]
        #   walk p
        of tkLB:
          let arrayNode: Node = p.pAnoArray()
          caseNotNil arrayNode:
            add attrs,
              ast.newHtmlAttribute(attrKey.value, arrayNode, attrKey)
          do: return
        of tkLC:
          let objectNode: Node = p.pAnoObject()
          caseNotNil objectNode:
            add attrs,
              ast.newHtmlAttribute(attrKey.value, objectNode, attrKey)
          do: return
        else:
          var x: Node
          if p.next is tkLP and p.next.wsno == 0:
            x = p.pFunctionCall()
          else:
            x = p.pIdent()
          caseNotNil x:
            add attrs,
              ast.newHtmlAttribute(attrKey.value, x, attrKey)
          do: break
      else:
        case p.curr.kind
        of tkIdentVar, tkIdentVarSafe:
          if p.curr.line == el.line or p.curr.pos > el.line:
            discard
          elif p.next isnot tkGT and p.next.line != p.curr.line:
            if p.curr.pos <= el.pos or not p.next.isInfix:
              break
          let x = p.pIdent()
          caseNotNil x:
            add attrs, x
          do: break
        of tkLP:
          let exprNode = p.pGroupExpr()
          caseNotNil exprNode:
            add attrs, exprNode
          do: break
        else:
          break

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
  of tkDot, tkID, tkIdentifier:
    p.parseAttributes(result.htmlAttributes, this)
  of tkIdentVar, tkIdentVarSafe:
    let x = p.pIdent()
    caseNotNil x:
      add result.htmlAttributes, x
    case p.curr.kind
    of tkDot, tkID, tkIdentifier:
      p.parseAttributes(result.htmlAttributes, this)
    else: discard
  of tkAsterisk:
    walk p
    case p.curr.kind
    of tkInteger:
      result.htmlMultiplyBy = ast.newNode(ntLitInt)
      result.htmlMultiplyBy.iVal = p.curr.value.parseInt
      walk p
    of tkIdentVar, tkIdentVarSafe:
      result.htmlMultiplyBy = p.pIdent()
      caseNotNil result.htmlMultiplyBy:
        discard
    else: return nil
  else:
    if p.curr is tkLP and
      (p.curr.line == this.line or p.curr.pos > this.pos):
        p.parseAttributes(result.htmlAttributes, this)
    else: discard
    # if p.curr.line == this.line:
    #   result.attrs = HtmlAttributes()
    #   p.parseAttributes(result, this)
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
                  try:
                    dec p.lvl, currentParent.meta[2] div p.curr.pos
                  except DivByZeroDefect:
                    discard
                  delete(p.parentNode, p.parentNode.high)
                  break
          add result.nodes, node
          if p.lvl != 0:
            dec p.lvl
          return result
      else: return
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
  caseNotNil result.expr:
    result.body = p.parseStatement(tk)
  do: return

prefixHandle pCondition:
  # parse `if`, `elif`, `else` condition statements
  var this = p.curr
  let ifbranch = p.parseCondBranch(this)
  caseNotNil ifbranch.expr:
    result = ast.newCondition(ifbranch, this)
    while p.curr is tkElif and (p.curr.pos == this.pos or p.prev is tkRC):
      # parse `elif` branches
      let eliftk = p.curr
      let condBranch = p.parseCondBranch(eliftk)
      caseNotNil condBranch.expr:
        if unlikely(condBranch.body.stmtList.len == 0):
          return nil
        add result.condElifBranch, condBranch

    if p.curr is tkElse and (p.curr.pos == this.pos or p.next is tkLC):
      # parse `else` branch
      let elsetk = p.curr
      walk p
      let elseStmtBranch = p.parseStatement(elsetk)
      caseNotNil elseStmtBranch:
        result.condElseBranch = elseStmtBranch

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
        discard p.parseStatement(currOfToken, excludes, includes)

prefixHandle pWhile:
  # parse `while` statement
  let tk = p.curr; walk p
  result = ast.newNode(ntWhileStmt, tk)
  result.whileExpr = p.getPrefixOrInfix()
  caseNotNil result.whileExpr:
    result.whileBody = p.parseStatement(tk)
    caseNotNil result.whileBody:
      discard

prefixHandle pFor:
  # parse `for` statement
  let tk = p.curr; walk p
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
    let inToken = p.curr
    expectWalk tkIN
    if p.curr in {tkIdentVar, tkIdentVarSafe, tkString, tkLB} or p.isFnCall:
      let items = p.parsePrefix()
      caseNotNil items:
        result.loopItems = items
    elif p.curr in {tkInteger, tkIdentVar, tkIdentVarSafe} and p.curr.line == inToken.line:
      let min = p.curr; walk p
      if likely(isRange()):
        walk p, 2
        expect {tkInteger, tkIdentVar, tkIdentVarSafe, tkIdentifier}:
          if p.curr is tkIdentifier:
            if p.isFnCall(): discard
            else: return nil
          result.loopItems = ast.newNode(ntIndexRange)
          case p.curr.kind
          of tkInteger:
            result.loopItems.rangeNodes = [
              ast.newInteger(min.value.parseInt, min),
              ast.newInteger(p.curr.value.parseInt, p.curr)
            ]
            walk p
          of tkIdentVar, tkIdentVarSafe:
            result.loopItems.rangeNodes[0] = ast.newInteger(min.value.parseInt, min)
            result.loopItems.rangeNodes[1] = p.pIdent()
          else: discard
      else: return nil
    result.loopBody = p.parseStatement(tk)
    caseNotNil result.loopBody:
      discard
    do:
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
          v = p.getPrefixOrInfix(includes = tkAssignableSet + {tkBlock, tkFunc})
          # todo wip allow defining anonymous functions/blocks 
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
      if p.curr.value.startsWith("std/") or p.curr.value == "*":
        p.tree.modules[p.curr.value] =
          p.engine.parseModule(p.curr.value, std(p.curr.value)[1])
        p.tree.modules[p.curr.value].src = p.curr.value
      else:
        let path = 
          (if not isAbsolute(p.curr.value):
            absolutePath(p.curr.value)
          else:
            p.curr.value).addFileExt(".timl")
        if fileExists(path):
          let contents = readFile(path)
          p.tree.modules[path] =
            p.engine.parseModule(path, SourceCode(contents))
        else:
          errorWithArgs(importNotFound, p.curr, [p.curr.value.addFileExt(".timl")])
        if likely(not p.hasErrors):
          p.tree.modules[path].src = path
      walk p

prefixHandle pSnippet:
  case p.curr.kind
  of tkSnippetJS:
    result = ast.newNode(ntJavaScriptSnippet, p.curr)
    result.snippetCode = p.curr.value
    for attr in p.curr.attr:
      let identNode = ast.newNode(ntIdent, p.curr)
      let id = attr.split("_")
      identNode.identName = id[1]
      add result.snippetCodeAttrs, (attr, identNode)
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
      return nil # todo error client-side requires `target` attribute
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
      if p.curr is tkEnd:
        walk p
      elif p.curr is tkDO:
        result.clientBind = ast.newNode(ntDoBlock)
        result.clientBind.doBlockCode = p.curr.value
        walk p
      else:
        # todo make `end` optional if the
        # current token is tkEOF
        return nil

prefixHandle pPlaceholder:
  # parse a placeholder
  let tk = p.curr; walk p
  expectWalk tkID
  expect tkIdentifier:
    result = ast.newNode(ntPlaceholder)
    result.placeholderName = p.curr.value; walk p
    p.tpl.jitEnable()

template handleImplicitDefaultValue {.dirty.} =
  # handle implicit default value
  walk p
  let implNode = p.getPrefixOrInfix(includes = tkAssignableSet)
  caseNotNil implNode:
    result.fnParams[pName.value].pImplVal = implNode
    isTypedOrDefault = true

prefixHandle pFunction:
  # parse a function declaration
  let tk = p.curr; walk p # tkFN
  if p.curr is tkIdentifier:
    result = ast.newFunction(tk, p.curr.value)
    walk p
  else:
    result = ast.newFunction(tk)
  if p.curr is tkAsterisk:
    result.fnExport = true
    walk p
  if p.curr is tkLP:
    walk p
    result.fnParams = newOrderedTable[string, FNParam]()
    while p.curr isnot tkRP:
      var isTypedOrDefault: bool
      case p.curr.kind
      of tkIdentifier:
        let pName = p.curr
        walk p
        if p.curr is tkColon:
          walk p # tkColon
          let isMut =
            if p.curr is tkVar:
              walk p; true
            else: false
          case p.curr.kind
          of tkTypedLiterals:
            let pType = p.curr.kind.getType
            let dataType = p.getDataType
            result.fnParams[pName.value] =
              (pName.value, pType, nil, dataType, isMut, [p.curr.line, p.curr.pos, p.curr.col]) # todo parse implicit value
            walk p
            if p.curr is tkAssign:
              handleImplicitDefaultValue()
            else:
              isTypedOrDefault = true
          else: return nil
        elif p.curr is tkAssign:
          result.fnParams[pName.value] =
            (pName.value, ntUnknown, nil, typeNil, false, [0, 0, 0])
          handleImplicitDefaultValue()
          result.fnParams[pName.value].meta = implNode.meta
        if p.curr is tkComma and p.next isnot tkRP:
          walk p
        elif not isTypedOrDefault and p.next isnot tkIdentifier:
          return nil
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
        result.fnReturnType = p.curr.kind.getType
        result.fnReturnHtmlElement = htmlTag(p.curr.value)
        walk p; expectWalk(tkRB)
      else: discard # todo error
    of tkLitVoid:
      result.fnReturnType = ntLitVoid
      walk p
    else:
      expect tkTypedLiterals:
        # set a return type
        result.fnReturnType = p.curr.kind.getType
        walk p
  if p.curr in {tkAssign, tkLC}:
    # begin function body
    result.fnBody = p.parseStatement(tk, defaultBodyMarker = tkAssign)
    result.fnSource = p.tree.src
  else:
    if p.tree.src.startsWith("std/") or p.tree.src == "*":
      result.fnType = FunctionType.fnImportSystem
    else:
      result.fnType = FunctionType.fnImportModule
    result.fnSource = p.tree.src
    result.fnFwdDecl = true

prefixHandle pBlock:
  # parse a macro definition
  result = p.pFunction(excludes, includes)
  caseNotNil result:
    result.fnIdent = "@" & result.fnIdent
    result.nt = ntBlock
    if p.curr is tkDO and p.curr.line == result.meta[0]:
      result.clientBind = ast.newNode(ntDoBlock)
      result.clientBind.doBlockCode = p.curr.value


prefixHandle pFunctionCall:
  # parse a function call
  result = ast.newCall(p.curr)
  walk p, 2 # we know tkLP is next so we'll skip it
  while p.curr isnot tkRP:
    if unlikely(p.curr is tkEOF): return nil
    let argNode = p.getPrefixOrInfix(includes = tkAssignableSet)
    if p.curr is tkComma and p.next in tkAssignableSet:
      walk p
    elif p.curr isnot tkRP:
      return nil
    caseNotNil argNode:
      add result.identArgs, argNode
  walk p # tkRP

prefixHandle pBlockCall:
  # Parse a macro call
  let tk = p.curr
  walk p # tkAt
  expect tkIdentifier:
    result = ast.newBlockIdent(p.curr)
    walk p
    while true:
      case p.curr.kind
      of tkComma:
        walk p
        if p.curr is tkIdentifier and p.next is tkAssign:
          # parse named parameters
          discard # TODO
        else:
          let argNode = p.getPrefixOrInfix(includes = tkAssignableSet)
          caseNotNil argNode:
            add result.identArgs, argNode
      of tkColon:
        if p.next.isChild(tk):
          let stmtNode = p.parseStatement(tk)
          caseNotNil stmtNode:
            add result.identArgs, stmtNode
            break
        else:
          let inlineNode = p.getPrefixOrInfix()
          caseNotNil inlineNode:
            add result.identArgs, inlineNode
          break
      of tkDot, tkID:
        p.parseAttributes(result.identArgs, tk)
      of tkIdentifier:
        if tk.col >= p.curr.col: break
        p.parseAttributes(result.identArgs, tk)
      else: break

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
      return p.parseTernaryExpr(result)
    else: discard

proc parseTernaryExpr(p: var Parser, infixExpr: Node): Node {.gcsafe.} =
  # parse an one line conditional using ternary operator
  var condBranch: ConditionBranch
  condBranch.expr = infixExpr
  var ifToken = p.curr
  expectWalk tkTernary # ?
  let condBody = p.getPrefixOrInfix()
  caseNotNil condBody:
    condBranch.body = ast.newNode(ntStmtList, ifToken)
    add condBranch.body.stmtList, ast.newCommand(cmdReturn, condBody, ifToken)
  expectWalk tkOrOr # ||
  let elseToken = p.prev
  var condNode = ast.newCondition(condBranch, elseToken)
  let node = p.getPrefixOrInfix()
  caseNotNil node:
    condNode.condElseBranch = ast.newNode(ntStmtList, elseToken)
    add condNode.condElseBranch.stmtList, ast.newCommand(cmdReturn, node, elseToken)
  result = newStmtList(ifToken)
  result.stmtList.add(condNode)

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

proc parseAssignExpr(p: var Parser, lhs: Node): Node {.gcsafe.} =
  # parse assignment expression
  walk p # tkAssign
  let varValue = p.getPrefixOrInfix()
  caseNotNil varValue:
    result = ast.newAssignment(lhs, varValue)

proc getInfixFn(p: var Parser, excludes, includes: set[TokenKind] = {}): InfixFunction {.gcsafe.} =
  case p.curr.kind
  of tkCompSet: parseCompExp
  of tkMathSet: parseMathExp
  of tkAssign: parseAssignExpr
  else: nil

proc parseInfix(p: var Parser, lhs: Node): Node {.gcsafe.} =
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
    of tkWhile: pWhile
    of tkIdentifier:
      if p.next is tkLP and p.next.wsno == 0:
        pFunctionCall # function call by ident
      elif p.next is tkAssign:
        pHtmlAttribute
      elif likely(p.curr.value[0] in IdentChars):
        pElement # parse HTML element
      else: nil
    of tkIdentVar, tkIdentVarSafe: pIdentOrAssignment
    of tkViewLoader: pViewLoader
    of tkSnippetJS, tkSnippetJSON,
       tkSnippetYaml: pSnippet
    of tkInclude: pInclude
    of tkImport: pImport
    of tkClient: pClientSide
    of tkLB: pAnoArray
    of tkLC: pAnoObject
    of tkFN, tkFunc: pFunction
    of tkBlock: pBlock
    of tkEchoCmd: pEchoCommand
    of tkDiscardCmd: pDiscardCommand
    of tkBreakCmd: pBreakCommand
    of tkReturnCmd: pReturnCommand
    of tkPlaceholder: pPlaceholder
    of tkAt: pBlockCall
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
  if p.curr.isInfix:
    caseNotNil lhs:
      let infixNode = p.parseInfix(lhs)
      caseNotNil infixNode:
        return infixNode
  result = lhs

prefixHandle pComponent:
  ## Create custom HtmlElements at client-side
  # todo
  let tk = p.curr; walk p # tkComponent
  expect tkIdentifier:
    let id = p.curr
    walk p
    expectWalk tkLP
    expect tkIdentifier:
      let tagName = p.curr
      walk p
    expectWalk tkRP
    result = newComponent(id)
    let componentBody = p.pAnoObject()
    # todo parsed object is one level
    # object that should contain specific
    # keys/values and must be validated
    # at compile-time
    caseNotNil componentBody:
      result.componentBody = componentBody
    # debugEcho result

proc parseRoot(p: var Parser, excludes, includes: set[TokenKind] = {}): Node {.gcsafe.} =
  # Parse elements declared at root-level
  result =
    case p.curr.kind
    of tkVar,tkConst: p.pAssignment()
    of tkIdentVar, tkIdentVarSafe:
      if p.next is tkAssign:
        p.pIdentOrAssignment()
      elif p.next in {tkDot, tkLB}:
        p.pIdent()
      else: nil
    of tkIF:          p.pCondition()
    of tkCase:        p.pCase()
    of tkFor:         p.pFor()
    of tkWhile:       p.pWhile()
    of tkViewLoader:  p.pViewLoader()
    of tkIdentifier:
      if p.next is tkLP and p.next.wsno == 0:
        p.pFunctionCall()
      elif p.curr.value[0] in IdentChars:
        p.pElement()
      else: nil
    of tkSnippetJS,
        tkSnippetJSON,
        tkSnippetYaml: p.pSnippet()
    of tkInclude:     p.pInclude()
    of tkImport:      p.pImport()
    of tkLB:          p.pAnoArray()
    of tkLC:          p.pAnoObject()
    of tkFN, tkFunc:  p.pFunction()
    of tkBlock:       p.pBlock()
    of tkComponent:   p.pComponent()
    of tkClient:      p.pClientSide()
    of tkEchoCmd:     p.pEchoCommand()
    of tkDiscardCmd:  p.pDiscardCommand()
    of tkPlaceholder: p.pPlaceholder()
    of tkAt:          p.pBlockCall()
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
      var childParser: Parser = i.handle.engine.newParser(tpl, false)
      if likely(not childParser.hasErrors):
        if childParser.tpl.jitEnabled():
          jitMainParser = true
        when defined napiOrWasm:
          partials[path] = (childParser.getAst(), @[])
        else:
          partials[path] = (childParser.getAst(), childParser.logger.errors.toSeq)
        result = childParser.includes.keys.toSeq
        if not tpl.hasDep(i.handle.tpl.getSourcePath()):
          tpl.addDep(i.handle.tpl.getSourcePath())
      else:
        # this is weird, gotta do something different here
        i.handle.logger.errorLogs = i.handle.logger.errorLogs.concat(childParser.logger.errorLogs)
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
      break
    if unlikely(p.handle.hasErrors):
      # reset(p.handle.tree) # reset incomplete tree
      break
    let node = p.handle.parseRoot()
    caseNotNil node:
      add p.handle.tree.nodes, node
    do: discard
  lexbase.close(p.handle.lex)
  if isMainParser:
    if p.handle.engine.importsHandle.hasDeps(path) and not p.handle.hasErrors:
      let deps = p.handle.engine.importsHandle.dependencies(path).toSeq
      p.imports(deps, parseHandle[Parser])

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
        break
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
  engine.importsHandle.indexModule(tpl.sources.src)
  p.handle.engine = engine
  p.handle.tpl = tpl
  p.handle.refreshAst = refreshAst
  p.handle.tree = Ast(src: tpl.sources.src)
  p.handle.lex = newLexer(readFile(tpl.sources.src), allowMultilineStrings = true)
  initModuleSystem()
  p.handle.initSystemModule()
  startParse(tpl.sources.src)
  if isMainParser:
    {.gcsafe.}:
      if partials.len > 0:
        p.handle.tree.partials = partials
      if jitMainParser:
        p.handle.tpl.jitEnable
    for path, notification in engine.importsHandle.notifications:
      echo path
      echo notification
  collectImporterErrors()
  result = p.handle

proc parseSnippet*(id, code: string): Parser {.gcsafe.} =
  ## Parse static snippet `code` at runtime before
  ## calling the `precompile` handle
  var p = Parser(
    tree: Ast(src: id),
    lex: newLexer(code, allowMultilineStrings = true),
    logger: Logger(filePath: id)
  )
  p.curr = p.lex.getToken()
  p.next = p.lex.getToken()
  initModuleSystem()
  p.initSystemModule()
  p.skipComments() # if any
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
  let snippetPath = absolutePath(snippetPath)
  var p = Parser(
    tree: Ast(src: snippetPath),
    lex: newLexer(readFile(snippetPath), allowMultilineStrings = true),
    logger: Logger(filePath: snippetPath)
  )
  p.curr = p.lex.getToken()
  p.next = p.lex.getToken()
  initModuleSystem()
  p.initSystemModule()
  p.skipComments() # if any
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