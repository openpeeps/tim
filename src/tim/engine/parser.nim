# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://tim-engine.com

import std/[macros, lexbase, tables, strutils, critbits]

import ./[tokens, ast]

type
  Parser* = object
    lex: Lexer
    prev, curr, next: TokenTuple
    # internals
    parentNode: seq[Node]
    classCacheAttr: CritBitTree[Node]
      # A critbit tree used to cache static class attributes
      # prefixed with a dot (.) for faster parsing and memory usage optimization.
    # attrCacheAttr: CritBitTree[Node]
      # A critbit tree used to cache `key=value` HTML attributes
    lvl: int

const
  MathOperators = {tkPlus, tkMinus, tkAsterisk, tkDivide}
  LogicalOperators = {tkAnd, tkAndAnd, tkOr, tkOrOr}
  ComparisonOperators = {tkEQ, tkNE, tkGT, tkGTE, tkLT, tkLTE}
  Operators = ComparisonOperators + MathOperators + {tkAmp, tkAssign}
  Assignables = {tkBool, tkString, tkInteger, tkFloat, tkIdentifier}
#
# Parser utility functions
#
proc skipNextComment(p: var Parser) =
  # Skip comments until the next token
  # This is used to skip inline comments.
  while true:
    case p.next.kind
    of tkComment:
      p.next = p.lex.getToken() # skip inline comments
    else: break

template ruleGuard(body) =
  ## Helper used by {.rule.} to update line info appropriately for nodes.
  when declared(result):
    let
      ln = p.curr.line
      col = p.curr.col
  body
  when declared(result):
    if result != nil:
      result.ln = ln
      result.col = col
      # result.file = scan.file

macro rule(pc) =
  ## Adds a ``scan`` parameter to a proc and wraps its body in a call to
  ## ``ruleGuard``.
  # pc[3].insert(1, newIdentDefs(ident"scan", newTree(nnkVarTy, ident"Scanner")))
  if pc[6].kind != nnkEmpty:
    pc[6] = newCall("ruleGuard", newStmtList(pc[6]))
  pc

type
  PrefixFunction* = proc (p: var Parser): Node

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
      )
    ],
    body,
    pragmas = nnkPragma.newTree(ident("rule"))
  )

proc walk(p: var Parser, offset = 1) =
  # Walk the parser state to the next token.
  # `offset` is the number of tokens to walk
  var i = 0
  while offset > i:
    inc i
    p.prev = p.curr
    p.curr = p.next
    p.next = p.lex.getToken()
    p.skipNextComment()

proc walkOpt(p: var Parser, kind: TokenKind) =
  # This is used to skip over tokens that are not needed
  # in the current context.
  if p.curr.kind == kind:
    walk(p)

template expectWalk(k: TokenKind) =
  if likely(p.curr.kind == k):
    walk p
  else: return nil

template expectWalk(k: TokenKind, bdy) =
  if likely(p.curr.kind == k):
    walk p
    bdy
  else: return

proc skipComments(p: var Parser) =
  while p.curr.kind == tkComment:
    walk p

template caseNotNil(x: Node, body): untyped =
  if likely(x != nil):
    body
  else: return nil

template caseNotNil(x: Node, body, then): untyped =
  if likely(x != nil):
    body
  else: then

proc isChild(tk, parent: TokenTuple): bool {.inline.} =
  tk.pos > parent.pos and (tk.line > parent.line and tk.kind != tkEOF)

proc isInfix(p: var Parser): bool {.inline.} =
  p.curr.kind in Operators

proc isInfix(tk: TokenTuple): bool {.inline.} =
  tk.kind in Operators

proc `isnot`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind != kind

proc `is`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind == kind

proc `in`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind in kind

proc `notin`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind notin kind

#
# Parse handlers - forward declarations
#
proc parseStmt(p: var Parser): Node
proc parsePrefix(p: var Parser): Node
proc parseExpression(p: var Parser): Node
proc parseIdent(p: var Parser): Node
proc parseCall(p: var Parser): Node
proc parseBlockCall(p: var Parser): Node

#
# Parse handlers
#
prefixHandle parseBoolean:
  # parse boolean
  let v =
    try:
      parseBool(p.curr.value)
    except ValueError:
      return nil
  result = ast.newBoolLit(v)
  walk p

prefixHandle parseInteger:
  # parse an interger
  let v =
    try:
      parseInt(p.curr.value)
    except ValueError:
      return nil
  result = ast.newIntLit(v)
  walk p

prefixHandle parseFloat:
  # parse a float number
  let v =
    try:
      parseFloat(p.curr.value)
    except ValueError:
      return nil
  result = ast.newFloatLit(v)
  walk p

prefixHandle parseString:
  # parse a string
  result = ast.newStringLit(p.curr.value)
  walk p

proc parseCommaList(p: var Parser, start, term: static TokenKind,
  results: var seq[Node], infixList: static bool = false): bool =
  # parse a comma separated list of expressions
  walk p # start
  if p.curr isnot term:
    while p.curr isnot tkEOF:
      let lhs: Node = p.parseExpression()
      caseNotNil lhs:
        when infixList == true:
          # the comma list is a list of infix expressions
          # usually representing a list of key-value pairs
          expectWalk tkColon:
            let rhs: Node = p.parseExpression()
            caseNotNil rhs:
              results.add(ast.newInfix(nil, lhs, rhs))
            do: return false
        else:
          # it's a normal array list
          results.add(lhs)
      do: return false
      case p.curr.kind
      of tkComma:
        walk p # skip commas
      of term: walk p; break
      else: return
  else: walk p # skip term, we have an empty list
  result = true

proc parseCommaIdentList(p: var Parser, start,
      term: static TokenKind, results: var seq[Node]): bool =
  # parse a comma separated list of expressions
  walk p # start
  if p.curr isnot term:
    while p.curr isnot tkEOF:
      let defNode: Node = p.parseIdentDefs()
      caseNotNil defNode:
        results.add(defNode)
      do: return false
      case p.curr.kind
      of tkComma:
        walk p # skip commas
      of term:
        walk p
        break # end of the list, break the loop
      else: return
  else: walk p # skip term, we have an empty list
  result = true

prefixHandle parseImportStmt:
  # parse an import statement
  result =
    case p.curr.kind
    of tkImport:
      ast.newTree(nkImport)
    else:
      ast.newTree(nkInclude)
  if p.next is tkLB:
    walk p, 2
    while p.curr isnot tkRB:
      # case p.curr.kind
      # of tkEOF: break # todo error
      # of tkComma: walk p # skip comma
      let path = p.parseExpression()
      caseNotNil path:
        result.add(path)
  else:
    walk p # tkImport
    let path = p.parseExpression()
    caseNotNil path:
      result.add(path)

template anyAttrIdent: untyped =
  (
    (p.curr in {tkString, tkIdentifier, tkType, tkIf, tkFor,
      tkElif, tkElse, tkOr, tkIn} and p.next is tkAssign) or
    (
      (p.curr is tkIdentifier and p.curr.value[0] in IdentChars) and
      (p.curr.line == el.line or (p.curr.isChild(el) and p.next is tkAssign))
    )
  )

proc parseAttributes(p: var Parser, attrs: var seq[Node], el: TokenTuple) =
  # parse attributes of an HTML element
  while true:
    case p.curr.kind
    of tkEOF: break
    of tkDot:
      # parse html classes prefixed with a dot
      walk p # tkDot
      if likely(anyAttrIdent()):
        if p.classCacheAttr.hasKey(p.curr.value):
          # HTML attributes are cached in a CritBitTree
          # to optimize memory usage and speed up
          # the parsing process.
          attrs.add(p.classCacheAttr[p.curr.value])
        else:
          let attrNode = newHtmlAttribute(htmlAttrClass, ast.newStringLit(p.curr.value))
          attrs.add(attrNode)
          p.classCacheAttr[p.curr.value] = attrNode
        walk p
        # todo support class attributes containing colons
        # example `size:sm` 
      elif p.curr is tkIdentVar:
        let identNode = p.parseExpression()
        caseNotNil identNode:
          attrs.add(newHtmlAttribute(htmlAttrClass, identNode))
        do: return
      else: break
    of tkID:
      # parse a `#ident` html attribute
      walk p # tkID
      if likely(anyAttrIdent()):
        attrs.add(ast.newHtmlAttribute(htmlAttrID, ast.newStringLit(p.curr.value)))
        walk p
      elif p.curr is tkIdentVar:
        let identNode = p.parseExpression()
        caseNotNil identNode:
          attrs.add(ast.newHtmlAttribute(htmlAttrID, identNode))
        do: return
      else: break
    else:
      # parse a `key="value"` html attribute
      if anyAttrIdent():
        if p.curr.value == "class":
          # when `class` attribute is used will collect the class values
          # and create a single class attribute with all values
          walk p # tkIdentifier `class`
          expectWalk tkAssign:
            let attrValue: Node = p.parseExpression()
            caseNotNil attrValue:
              let attrNode: Node = newHtmlAttribute(htmlAttrClass, attrValue)
              attrs.add(attrNode)
              continue # no need to continue
            do: break
        elif p.curr.value == "id":
          # todo handle `id` attribute
          break
        var attr = ast.newStringLit(p.curr.value)
        walk p # tk any attribute name
        if p.curr is tkColon:
          attr.stringVal.add(":")
          walk p # tkColon
          if p.curr is tkIdentifier:
            attr.stringVal.add(p.curr.value)
        if p.curr is tkAssign:
          # parse an HTML attribute with a value
          walk p # tkAssign
          let infixNode: Node = ast.newInfix(nil, attr, p.parseExpression())
          let attrNode = ast.newHtmlAttribute(htmlAttr, infixNode)
          attrs.add(attrNode)
        else:
          # html attributes can be passed without a value
          attrs.add(ast.newHtmlAttribute(htmlAttr, attr))
      else: break

prefixHandle parseElement:
  # parse an HTML element
  let tk = p.curr
  let tag = ast.htmlTag(tk.value)
  result = ast.newHtmlElement(tag, tk.value)
  result.ln = p.curr.line
  result.col = p.curr.col
  walk p
  # if result.col != 0:
  #   result.col = p.lvl * 4 # set real indent size
  if p.parentNode.len == 0:
    add p.parentNode, result
  else:
    if result.ln > p.parentNode[^1].ln:
      add p.parentNode, result

  # parse the attributes
  case p.curr.kind
  of tkDot, tkID, tkIdentifier, tkType:
    p.parseAttributes(result.attributes, tk)
  of tkIdentVar, tkIdentVarSafe:
    let x = p.parseIdent()
    caseNotNil x:
      add result.attributes, x
    case p.curr.kind
    of tkDot, tkID, tkIdentifier, tkType:
      p.parseAttributes(result.attributes, tk)
    else: discard
  of tkAsterisk:
    walk p
    # case p.curr.kind
    # of tkInteger:
    #   result.htmlMultiplyBy = ast.newNode(nkInt)
    #   result.htmlMultiplyBy.intVal = p.curr.value.parseInt
    #   walk p
    # of tkIdentVar, tkIdentVarSafe:
    #   result.htmlMultiplyBy = p.parseIdent()
    #   caseNotNil result.htmlMultiplyBy:
    #     discard
    # of tkIdentifier:
    #   result.htmlMultiplyBy = p.parseExpression()
    #   caseNotNil result.htmlMultiplyBy:
    #     discard
    # else: return nil
  else:
    if p.curr is tkLP and
      (p.curr.line == tk.line or p.curr.pos > tk.pos):
        p.parseAttributes(result.attributes, tk)
    else: discard
  
  # parse inline elements
  case p.curr.kind
  of tkColon:
    walk p
    let valNode = p.parseExpression()
    caseNotNil valNode:
      result.childElements.add(valNode)
  of tkString:
    # parse a string value and add it as a child element
    let strNode: Node = p.parseString() 
    result.childElements.add(strNode)  
  # of tkString, tkIdentVar:
  #   if p.curr.line == result.ln:
  #     let valNode = p.parseExpression()
  #     caseNotNil valNode:
  #       result.childElements.add(valNode)
  of tkGT:
    # parse inline HTML tags
    var node: Node
    while p.curr is tkGT:
      inc p.lvl
      case p.next.kind
      of tkIdentifier:
        walk p
        p.curr.pos = p.lvl
        node = p.parseElement()
        caseNotNil node:
          if p.curr isnot tkEOF and p.curr.pos > 0:
            if p.curr.line > node.ln:
              let currentParent = p.parentNode[^1]
              while p.curr.pos > (currentParent.col - 1):
                if p.curr is tkEOF: break
                var subNode = p.parseStmt()
                caseNotNil subNode:
                  node.childElements.add(subNode)
                if p.curr.pos < (currentParent.col - 1):
                  try:
                    dec p.lvl, (currentParent.col - 1) div p.curr.pos
                  except DivByZeroDefect:
                    discard
                  delete(p.parentNode, p.parentNode.high)
                  break
          result.childElements.add(node)
          if p.lvl != 0:
            dec p.lvl
          return result
      of tkAt:
        walk p
        let blockNode: Node = p.parseBlockCall()
        caseNotNil blockNode:
          result.childElements.add(blockNode)
      else: return
  else: discard
  
  # parse multi-line nested nodes
  if p.curr isnot tkEOF:
    var currentParent = p.parentNode[^1]
    if p.curr.line > currentParent.ln:
      if p.curr.pos > (currentParent.col - 1):
        inc p.lvl
        while p.curr.pos > (currentParent.col - 1):
          if p.curr is tkEOF: break
          var subNode = p.parseStmt()
          caseNotNil subNode:
            add result.childElements, subNode
          if p.curr is tkEOF or p.curr.pos == 0: break # prevent division by zero
          if p.curr.pos < (currentParent.col - 1):
            dec p.lvl
            delete(p.parentNode, p.parentNode.high)
            break
          elif p.curr.pos == (currentParent.col - 1):
            dec p.lvl
        if p.curr.pos == 0:
          p.lvl = 0 # reset level

proc parseBlock(p: var Parser, indentPos = 0,
            parseFnBlock: static bool = false): Node {.rule.} =
  # parse a block of code
  var
    closingBlock: bool
    stmts = newSeq[Node](0)
  if p.curr is tkLC:
    closingBlock = true
    walk p # tkLC
  elif p.curr is (
      when parseFnBlock == true: tkAssign
                else: tkColon
      ): walk p
  while p.curr isnot tkEOF:
    if closingBlock and p.curr is tkRC:
      walk p; break
    elif p.curr.pos <= indentPos: break
    let subNode = p.parseStmt()
    caseNotNil subNode:
      stmts.add(subNode)
  result = ast.newTree(nkBlock, stmts)

prefixHandle parseForLoop:
  # parse a for loop
  let tokenFor: TokenTuple = p.curr
  if p.next.kind == tkIdentVar:
    walk p # tkFor
    let itemVar: Node = ast.newIdent(p.curr.value)
    walk p
    expectWalk(tkIN)
    let iterExpr: Node = p.parseExpression() 
    caseNotNil iterExpr:
      let body: Node = p.parseBlock(tokenFor.pos)
      caseNotNil body:
        result = ast.newTree(nkFor, itemVar, iterExpr, body)

prefixHandle parseWhileLoop:
  # parse a while loop
  let tokenWhile: TokenTuple = p.curr
  walk p # tkWhile
  let whileExpr: Node = p.parseExpression()
  caseNotNil whileExpr:
    let whileBlock: Node = p.parseBlock(tokenWhile.pos)
    caseNotNil whileBlock:
      result = ast.newTree(nkWhile, whileExpr, whileBlock)

prefixHandle parseIf:
  # parse an if/elif/else statement
  let tokenIf: TokenTuple = p.curr
  walk p # tkIf
  let ifExpr: Node = p.parseExpression()
  caseNotNil ifExpr:
    var children = @[ifExpr]
    let ifBlock: Node = p.parseBlock(tokenIf.pos)
    caseNotNil ifBlock:
      children.add(ifBlock)
    
    # handle elif statements
    while p.curr is tkELIF:
      # if p.curr.pos != tokenIf.pos: break # todo error
      let tokenElif = p.curr
      walk p # tkELIF
      let elifExpr: Node = p.parseExpression()
      caseNotNil elifExpr:
        let elifBlock: Node = p.parseBlock(tokenIf.pos)
        caseNotNil elifBlock:
          children.add(@[elifExpr, elifBlock])
    # handle else statement, if available
    if p.curr is tkELSE:
      let tokenElse = p.curr
      walk p # tkELSE
      let elseBlock: Node = p.parseBlock(tokenIf.pos)
      caseNotNil elseBlock:
        children.add(elseBlock)
    result = ast.newTree(nkIf, children)

prefixHandle parseStaticStmt:
  # parse a statement inside a `static` block
  result = ast.newNode(nkStatic)
  walk p # tkStatic
  p.curr.pos = 0
  let stmtNode: Node = p.parseStmt()
  caseNotNil stmtNode:
    result.add(stmtNode)
  # debugEcho result

prefixHandle parseIdent:
  # parse an identifier
  result = ast.newIdent(p.curr.value)
  walk p # tkIdentifier

prefixHandle parseIdentVar:
  # parse a variable identifier.
  result = ast.newIdent(p.curr.value)
  walk p # tkIdentVar
  # if p.curr.line == result.ln and p.curr.wsno == 0:
  #   case p.curr.kind
  #   of tkLB:
  #   else: break

prefixHandle parseType:
  if p.curr is tkIdentifier:
    return parseIdent(p)

prefixHandle parseJavaScript:
  result = ast.newNode(nkJavaScriptSnippet)
  result.snippetCode = p.curr.value
  for attr in p.curr.attr:
    let identNode = ast.newNode(nkIdent)
    let id = attr.split("_")
    identNode.ident = id[1]
    add result.snippetCodeAttrs, (attr, identNode)
  walk p


#
# Identifier & Variable Definitions
#
proc parseGenericType(p: var Parser, lhs: Node): Node =
  walk p # tkLB
  let genericType = p.parseIdent()
  caseNotNil genericType:
    result = ast.newNode(nkIndex).add(lhs)
    result.add(genericType)
    if p.curr is tkLB:
      result = p.parseGenericType(result)
    expectWalk(tkRB) # expect a right bracket

proc getVarIdent(p: var Parser, varIdent: bool): Node {.rule.} =
  # get the identifier name from the current token
  result = ast.newIdent(p.curr.value)
  walk p # tkIdentifier
  if varIdent:
    # variable definitions can be suffixed with an asterisk
    # to mark them as exported (public)
    if p.curr is tkAsterisk:
      walk p # tkAsterisk
      result = ast.newNode(nkPostfix).add([ast.newIdent("*"), result])

proc parseIdentDefs(p: var Parser, varIdent = true): Node {.rule.} =
  # parse identifier definitions
  result = newNode(nkIdentDefs)
  if p.curr.kind == tkIdentifier:
    result.add(p.getVarIdent(varIdent))
    var
      ty = newEmpty()
      value = newEmpty()
    # parse a type definition
    if p.curr is tkColon:
      walk p # tkColon
      if p.curr is tkIdentifier:
        ty = p.parseIdent()
        if p.curr is tkLB:
          ty = p.parseGenericType(ty)
      elif p.curr is tkVar:
        ty = ast.newNode(nkVarTy)
        if p.next is tkIdentifier:
          ty.varType = ast.newIdent(p.next.value)
          walk p, 2
    # parse an implicit assignment
    if p.curr.kind == tkAssign:
      walk p # tkAssign
      value = p.parseExpression()
    result.add([ty, value])

prefixHandle parseVar:
  # parse a variable definition
  case p.curr.kind
  of tkVar:
    result = ast.newNode(nkVar)
  of tkConst:
    result = ast.newNode(nkConst)
  else: discard
  walk p # tkVar/tkConst
  result.add(p.parseIdentDefs(true))

#
# Functions
#
proc parseFunctionHead(p: var Parser, isAnon: bool;
                name, genericParams, formalParams: var Node) =
  if not isAnon:
    name = ast.newIdent(p.curr.value)
    walk p
    if p.curr is tkAsterisk:
      # suffixed with an asterisk marks the function as exported (public)
      walk p # tkAsterisk
      name = ast.newNode(nkPostfix).add([ast.newIdent("*"), name])
  else:
    name = ast.newEmpty()
  
  if p.curr is tkLB:
    # parse generic parameters
    genericParams = ast.newNode(nkGenericParams)
    var params: seq[Node]
    if p.parseCommaIdentList(tkLB, tkRB, params):
      genericParams.add(params)
  else:
    genericParams = ast.newEmpty() # no generic parameters, use an empty node
  
  # parse function parameters
  # `formalParams` is a list of parameters
  formalParams = newTree(nkFormalParams, newEmpty())
  if p.curr is tkLP:
    var params: seq[Node]
    if p.parseCommaIdentList(tkLP, tkRP, params):
      formalParams.add(params)

  # parse a return type
  if p.curr is tkColon and p.next is tkIdentifier:
    walk p # tkColon
    formalParams[0] = p.parseIdent()

prefixHandle parseFunction:
  # parse a function definition
  let fnpos = p.curr.pos
  walk p # tkFunction
  var name, genericParams, formalParams: Node
  let isAnon = p.curr.kind != tkIdentifier
  parseFunctionHead(p, isAnon, name, genericParams, formalParams)
  if p.curr in {tkAssign, tkLC}:
    # parse function statement
    let fnBlock: Node = p.parseBlock(fnpos, parseFnBlock = true)
    caseNotNil fnBlock:
      result = ast.newTree(nkProc, name, genericParams, formalParams, fnBlock)
  # debugEcho result

prefixHandle parseIterator:
  # parse an iterator
  let tokenIterator = p.curr.pos
  walk p # tkIterator
  var name, genericParams, formalParams: Node
  parseFunctionHead(p, isAnon = false, name, genericParams, formalParams)
  if p.curr in {tkAssign, tkLC}:
    # parse function statement
    let fnBlock: Node = p.parseBlock(tokenIterator, parseFnBlock = true)
    caseNotNil fnBlock:
      result = ast.newTree(nkIterator, name, genericParams, formalParams, fnBlock)

#
# Block Functions
#
proc parseMacroFunctionHead(p: var Parser, isAnon: bool;
    name, genericParams, formalParams: var Node) =
  # parse a block function head
  if not isAnon:
    name = ast.newIdent("@" & p.curr.value)
    walk p # tkIdentifier
    if p.curr is tkAsterisk:
      # suffixed with an asterisk marks the function as exported (public)
      walk p # tkAsterisk
      name = ast.newNode(nkPostfix).add([ast.newIdent("*"), name])
  else:
    name = ast.newEmpty()
  genericParams = ast.newEmpty() # todo
  formalParams = newTree(nkFormalParams, newEmpty())
  if p.curr is tkLP:
    var params: seq[Node]
    if p.parseCommaIdentList(tkLP, tkRP, params):
      # @block functions instantiate with a default
      # parameter type of `stmt` which allows for
      # any statement to be passed (including other functions and block calls)
      # let stmtp = newNode(nkIdentDefs)
      # stmtp.add(ast.newIdent"stmt")
      # stmtp.add([ast.newIdent"any", defaultNil])
      # params.add(stmtp)
      formalParams.add(params)  

prefixHandle parseMacroFunction:
  # parse a block function
  let fnpos = p.curr.pos
  walk p # tkFunction
  var name, genericParams, formalParams: Node
  let isAnon = p.curr.kind != tkIdentifier
  parseMacroFunctionHead(p, isAnon, name, genericParams, formalParams)
  if p.curr in {tkAssign, tkLC}:
    # parse function statement
    let fnBlock: Node = p.parseBlock(fnpos, parseFnBlock = true)
    caseNotNil fnBlock:
      result = ast.newTree(nkMacro, name, genericParams, formalParams, fnBlock)  

prefixHandle parseBlockCall:
  # parse a block call
  let tokenAt = p.curr
  walk p # tkAt
  if p.curr is tkIdentifier:
    p.curr.value = "@" & p.curr.value

    result = ast.newCall(ast.newIdent(p.curr.value))
    var expectRP: bool
    walk p # tkIdentifier
    
    var attrs: seq[Node]
    p.parseAttributes(attrs, tokenAt)
    
    if p.curr.kind == tkLP:
      # parse function arguments wrapped in parentheses
      # and mark expectRP as true to expect a closing parenthesis
      expectRP = true
      walk p # tkLP
    elif p.curr.pos <= tokenAt.pos: return # result

    # parse arguments separated by comma
    while true:
      case p.curr.kind
      of tkComma:
        walk p # skip to next argument
      of tkRP:
        if expectRP:
          walk p # the end of comma separated arg list
          if p.curr.pos > tokenAt.pos:
            continue
        break
      of Assignables + {tkIdentVar}:
        if not expectRP and p.curr.pos <= tokenAt.pos: break
        let arg = p.parseExpression()
        caseNotNil arg:
          result.add(arg)
      else: break # nothing to add

prefixHandle parseCall:
  # parse a function call
  result = ast.newCall(ast.newIdent(p.curr.value))
  var expectRP: bool
  walk p # tkIdentifier
  
  if p.curr.kind == tkLP:
    # parse function arguments wrapped in parentheses
    # and mark expectRP as true to expect a closing parenthesis
    expectRP = true
    walk p # tkLP
  if p.curr isnot tkRP:
    while true:
      let arg = p.parseExpression()
      caseNotNil arg:
        result.add(arg)
      case p.curr.kind
      of tkComma:
        walk p # skip to next argument
      of tkRP:
        if expectRP:
          walk p # tkRP
        break
      of tkEOF:
        break # todo error EOF before closing parenthesis
      else: break
  else: walk p # tkRP
    
prefixHandle parseArray:
  # parse an array storage
  result = ast.newTree(nkArray)
  discard p.parseCommaList(tkLB, tkRB, result.children)
  p.walkOpt(tkSColon)

prefixHandle parseObjectStorage:
  # parse an object storage
  result = ast.newTree(nkObject)
  discard p.parseCommaList(tkLC, tkRC, result.children, infixList = true)

prefixHandle parseParExpr:
  # parse a parenthesized expression
  walk p # tkLP
  result = p.parseExpression()
  expectWalk(tkRP) # expect a right parenthesis

prefixHandle parseBreak:
  # parse a break command
  result = ast.newTree(nkBreak)
  walk p # tkBreakCmd
  p.walkOpt(tkSColon)

prefixHandle parseReturn:
  # parse a return statement
  result = ast.newTree(nkReturn)
  walk p # tkReturn
  let exprNode: Node = p.parseExpression()
  caseNotNil exprNode:
    result.add(exprNode)
    p.walkOpt(tkSColon)

prefixHandle parseYield:
  # parse a yield statement
  result = ast.newTree(nkYield)
  walk p # tkYield
  let exprNode: Node = p.parseExpression()
  caseNotNil exprNode:
    result.add(exprNode)
    p.walkOpt(tkSColon) # optional semicolon

prefixHandle parseEcho:
  # parse an echo statement
  result = ast.newTree(nkCall)
  result.add(ast.newIdent("echo"))
  walk p # tkEcho
  let exprNode: Node = p.parseExpression()
  caseNotNil exprNode:
    result.add(exprNode)
    p.walkOpt(tkSColon) # optional semicolon

prefixHandle parseObject:
  # parse an object
  result = ast.newTree(nkObject)
  if p.next is tkIdentifier:
    walk p # tkLitObject
    let objectIdent = ast.newIdent(p.curr.value)
    walk p # tkIdentifier
    expectWalk(tkLC) # expect a left curly brace
    # add the object identifier to the result
    # the empty node is used to define generic
    # parameters (todo)
    result.add([objectIdent, ast.newEmpty()])
    # parse the object fields
    var fields = newNode(nkRecFields)
    while true:
      case p.curr.kind
      of tkEOF: break
      of tkRC:
        walk p; break # end of the object
      of tkIdentifier, tkString:
        # parse a field name. it can be either a string or an identifier
        # let fieldName = p.curr
        # walk p # tkIdentifier/tkString
        # expectWalk(tkColon)
        # parse the field value
        let kvNode: Node = p.parseIdentDefs()
        caseNotNil kvNode:
          fields.add(kvNode)
        if p.curr is tkComma and p.next isnot tkRC:
          walk p # tkComma
      else: break # todo error
    result.add(fields)

proc getPrefixFn(p: var Parser): PrefixFunction =
  # Get the prefix function for the current token
  # This is used to parse the current token
  # and return the corresponding node
  result = 
    case p.curr.kind
    of tkBool: parseBoolean
    of tkInteger: parseInteger
    of tkFloat: parseFloat
    of tkString: parseString
    of tkIdentVar: parseIdentVar
    of tkIf: parseIf
    of tkLitObject: parseObject
    of tkIdentifier, tkType:
      # if p.next.line == p.curr.line and p.next in Assignables + {tkIdentVar, tkType}:
      #   parseCall
      if p.next.line == p.curr.line and p.next is tkLP:
        parseCall
      else: parseIdent
    of tkAt: parseBlockCall
    of tkLP:  parseParExpr
    of tkWhile: parseWhileLoop
    of tkFor: parseForLoop
    of tkReturnCmd: parseReturn
    of tkBreakCmd: parseBreak
    of tkFunc, tkFn: parseFunction
    of tkIterator: parseIterator
    of tkImport, tkInclude: parseImportStmt
    of tkLB: parseArray
    of tkLC: parseObjectStorage
    of tkSnippetJs: parseJavaScript
    of tkYield: parseYield
    of tkEcho: parseEcho
    else: nil

proc parsePrefix(p: var Parser): Node =
  let parseFn = p.getPrefixFn()
  if parseFn != nil: 
    return parseFn(p)

#
# Infix Handlers
#
const infixTokenTable ={
  tkPlus: "+",
  tkMinus: "-",
  tkAsterisk: "*",
  tkDivide: "/",
  tkGT: ">",
  tkGTE: ">=",
  tkLT: "<",
  
  tkLTE: "<=",
  tkEQ: "==",
  tkNE: "!=",
  tkAmp: "&",
  tkAssign: "=",
  tkDot: ".",
  # tkColon: ":"
  tkLB: "["
}.toTable

const logicalOperators = {
  tkAnd: "and",
  tkAndAnd: "&&",
  tkOr: "or",
  tkOrOr: "||"  
}.toTable

proc parseInfix(p: var Parser, lhs: Node): Node {.rule.} =
  # parse an infix expression
  let op = p.curr
  walk p # operator token
  case op.kind
  of MathOperators, {tkEQ, tkNE, tkGT, tkGTE, tkLT, tkLTE} + {tkAmp}:
    # parse math and comparison operators
    let opLit = infixTokenTable[op.kind]
    let rhs: Node = p.parseExpression()
    caseNotNil rhs:
      return ast.newInfix(ast.newIdent(opLit), lhs, rhs)
  of LogicalOperators:
    # parse logical operators
    assert lhs.kind == nkInfix
    let rhs: Node = p.parseExpression()
    caseNotNil rhs:
      let opLit = logicalOperators[op.kind]
      return ast.newInfix(ast.newIdent(opLit), lhs, rhs)
  of tkAssign:
    # parse an assignment expression
    assert lhs.kind == nkIdent
    let rhs: Node = p.parseExpression()
    caseNotNil rhs:
      return ast.newInfix(ast.newIdent("="), lhs, rhs)
  of tkDot:
    # parse a dot-access expression
    if p.curr is tkDot and p.curr.wsno == 0:
      walk p
      let rhs = p.parseExpression()
      caseNotNil rhs:
        return ast.newCall(ast.newIdent"..", lhs, rhs)
    let opLit = infixTokenTable[op.kind]
    let rhs = p.parseExpression()
    caseNotNil rhs:
      return newTree(nkDot, lhs, rhs)
  of tkLB:
    # parse a bracket access expression
    # assert lhs.kind in {nkIdent, nkInfix}
    let indexNode: Node = p.parseExpression()
    caseNotNil indexNode:
      result = ast.newNode(nkBracket)
      result.add([lhs, indexNode])
      expectWalk(tkRB) # expect a right bracket
      case p.curr.kind
      of tkLB:
        if likely(p.curr.line == indexNode.ln and p.curr.wsno == 0):
          return p.parseInfix(result)
      else:
        if infixTokenTable.hasKey(p.curr.kind):
          # if the next token is an infix operator, parse it
          # as an infix expression
          return p.parseInfix(result)
  else: discard # returns nil

proc parseExpression(p: var Parser): Node =
  # parse an expression and return
  # the corresponding node
  let lhs = p.parsePrefix()
  caseNotNil lhs:
    if infixTokenTable.hasKey(p.curr.kind):
      result = p.parseInfix(lhs)
      caseNotNil result:
        if p.curr in LogicalOperators:
          result = p.parseInfix(result)
        return # result
    return lhs

proc parseStmt(p: var Parser): Node =
  # Parse a statement node
  let prefixFn: PrefixFunction = 
    case p.curr.kind
    of tkIdentifier, tkType:
      # if p.next.line == p.curr.line and p.next in Assignables + {tkIdentVar, tkType}:
      #   parseCall
      if p.next.line == p.curr.line and p.next is tkLP:
        parseCall
      else: parseElement
    of tkAt:
      parseBlockCall
    of tkVar, tkConst: parseVar
    of tkIf: parseIf
    of tkWhile: parseWhileLoop
    of tkFor: parseForLoop
    of tkImport, tkInclude: parseImportStmt
    of tkSnippetJs: parseJavaScript
    of tkFunc, tkFn: parseFunction
    of tkMacro: parseMacroFunction
    of tkIterator: parseIterator
    of tkStatic: parseStaticStmt
    of tkEcho: parseEcho
    else: parseExpression
  if prefixFn != nil:
    return prefixFn(p)

proc parseScript*(astProgram: var Ast, code: string) =
  var p = Parser(lex: newLexer(code, allowMultilineStrings = true))
  defer: p.lex.close()
  p.curr = p.lex.getToken()
  p.next = p.lex.getToken()
  p.skipComments()
  astProgram = Ast()
  while p.curr.kind != tkEOF:
    let node: Node = p.parseStmt()
    caseNotNil node:
      astProgram.nodes.add(node)
    do:
      echo "Unexpected token: ", p.curr.kind, " at ", p.curr.pos
      break
