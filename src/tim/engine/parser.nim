# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

{.warning[ImplicitDefaultValue]:off.}
import std/[macros, streams, lexbase, strutils, sequtils, re, tables]
from std/os import `/`

import ./meta, ./tokens, ./ast, ./logging
import pkg/kapsis/cli

# from ./meta import TimEngine, TimTemplate, TimTemplateType, getType,
#   getTemplateByPath, getSourcePath, setViewIndent, jitEnable,
#   addDep, hasDep, getDeps

import pkg/importer

type
  Parser* = object
    lex: Lexer
    lvl: int
    prev, curr, next: TokenTuple
    engine: TimEngine
    tpl: TimTemplate
    logger*: Logger
    hasErrors*, nilNotError, hasLoadedView: bool
    parentNode: seq[Node]
    includes: Table[string, Meta]
    isMain: bool
    refreshAst: bool
    tplView: TimTemplate
    tree: Ast

  PrefixFunction = proc(p: var Parser, excludes, includes: set[TokenKind] = {}): Node {.gcsafe.}
  InfixFunction = proc(p: var Parser, lhs: Node): Node {.gcsafe.}

const
  tkCompSet = {tkEQ, tkNE, tkGT, tkGTE, tkLT, tkLTE, tkAmp, tkAndAnd}
  tkMathSet = {tkPlus, tkMinus, tkMultiply, tkDivide}
  tkAssignableSet = {
    tkString, tkBacktick, tkBool, tkFloat,
    tkInteger, tkIdentVar, tkLC, tkLB
  }
  tkComparable = tkAssignableSet
  tkTypedLiterals = {
    tkLitArray, tkLitBool, tkLitFloat, tkLitFunction,
    tkLitInt, tkLitObject, tkLitString
  }

#
# Forward Declaration
#
proc getPrefixFn(p: var Parser, excludes, includes: set[TokenKind] = {}): PrefixFunction {.gcsafe.}
proc getInfixFn(p: var Parser, excludes, includes: set[TokenKind] = {}): InfixFunction {.gcsafe.}

proc parseInfix(p: var Parser, lhs: Node): Node {.gcsafe.}
proc getPrefixOrInfix(p: var Parser, includes, excludes: set[TokenKind] = {}, infix: Node = nil): Node {.gcsafe.}
proc parsePrefix(p: var Parser, excludes, includes: set[TokenKind] = {}): Node {.gcsafe.}

proc pAnoArray(p: var Parser, excludes, includes: set[TokenKind] = {}): Node {.gcsafe.}
proc pAnoObject(p: var Parser, excludes, includes: set[TokenKind] = {}): Node {.gcsafe.}
proc pAssignable(p: var Parser): Node {.gcsafe.}

template caseNotNil*(x: Node, body): untyped =
  if likely(x != nil):
    body
  else: return nil

#
# Error API
#
proc hasError*(p: Parser): bool = p.hasErrors

#
# Parse Utils
#
proc isChild(tk, parent: TokenTuple): bool {.inline.} =
  tk.pos > parent.pos and (tk.line > parent.line and tk.kind != tkEOF)

proc isInfix*(p: var Parser): bool {.inline.} =
  p.curr.kind in tkCompSet + tkMathSet 

proc isInfix*(tk: TokenTuple): bool {.inline.} =
  tk.kind in tkCompSet + tkMathSet 

proc `isnot`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind != kind

proc `is`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind == kind

proc `in`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind in kind

proc `notin`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind notin kind

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

proc walk(p: var Parser, offset = 1) {.gcsafe.} =
  var i = 0
  while offset > i:
    inc i
    p.prev = p.curr
    p.curr = p.next
    p.next = p.lex.getToken()
    case p.next.kind
    of tkComment:
      p.next = p.lex.getToken() # skip inline comments
    else: discard

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
  node.meta = [p.curr.line, p.curr.pos, p.curr.col]
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
    of tkLitArray: ntLitArray
    of tkLitBool: ntLitBool
    of tkLitFloat: ntLitFloat
    of tkLitFunction: ntLitFunction
    of tkLitInt: ntLitInt
    of tkLitObject: ntLitObject
    of tkLitString: ntLitString
    else: ntUnknown

#
# Parse Handlers
#
prefixHandle pString:
  # parse a single/double quote string
  result = ast.newString(p.curr)
  walk p

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

proc parseDotExpr(p: var Parser, lhs: Node): Node =
  # parse dot expression
  result = ast.newNode(ntDotExpr, p.prev)
  result.lhs = lhs
  walk p # tkDot
  if likely(p.curr is tkIdentifier):
    result.rhs = ast.newIdent(p.curr)
    walk p
    while p.curr is tkDot:
      result = p.parseDotExpr(result)
  else:
    return nil

proc parseBracketExpr(p: var Parser, lhs: Node): Node =
  # parse bracket expression
  result = ast.newNode(ntBracketExpr, p.prev)

prefixHandle pIdent:
  # parse an identifier
  result = ast.newIdent(p.curr)
  let storageType = p.getStorageType()
  walk p
  case p.curr.kind
  of tkDot:
    # handle dot expressions
    result = p.parseDotExpr(result)
    result.storageType = storageType
    return # result
  of tkLB:
    # handle bracket expressions
    result = p.parseBracketExpr(result)
    result.storageType = storageType
    return # result
  else: discard

prefixHandle pIdentOrAssignment:
  let ident = p.curr
  if p.next is tkAssign:
    walk p, 2 # tkAssign
    let varValue = p.getPrefixOrInfix()
    caseNotNil varValue:
      return ast.newAssignment(ident, varValue)
  return p.pIdent()

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
    else:
      nil

prefixHandle pEchoCommand:
  # parse `echo` command
  let tk = p.curr
  walk p
  var varNode: Node
  case p.curr.kind
  of tkAssignableSet:
    if p.curr is tkIdentVar:
      if p.next.isInfix:
        varNode = p.getPrefixOrInfix()
      else:
        varNode = p.pIdent()
    else:
      varNode = p.getPrefixOrInfix()
    return ast.newCommand(cmdEcho, varNode, tk)
  else: errorWithArgs(unexpectedToken, p.curr, [p.curr.value])

prefixHandle pReturnCommand:
  # parse `return` command
  let tk = p.curr
  if p.next in tkAssignableSet:
    walk p
    let varValue = p.getPrefixOrInfix()
    return ast.newCommand(cmdReturn, varValue, tk)

template anyAttrIdent(): untyped =
  (
    (p.curr in {tkString, tkIdentifier, tkIf, tkFor,
      tkElif, tkElse, tkOr, tkIn} and p.next is tkAssign) or
    (p.curr is tkIdentifier and (p.curr.line == el.line or (p.curr.isChild(el) and p.next is tkAssign)))
  )

proc parseAttributes(p: var Parser, attrs: var HtmlAttributes, el: TokenTuple) {.gcsafe.} =
  # parse HTML element attributes
  while true:
    case p.curr.kind
    of tkEOF: break
    of tkDot:
      let attrKey = "class"
      if attrs.hasKey(attrKey):
        attrs[attrKey].add(ast.newString(p.next))
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
          of tkString:
            let attrValue = ast.newString(p.curr)
            attrs[attrKey.value] = @[attrValue]
            walk p
          of tkBacktick:
            let attrValue = ast.newString(p.curr)
            attrs[attrKey.value] = @[attrValue]
            walk p            
          else:
            attrs[attrKey.value] = @[ast.newIdent(p.curr)]
            walk p
        else: errorWithArgs(duplicateAttribute, attrKey, [attrKey.value])
      else: break
      # errorWithArgs(invalidAttribute, p.prev, [p.prev.value])

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
    p.parentNode.add(result)
  else:
    if result.meta[0] > p.parentNode[^1].meta[0]:
      p.parentNode.add(result)
  # parse HTML attributes
  case p.curr.kind
  of tkDot, tkID:
    result.attrs = HtmlAttributes()
    p.parseAttributes(result.attrs, this)
  of tkIdentifier:
    result.attrs = HtmlAttributes()
    p.parseAttributes(result.attrs, this)
  else: discard

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
      let valNode = p.getPrefixOrInfix()
      if likely(valNode != nil):
        result.nodes.add(valNode)
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
                  node.nodes.add(subNode)
                # if p.hasError(): break
                if p.curr.pos < currentParent.meta[2]:
                  dec p.lvl, currentParent.meta[2] div p.curr.pos
                  delete(p.parentNode, p.parentNode.high)
                  break
          result.nodes.add(node)
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
      result.nodes.add(subNode)
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
  if likely(result.expr != nil):
    while p.curr.isChild(tk):
      let node = p.getPrefixOrInfix()
      if likely(node != nil):
        add result.body, node
    if unlikely(result.body.len == 0):
      error(badIndentation, p.curr)

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
          result.condElseBranch.add(node)
      if unlikely(result.condElseBranch.len == 0):
        return nil

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
    expectWalk(tkIN)
    expect tkIdentVar:
      result.loopItems = p.pIdentOrAssignment()
    if p.curr is tkColon: walk p
    while p.curr.isChild(tk):
      let node = p.getPrefixOrInfix()
      caseNotNil node:
        result.loopBody.add(node)
    if unlikely(result.loopBody.len == 0):
      error(badIndentation, p.curr)
  else: discard

prefixHandle pAnoObject:
  # parse an anonymous object
  let anno = ast.newNode(ntLitObject, p.curr)
  anno.objectItems = newOrderedTable[string, Node]()
  walk p # {
  while p.curr.isIdent(anyIdent = true, anyStringKey = true) and p.next.kind == tkColon:
    let fName = p.curr
    if unlikely(p.curr is tkColon):
      return nil
    else: walk p, 2
    if likely(anno.objectItems.hasKey(fName.value) == false):
      var item: Node
      case p.curr.kind
      of tkLB:
        item = p.pAnoArray()
      of tkLC:
        item = p.pAnoObject()
      else:
        item = p.getPrefixOrInfix(includes = tkAssignableSet)
      if likely(item != nil):
        anno.objectItems[fName.value] = item
      else: return
    else:
      errorWithArgs(duplicateField, fName, [fName.value])
    if p.curr is tkComma:
      walk p # next k/v pair
  if likely(p.curr is tkRC):
    walk p
  return anno

prefixHandle pAnoArray:
  # parse an anonymous array
  let tk = p.curr
  walk p # [
  var items: seq[Node]
  while p.curr.kind != tkRB:
    var item = p.pAssignable()
    if likely(item != nil):
      add items, item
    else:
      if p.curr is tkLB:
        item = p.pAnoArray()
        caseNotNil item:
          add items, item
      elif p.curr is tkLC:
        item = p.pAnoObject()
        caseNotNil item:
          add items, item
      else: return # todo error
    if p.curr is tkComma:
      walk p
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
    p.includePartial(result, p.curr.value)
    walk p
    while p.curr is tkComma:
      walk p
      if likely p.curr is tkString:
        p.includePartial(result, p.curr.value)
        walk p
      else: return nil

prefixHandle pSnippet:
  case p.curr.kind
  of tkSnippetJS:
    result = ast.newNode(ntJavaScriptSnippet, p.curr)
    result.snippetCode = p.curr.value
  of tkSnippetYaml:
    result = ast.newNode(ntYamlSnippet, p.curr)
    result.snippetCode = p.curr.value
  else: discard
  # elif p.curr.kind == tkSass:
    # result = ast.newSnippet(p.curr)
    # result.sassCode = p.curr.value
  # elif p.curr.kind in {tkJson, tkYaml}:
  #   let code = p.curr.value.split(Newlines, maxsplit = 1)
  #   var ident = code[0]
  #   p.curr.value = code[1]
  #   if p.curr.kind == tkJson:
  #     result = newSnippet(p.curr, ident)
  #     result.jsonCode = p.curr.value
  #   else:
  #     p.curr.kind = tkJson
  #     result = newSnippet(p.curr, ident)
  #     # result.jsonCode = yaml(p.curr.value).toJsonStr
  walk p

template handleImplicitDefaultValue {.dirty.} =
  # handle implicit default value
  walk p
  let implNode = p.getPrefixOrInfix(includes = tkAssignableSet)
  if likely(implNode != nil):
    result.fnParams[pName.value].pImplVal = implNode

prefixHandle pFunction:
  # parse a function declaration
  let this = p.curr; walk p # tkFN
  expect tkIdentifier: # function identifier
    result = ast.newFunction(this, p.curr.value)
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
            (pName.value, ntUnknown, nil, [0, 0, 0])
          handleImplicitDefaultValue()
          result.fnParams[pName.value].meta = implNode.meta
      else: return nil
    walk p # tkRP
    if p.curr is tkColon:
      walk p
      expect tkTypedLiterals:
        # set return type
        result.fnReturnType = p.getType
        walk p
    expectWalk tkAssign
    while p.curr.isChild(this):
      # todo disallow use of html inside a function 
      let node = p.getPrefixOrInfix()
      if likely(node != nil):
        add result.fnBody, node
    if unlikely(result.fnBody.len == 0):
      error(badIndentation, p.curr)

prefixHandle pFunctionCall:
  # parse a function call
  result = ast.newCall(p.curr)
  walk p, 2 # we know tkLP is next so we'll skip it
  while p.curr isnot tkRP:
    let argNode = p.getPrefixOrInfix(includes = tkAssignableSet)
    if likely(argNode != nil):
      add result.callArgs, argNode
    else: return nil
  walk p # tkRP

#
# Infix Main Handlers
#
proc parseMathExp(p: var Parser, lhs: Node): Node {.gcsafe.}
proc parseCompExp(p: var Parser, lhs: Node): Node {.gcsafe.}

proc parseCompExp(p: var Parser, lhs: Node): Node {.gcsafe.} =
  # parse logical expressions with symbols (==, !=, >, >=, <, <=)
  let op = getInfixOp(p.curr.kind, false)
  walk p
  let rhstk = p.curr
  let rhs = p.parsePrefix(includes = tkComparable)
  if likely(rhs != nil):
    result = ast.newNode(ntInfixExpr, rhstk)
    result.infixLeft = lhs
    result.infixOp = op
    if p.curr.kind in tkMathSet:
      result.infixRight = p.parseMathExp(rhs)
    else:
      result.infixRight = rhs
    case p.curr.kind
    of tkOr, tkOrOr, tkAnd, tkAndAnd:
      let infixNode = ast.newNode(ntInfixExpr, p.curr)
      infixNode.infixLeft = result
      infixNode.infixOp = getInfixOp(p.curr.kind, true)
      walk p
      let rhs = p.getPrefixOrInfix()
      caseNotNil rhs:
        infixNode.infixRight = rhs
        return infixNode
    else: discard

proc parseMathExp(p: var Parser, lhs: Node): Node {.gcsafe.} =
  # parse math expressions with symbols (+, -, *, /)
  let infixOp = getInfixMathOp(p.curr.kind, false)
  walk p
  let rhstk = p.curr
  let rhs = p.parsePrefix(includes = tkComparable)
  if likely(rhs != nil):
    result = ast.newNode(ntMathInfixExpr, rhstk)
    result.infixMathOp = infixOp
    result.infixMathLeft = lhs
    case p.curr.kind
    of tkMultiply, tkDivide:
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
    of tkEchoCmd: pEchoCommand
    of tkIF: pCondition
    of tkFor: pFor
    of tkIdentifier:
      if p.next is tkLP and p.next.wsno == 0: pFunctionCall
      else: pElement
    of tkIdentVar: pIdentOrAssignment
    of tkViewLoader: pViewLoader
    of tkSnippetJS: pSnippet
    of tkInclude: pInclude
    of tkLB: pAnoArray
    of tkLC: pAnoObject
    of tkFN: pFunction
    else: nil

proc parsePrefix(p: var Parser, excludes, includes: set[TokenKind] = {}): Node {.gcsafe.} =
  let prefixFn = p.getPrefixFn(excludes, includes)
  if likely(prefixFn != nil):
    return p.prefixFn(excludes, includes)
  result = nil

proc getPrefixOrInfix(p: var Parser, includes,
    excludes: set[TokenKind] = {}, infix: Node = nil): Node {.gcsafe.} =
  let lhs = p.parsePrefix(excludes, includes)
  var infixNode: Node
  if p.curr.isInfix:
    if likely(lhs != nil):
      infixNode = p.parseInfix(lhs)
      if likely(infixNode != nil):
        return infixNode
    else: return
  result = lhs

proc parseRoot(p: var Parser, excludes, includes: set[TokenKind] = {}): Node {.gcsafe.} =
  # Parse elements declared at root-level
  result =
    case p.curr.kind
    of tkVar,tkConst: p.pAssignment()
    of tkEchoCmd:     p.pEchoCommand()
    of tkReturnCmd:   p.pReturnCommand()
    of tkIdentVar:    p.pIdentOrAssignment()
    of tkIF:          p.pCondition()
    of tkFor:         p.pFor()
    of tkViewLoader:  p.pViewLoader()
    of tkIdentifier:
      if p.next is tkLP and p.next.wsno == 0:
        p.pFunctionCall()
      else:
        p.pElement()
    of tkSnippetJS:   p.pSnippet()
    of tkInclude:     p.pInclude()
    of tkLB: p.pAnoArray()
    of tkLC: p.pAnoObject()
    of tkFN: p.pFunction()
    else: nil
  if unlikely(result == nil):
    let tk = if p.curr isnot tkEOF: p.curr else: p.prev
    errorWithArgs(unexpectedToken, tk, [tk.value])

proc newParser*(engine: TimEngine, tpl, tplView: TimTemplate, isMainParser = true, refreshAst = false): Parser {.gcsafe.}
proc getAst*(p: Parser): Ast {.gcsafe.}
let partials = TimPartialsTable()
var jitMainParser: bool # force main parser enable JIT

proc parseHandle[T](i: Import[T], importFile: ImportFile,
    ticket: ptr TicketLock): seq[string] {.gcsafe, nimcall.} =
  withLock ticket[]:
    let fpath = importFile.getImportPath
    let path = fpath.replace(i.handle.engine.getSourcePath() / $(ttPartial) / "", "")
    var tpl: TimTemplate = i.handle.engine.getTemplateByPath(fpath)
    if likely(not partials.hasKey(path) or i.handle.refreshAst):
      var childParser: Parser = i.handle.engine.newParser(tpl, i.handle.tplView, false)
      if childParser.tpl.jitEnabled():
        jitMainParser = true
      partials[path] = (childParser.getAst(), childParser.logger.errors.toSeq)
    tpl.addDep(i.handle.tplView.getSourcePath())

template startParse(path: string): untyped =
  p.handle.curr = p.handle.lex.getToken()
  p.handle.next = p.handle.lex.getToken()
  p.handle.logger = Logger(filePath: path)
  while p.handle.curr isnot tkEOF:
    if unlikely(p.handle.lex.hasError):
      p.handle.logger.newError(internalError, p.handle.curr.line,
        p.handle.curr.col, false, p.handle.lex.getError)
    if unlikely(p.handle.hasErrors):
      reset(p.handle.tree) # reset incomplete tree
      break
    let node = p.handle.parseRoot()
    if likely(node != nil):
      add p.handle.tree.nodes, node
  lexbase.close(p.handle.lex)
  if p.handle.includes.len > 0 and not p.handle.hasErrors:
    # continue parse other partials
    p.imports(p.handle.includes.keys.toSeq, parseHandle[Parser])

#
# Public API
#
proc newParser*(engine: TimEngine, tpl, tplView: TimTemplate,
    isMainParser = true, refreshAst = false): Parser {.gcsafe.} =
  ## Parse `tpl` TimTemplate
  let partialSrcPath = engine.getSourcePath() / $(ttPartial)
  var p = newImport[Parser](tpl.sources.src, partialSrcPath, baseIsMain=true)
  p.handle.lex = newLexer(readFile(tpl.sources.src), allowMultilineStrings = true)
  p.handle.engine = engine
  p.handle.tpl = tpl
  p.handle.isMain = isMainParser
  p.handle.refreshAst = refreshAst
  p.handle.tplView = tplView
  startParse(tpl.sources.src)
  if isMainParser:
    {.gcsafe.}:
      if partials.len > 0:
        p.handle.tree.partials = partials
      if jitMainParser:
        p.handle.tpl.jitEnable
    for err in p.importErrors:
      case err.reason
      of ImportErrorMessage.importNotFound:
        let meta: Meta = p.handle.includes[err.fpath]
        p.handle.logger.newError(Message.importNotFound, meta[0], meta[2], true, [err.fpath.replace(engine.getSourcePath(), "")])
        p.handle.hasErrors = true
      else: discard
  result = p.handle

proc getAst*(p: Parser): Ast {.gcsafe.} =
  ## Returns the constructed AST
  result = p.tree