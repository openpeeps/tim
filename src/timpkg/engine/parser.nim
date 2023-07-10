# A high-performance compiled template engine
# inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, json]
from pkg/nyml import yaml, toJsonStr
import pkg/jsony

import ./tokens, ./ast
from resolver import resolve, hasError, getError,
          getErrorLine, getErrorColumn, getFullCode

from meta import TimEngine, Template, TemplateType
from std/strutils import `%`, isDigit, join, endsWith, Newlines,
                            split, parseInt, parseBool, parseFloat

type
  Parser* = ref object
    lvl: int
    engine: TimEngine
    lexer: Lexer
    filePath: string
    includes: seq[string]
    prev, curr, next: TokenTuple
    parentNode: seq[Node]
    statements: Program
    enableJit: bool
    hasView: bool
    error: string
    templateType: TemplateType
    ids: TableRef[string, int]

  PrefixFunction = proc(p: var Parser): Node
  # InfixFunction = proc(p: var Parser, left: Node): Node

const
  InvalidIndentation = "Invalid indentation"
  DuplicateClassName = "Duplicate class entry \"$1\""
  InvalidAttributeId = "Invalid ID attribute"
  DuplicateAttrId = "Duplicate ID entry \"$1\""
  InvalidAttributeValue = "Missing value for \"$1\" attribute"
  InvalidClassAttribute = "Invalid class name"
  DuplicateAttributeKey = "Duplicate attribute name for \"$1\""
  InvalidTextNodeAssignment = "Expect text assignment for \"$1\" node"
  UndeclaredVariable = "Undeclared variable \"$1\""
  InvalidIterationMissingVar = "Invalid iteration missing variable identifier"
  InvalidIteration = "Invalid iteration"
  InvalidConditionalStmt = "Invalid conditional statement"
  InvalidInlineNest = "Invalid inline nest missing `>`"
  InvalidNestDeclaration = "Invalid nest declaration"
  InvalidValueAssignment = "Expected value after `:` assignment operator"
  InvalidHTMLElementName = "Invalid HTMLElement name \"$1\""
  InvalidMixinDefinition = "Invalid mixin definition \"$1\""
  InvalidStringConcat = "Invalid string concatenation"
  InvalidVarDeclaration = "Invalid variable declaration"
  InvalidArrayIndex = "Invalid array access missing index"
  InvalidAccessorDeclaration = "Invalid accessor declaration"
  InvalidScopeVarContext = "Invalid usage of $this in this context"
  InvalidGlobalVarContext = "Invalid usage of $app in this context"
  NestableStmtIndentation = "Nestable statement requires indentation"
  TypeMismatch = "Type mismatch: x is type of $1 but y: $2"
  InvalidIDNotUnique = "The ID \"$1\" is also used for another element at line $2"
  InvalidJavaScript = "Invalid JavaScript snippet"
  InvalidImportView = "Trying to load a view inside a $1"
  InvalidStringInterpolation = "Invalid string interpolation"
  DuplicateViewLoader = "Cannot render more than one `@view`. Use `@include` instead"

const
  tkVars = {tkVariable, tkSafevariable}
  tkCallables = {tkCall}
  tkAssignables = {tkString, tkInteger, tkBool} + tkVars
  tkComparables = tkAssignables + tkCallables
  tkOperators = {tkEq, tkNe, tkLt, tkLte, tkGt, tkGte}
  tkConditionals = {tkIf, tkElif, tkElse, tkIn, tkOr, tkAnd}
  tkLoops = {tkFor, tkIn}
  tkCalc = {tkPlus, tkMinus, tkDivide, tkMulti}
  tkCallSet = {tkInclude, tkMixin}
  tkNone = (tkNone, "", 0,0,0,0)
  tkSpecial = {tkDot, tkColon, tkLC, tkRC,
          tkLP, tkRP, tkId, tkAssign, tkComma,
          tkAt, tkNot, tkAmp} + tkCalc + tkOperators + tkLoops
  svgscTags = {
    tkSvg_path, tkSvg_circle, tkSvg_polyline, tkSvg_animate,
    tkSvg_animatetransform, tkSvg_animatemotion,
    tkSvg_fe_blend, tkSvg_fe_colormatrix, tkSvg_fe_composite,
    tkSvg_fe_convolvematrix, tkSvg_fe_displacementmap
  }
  scTags = {
    tkArea, tkBase, tkBr, tkCol, tkEmbed,
    tkHr, tkImg, tkInput, tkLink, tkMeta,
    tkParam, tkSource, tkTrack, tkWbr} + svgscTags

  tkHtml = {
    tkA, tkAbbr, tkAcronym, tkAddress, tkApplet, tkArea, tkArticle, tkAside,
    tkAudio, tkBold, tkBase, tkBasefont, tkBdi, tkBdo, tkBig, tkBlockquote,
    tkBody, tkBr, tkButton, tkCanvas, tkCaption, tkCenter, tkCite, tkCode,
    tkCol, tkColgroup, tkData, tkData, tkDatalist, tkDd, tkDel, tkDetails,
    tkDfn, tkDialog, tkDir, tkDoctype, tkDl, tkDt, tkEm, tkEmbed, tkFieldset,
    tkFigcaption, tkFigure, tkFont, tkFooter, tkH1, tkH2, tkH3, tkH4, tkH5, tkH6,
    tkHead, tkHeader, tkHr, tkHtml, tkItalic, tkIframe, tkImg, tkInput, tkIns,
    tkKbd, tkLabel, tkLegend, tkLi, tkLink, tkMain, tkMap, tkMark, tkMeter,
    tkNav, tkNoframes, tkNoscript, tkObject, tkOl, tkOptgroup, tkOption, tkOutput,
    tkParagraph, tkParam, tkPre, tkProgress, tkQuotation, tkRp, tkRt, tkRuby, tkStrike,
    tkSamp, tkSection, tkSelect, tkSmall, tkSource, tkSpan, tkStrike_long, tkStrong,
    tkStyle, tkSub, tkSummary, tkSup, tkTable, tkTbody, tkTd, tkTemplate,
    tkTextarea, tkTfoot, tkTh, tkThead, tkTime, tkTitle, tkTr, tkTrack, tkTt, tkUnderline,
    tkUl, tkVar, tkVideo, tkWbr
  }

template setError(p: var Parser, msg: string, breakStmt: bool) =
  ## Set parser error
  p.error = "Error ($2:$3): $1\n$4" % [msg, $p.curr.line, $p.curr.pos, p.filePath]
  break

template setError(p: var Parser, msg: string) =
  ## Set parser error
  p.error = "Error ($2:$3): $1" % [msg, $p.curr.line, $p.curr.pos]

proc setError(p: var Parser, msg: string, line, col: int, breakStmt = false) =
  ## Set a parser error using a specific line/pos number
  p.error = "Error ($2:$3): $1" % [msg, $line, $col]

proc hasError*(p: var Parser): bool =
  ## Determine if current parser instance has any errors
  result = p.error.len != 0 or p.lexer.hasError()

proc getError*(p: var Parser): string = 
  ## Retrieve current parser instance errors,
  ## including lexer-side unrecognized token errors
  if p.lexer.hasError():
    result = p.lexer.getError()
  elif p.error.len != 0:
    result = p.error

proc isHTMLElement(token: TokenKind): bool =
  result = token notin tkComparables + tkOperators +
             tkConditionals + tkCalc + tkCallSet +
             tkLoops + {tkEof}

proc parse*(engine: TimEngine, code, path: string,
      templateType: TemplateType): Parser

proc getStatements*(p: Parser, asNodes = true): Program =
  ## Return all HtmlNodes available in current document
  result = p.statements

proc getStatementsStr*(p: Parser, prettyString, prettyPlain = false): string = 
  ## Retrieve all HtmlNodes available in current document as stringified JSON
  # if prettyString or prettyPlain: 
    # return pretty(toJson(p.getStatements()))
  result = toJson(p.statements)

template jit(p: var Parser) =
  ## Enable jit flag When current document contains
  ## either conditionals, or variable assignments
  if p.enableJit == false:
    p.enableJit = true

proc hasJIT*(p: var Parser): bool {.inline.} =
  ## Determine if current timl template
  ## requires a JIT compilation
  result = p.enableJit == true

proc walk(p: var Parser, offset = 1) =
  var i = 0
  while offset != i:
    p.prev = p.curr
    p.curr = p.next
    p.next = p.lexer.getToken()
    inc i

proc getOperator(tk: TokenKind): OperatorType =
  case tk:
    of tkEq: result = EQ
    of tkNe: result = NE
    of tkLt: result = LT
    of tkLte: result = LTE
    of tkGt: result = GT
    of tkGte: result = GTE
    of tkAnd: result = AND
    of tkAmp: result  = AMP
    else: discard

# prefix / infix handlers
proc parseExpressionStmt(p: var Parser): Node
proc parseStatement(p: var Parser): Node
proc parseExpression(p: var Parser, exclude: set[NodeType] = {}): Node
proc parseInfix(p: var Parser, strict = false): Node
proc parseIfStmt(p: var Parser): Node
proc parseForStmt(p: var Parser): Node
proc parseCall(p: var Parser): Node
proc getPrefixFn(p: var Parser, kind: TokenKind): PrefixFunction
# proc getInfixFn(kind: TokenKind): InfixFunction

proc isGlobalVar(tk: TokenTuple): bool = tk.value == "app"
proc isScopeVar(tk: TokenTuple): bool = tk.value == "this"

proc parseInteger(p: var Parser): Node =
  # Parse a new `integer` node
  result = ast.newInt(parseInt(p.curr.value), p.curr)
  walk p

proc parseBoolean(p: var Parser): Node =
  # Parse a new `boolean` node
  result = ast.newBool(parseBool(p.curr.value))
  walk p

template handleConcat() =
  while p.curr.kind == tkAmp:
    if p.next.kind notin {tkString, tkVariable, tkSafevariable}:
      p.setError(InvalidStringConcat)
      return nil
    walk p
    let infixRight: Node = p.parseExpression()
    if result == nil:
      result = ast.newInfix(leftNode, infixRight, getOperator(tkAmp))
    else:
      result = ast.newInfix(result, infixRight, getOperator(tkAmp))

proc parseString(p: var Parser): Node =
  # Parse a new `string` node
  if p.hasError(): return
  var concated: bool
  let this = p.curr
  if p.next.kind == tkAmp:
    concated = true
    walk p
    var leftNode = ast.newString(this)
    handleConcat()
    if result == nil:
      result = leftNode
  if not concated:
    result = ast.newString(this)
    walk p

proc parseVariable(p: var Parser): Node =
  # Parse variables. Includes support for multi-accessor
  # fields using dot notation for objects, while for array access
  # by referring to the index number of the item using square brackets
  var
    leftNode: Node
    varVisibility: VarVisibility
    this = p.curr
    accessors: seq[Node]
  if p.curr.isGlobalVar(): 
    walk p
    varVisibility = VarVisibility.GlobalVar
  elif p.curr.isScopeVar():
    varVisibility = VarVisibility.ScopeVar
    walk p
  else:
    varVisibility = VarVisibility.InternalVar
  if p.curr.kind in {tkDot, tkLB}:
    walk p
  if p.curr.kind == tkIdentifier or p.curr.kind notin tkSpecial and p.curr.kind != tkEof:
    this = p.curr
    walk p
    while true:
      if p.curr.kind == tkEof: break
      # if p.curr.wsno != 0 or p.curr.line != this.line:
      #     p.setError(InvalidAccessorDeclaration, true)
      if p.curr.kind == tkDot:
        walk p # .
        if p.curr.kind == tkIdentifier or p.curr.kind notin tkSpecial:
          accessors.add newString(p.curr)
          walk p # .
          if p.curr.wsno != 0: break
        else: p.setError(InvalidVarDeclaration, true)
      elif p.curr.kind == tkLB:
        if p.next.kind != tkInteger:
          p.setError(InvalidArrayIndex, true)
        walk p # [
        if p.next.kind != tkRB:
          p.setError(InvalidAccessorDeclaration, true)
        accessors.add(p.parseInteger())
        walk p # ]
        if p.curr.wsno != 0: break
      else: break
  else:
    case varVisibility:
    of VarVisibility.GlobalVar:
      p.setError(InvalidGlobalVarContext)
    of VarVisibility.ScopeVar:
      p.setError(InvalidScopeVarContext)
    else: discard

  if p.hasError:
    return # TODO handle error to avoid attempt to read from nil

  leftNode = newVariable(
    this,
    dataStorage = (varVisibility in {GlobalVar, ScopeVar}),
    varVisibility = varVisibility
  )
  leftNode.accessors = accessors
  if p.curr.kind == tkAmp: # support infix concatenation X & Y
    handleConcat()
  if result == nil:
    result = leftNode
  jit p

proc parseSafeVariable(p: var Parser): Node =
  result = newVariable(p.curr, isSafeVar = true)
  walk p
  jit p

template inHtmlAttributeNames(): untyped =
  (
    p.curr.kind in {
      tkString, tkVariable, tkSafevariable,
      tkIdentifier, tkIf, tkFor, tkElif, tkElse,
      tkOr, tkIn} + tkHtml and p.next.kind == tkAssign
  )

proc getHtmlAttributes(p: var Parser): HtmlAttributes =
  # Parse all attributes and return it as a
  # `TableRef[string, seq[string]]`
  while true:
    if p.curr.kind == tkDot:
      # Add `class=""` attribute
      let attrKey = "class"
      if p.next.kind notin tkSpecial:
        if result.hasKey(attrKey):
          # if p.next.value notin result[attrKey]:
          # p.setError DuplicateClassName % [p.next.value], true
          result[attrKey].add(newString(p.next))
        else:
          result[attrKey] = @[newString(p.next)]
        walk p, 2
        while p.curr.kind == tkLC and p.next.kind == tkVariable:
          # parse string interpolation
          walk p
          result[attrKey][^1].sConcat.add(p.parseVariable())
          if p.curr.kind == tkRC:
            walk p
          else: p.setError(InvalidStringInterpolation, true)
      else:
        p.setError(InvalidClassAttribute)
        walk p
        break
    elif p.curr.kind == tkId:
      # Set `id=""` HTML attribute
      let attrKey = "id"
      if not result.hasKey(attrKey):
        if p.next.kind notin tkSpecial:
          walk p
          if p.curr.kind in {tkVariable, tkSafevariable}:
            result[attrKey] = @[p.parseVariable()]
          else:
            if p.ids.hasKey(p.curr.value):
              p.setError InvalidIDNotUnique % [p.curr.value, $(p.ids[p.curr.value])], true
            let attrValue = newString(p.curr)
            result[attrKey] = @[attrValue]
            p.ids[p.curr.value] = attrValue.meta.line
            walk p
        else: p.setError InvalidAttributeId, true
      else: p.setError DuplicateAttrId % [p.next.value], true
    elif inHtmlAttributeNames:
      let attrName = p.curr.value
      walk p
      if p.next.kind notin {tkString, tkVariable, tkSafevariable}:
        p.setError InvalidAttributeValue % [attrName], true
      if not result.hasKey(attrName):
        walk p
        if p.curr.kind == tkString:
          if attrName == "id":
            if p.ids.hasKey(p.curr.value):
              p.setError InvalidIDNotUnique % [p.curr.value, $(p.ids[p.curr.value])], true
          let attrValue = newString(p.curr)
          result[attrName] = @[attrValue]
          if attrName == "id":
            p.ids[p.curr.value] = attrValue.meta.line
          walk p
        else:
          result[attrName] = @[p.parseVariable()]
      else:
        p.setError DuplicateAttributeKey % [attrName], true
      # if p.curr.line > p.prev.line or p.curr.kind == tkGt:
      #   break
      if p.curr.kind == tkGt:
        break
    elif p.curr.kind == tkLP:
      # parse short hand conditional statement
      let this = p.curr
      let infixNode = p.parseInfix()
      if p.curr.kind == tkSif:
        walk p # ?
        var ifBody = p.getHtmlAttributes()
        if p.curr.kind != tkRP:
          p.setError(InvalidConditionalStmt, true)
        walk p # )
        let astNode = newShortIfExpression((infixNode, ifBody), this) 
        let condKey = "%_$1$2$3$4" % [$astNode.meta.line, $astNode.meta.pos,
                                      $astNode.meta.col, $astNode.meta.wsno]
        result[condKey] = @[astNode]
        jit p
      else:
        p.setError(InvalidConditionalStmt, true)
    elif p.curr.kind notin tkSpecial and p.prev.line == p.curr.line:
      let attrName = p.curr.value
      if not result.hasKey(attrName):
        result[attrName] = @[]
        walk p
      else:
        p.setError DuplicateAttributeKey % [attrName], true
    else: break

proc newHtmlNode(p: var Parser): Node =
  var isSelfClosingTag = p.curr.kind in scTags
  result = ast.newHtmlElement(p.curr)
  result.issctag = isSelfClosingTag
  walk p
  if result.meta.pos != 0:
    result.meta.pos = p.lvl * 4 # set real indentation size
  while true:
    if p.hasError(): return nil
    if p.curr.kind == tkColon:
      walk p
      if p.curr.kind == tkString:
        result.nodes.add p.parseString()
      elif p.curr.kind in {tkVariable, tkSafevariable}:
        result.nodes.add p.parseVariable()
      elif p.curr.kind == tkInteger:
        result.nodes.add p.parseInteger()
      elif p.curr.kind == tkCall:
        result.nodes.add p.parseCall()
      else:
        p.setError InvalidValueAssignment, p.prev.line, p.prev.col, true
    # elif p.curr.kind in {tkDot, tkId, tkIdentifier} + tkHtml:
    elif p.curr.kind in {tkDot, tkId} or inHtmlAttributeNames:
      # if p.curr.line > result.meta.line:
        # break # prevent bad loop
      # if p.curr.kind == tkColon: break
      result.attrs = p.getHtmlAttributes()
      if p.hasError():
        break
    else: break

proc parseHtmlElement(p: var Parser): Node =
  result = p.newHtmlNode()
  if result == nil:
    return
  if p.parentNode.len == 0:
    p.parentNode.add(result)
  else:
    if result.meta.line > p.parentNode[^1].meta.line:
      p.parentNode.add(result)
  var node: Node
  while p.curr.kind == tkGt:
    walk p
    if not p.curr.kind.isHTMLElement():
      p.setError(InvalidNestDeclaration)
    inc p.lvl
    node = p.parseHtmlElement()
    if p.curr.kind != tkEof and p.curr.pos != 0:
      if p.curr.line > node.meta.line:
        let currentParent = p.parentNode[^1]
        while p.curr.pos > currentParent.meta.col:
          if p.curr.kind == tkEof: break
          var subNode = p.parseExpression()
          if subNode != nil:
            node.nodes.add(subNode)
          elif p.hasError(): break
          if p.curr.pos < currentParent.meta.pos:
            dec p.lvl, currentParent.meta.col div p.curr.pos
            delete(p.parentNode, p.parentNode.high)
            break
    if node != nil:
      result.nodes.add(node)
    elif p.hasError(): break
    if p.lvl != 0:
      dec p.lvl
    return result
  let currentParent = p.parentNode[^1]
  if p.curr.pos > currentParent.meta.col:
    inc p.lvl
  while p.curr.pos > currentParent.meta.col:
    if p.curr.kind == tkEof: break
    var subNode = p.parseExpression()
    if subNode != nil:
      result.nodes.add(subNode)
    elif p.hasError(): break
    if p.curr.kind == tkEof or p.curr.pos == 0: break # prevent division by zero
    if p.curr.pos < currentParent.meta.col:
      # dec lvl, currentParent.meta.col div p.curr.pos
      dec p.lvl
      delete(p.parentNode, p.parentNode.high)
      break
    elif p.curr.pos == currentParent.meta.col:
      dec p.lvl
  if p.curr.pos == 0: p.lvl = 0 # reset level

proc parseAssignment(p: var Parser): Node =
  discard

# import re # lazy house
proc parseSnippet(p: var Parser): Node =
  if p.curr.kind == tkJs:
    result = newSnippet(p.curr)
    result.jsCode = p.curr.value         # re.replace(p.curr.value, re"\/\*(.*?)\*\/|\s\B")
  elif p.curr.kind == tkSass:
    result = newSnippet(p.curr)
    result.sassCode = p.curr.value
  elif p.curr.kind in {tkJson, tkYaml}:
    let code = p.curr.value.split(Newlines, maxsplit = 1)
    var ident = code[0]
    p.curr.value = code[1]
    if p.curr.kind == tkJson:
      result = newSnippet(p.curr, ident)
      result.jsonCode = p.curr.value
    else:
      p.curr.kind = tkJson
      result = newSnippet(p.curr, ident)
      result.jsonCode = yaml(p.curr.value).toJsonStr
  walk p

proc parseElseBranch(p: var Parser, elseBody: var seq[Node], ifThis: TokenTuple) =
  if p.curr.pos == ifThis.pos:
    var this = p.curr
    walk p
    if p.curr.kind == tkColon: walk p
    if this.pos >= p.curr.pos:
      p.setError(NestableStmtIndentation)
      return
    while p.curr.pos > this.pos and p.curr.kind != tkEof:
      let bodyNode = p.parseExpression(exclude = {NTInt, NTString, NTBool})
      elseBody.add bodyNode

proc parseInfix(p: var Parser, strict = false): Node =
  walk p # `if` or `(` for short hand conditions
  if p.curr.kind notin tkComparables:
    p.setError(InvalidConditionalStmt)
    return
  let
    tkLeft = p.curr
    infixLeftFn = p.getPrefixFn(tkLeft.kind)
  var infixLeft: Node
  if infixLeftFn != nil:
    infixLeft = infixLeftFn(p)
    if p.hasError(): return
  else:
    p.setError(InvalidConditionalStmt)
    return
  var infixNode = ast.newInfix(infixLeft)
  if p.curr.kind == tkAnd:
    infixNode.infixOp = getOperator(tkAnd)
    infixNode.infixOpSymbol = getSymbolName(infixNode.infixOp)
    while p.curr.kind == tkAnd:
      infixNode.infixRight = p.parseInfix()
  elif p.curr.kind in tkOperators:
    let op = p.curr
    walk p
    if p.curr.kind notin tkComparables:
      p.setError(InvalidConditionalStmt)
      return
    var
      infixRight: Node
      infixRightFn = p.getPrefixFn(p.curr.kind)
    if infixRightFn != nil:
      infixRight = infixRightFn(p)
      if p.hasError(): return
      infixNode.infixOp = getOperator(op.kind)
      infixNode.infixOpSymbol = getSymbolName(infixNode.infixOp)
      infixNode.infixRight = infixRight
    else:
      p.setError(InvalidConditionalStmt)
      return
  else:
    infixNode = infixLeft
  result = infixNode
  # if strict:
  #   let lit = {NTInt, NTString, NTBool}
  #   if infixLeft.nodeType in lit and infixRight.nodeType in lit and (infixLeft.nodeType != infixRight.nodeType):
  #     p.setError(TypeMismatch % [infixLeft.nodeName, infixRight.nodeName])
  #     result = nil

proc parseCondBranch(p: var Parser, this: TokenTuple): IfBranch =
  var infixNode = p.parseInfix()
  if p.hasError():
    return
  if p.curr.pos == this.pos:
    p.setError(InvalidIndentation)
    return

  if p.curr.kind == tkColon:
    walk p
  
  var ifBody: seq[Node]
  while p.curr.pos > this.pos and p.curr.kind != tkEof:     # parse body of `if` branch
    if p.curr.kind in {tkElif, tkElse}:
      p.setError(InvalidIndentation, true)
      break
    ifBody.add p.parseExpression()
  if ifBody.len == 0:                 # when missing `if body`
    p.setError(InvalidConditionalStmt)
    return
  result = (infixNode, ifBody)

proc parseIfStmt(p: var Parser): Node =
  var this = p.curr
  var elseBody: seq[Node]
  result = newIfExpression(ifBranch = p.parseCondBranch(this), this)
  while p.curr.kind == tkElif:
    let thisElif = p.curr
    result.elifBranch.add p.parseCondBranch(thisElif)
    if p.hasError(): break

  if p.curr.kind == tkElse:       # parse body of `else` branch
    p.parseElseBranch(elseBody, this)
    if p.hasError(): return         # catch error from `parseElseBranch`
    result.elseBody = elseBody

proc parseForStmt(p: var Parser): Node =
  # Parse a new iteration statement
  let this = p.curr
  walk p
  let singularIdent = p.parseVariable()
  if p.curr.kind != tkIn:
    p.setError(InvalidIteration)
    return
  walk p # `in`
  if p.curr.kind != tkVariable:
    p.setError(InvalidIteration)
    return
  let pluralIdent = p.parseVariable()
  if p.curr.kind == tkColon:
    walk p
  var forBody: seq[Node]
  while p.curr.pos > this.pos and p.curr.kind != tkEof:
    let subNode = p.parseExpression()
    if subNode != nil:
      forBody.add subNode
    elif p.hasError(): break
  if forBody.len != 0:
    return newFor(singularIdent, pluralIdent, forBody, this)
  p.setError(NestableStmtIndentation)

proc parseCall(p: var Parser): Node =
  let tk = p.curr
  walk p, 2 # ident + (
  var params: seq[Node]
  while p.curr.line == tk.line:
    if p.curr.kind == tkRP: break
    elif p.curr.kind in tkComparables:
      let node = p.parseExpression()
      if node != nil:
        params.add(node)
      else: break
    elif p.curr.kind == tkComma:
      walk p
    else:
      break
  if p.curr.kind == tkRP:
    walk p # )
  else:
    p.setError("EOL reached before closing call statement")
    return
  let callIdent = tk.value
  result = newCall(callIdent, params)

proc parseMixinCall(p: var Parser): Node =
  let this = p.curr
  result = newMixin(p.curr)
  walk p

proc parseMixinDefinition(p: var Parser): Node =
  let this = p.curr
  walk p
  let ident = p.curr
  result = newMixinDef(p.curr)
  if p.next.kind != tkLP:
    p.setError(InvalidMixinDefinition % [ident.value])
    return
  walk p, 2

  while p.curr.kind != tkRP:
    var paramDef: ParamTuple
    if p.curr.kind == tkIdentifier:
      paramDef.key = p.curr.value
      walk p
      if p.curr.kind == tkColon:
        if p.next.kind notin {tkType_bool, tkType_int, tkType_string}: # todo handle float
          p.setError(InvalidIndentation % [ident.value], true)
        walk p
        # todo in a fancy way, please
        if p.curr.kind == tkType_bool:
          paramDef.`type` = NTBool
          paramDef.typeSymbol = $NTBool
        elif p.curr.kind == tkType_int:
          paramDef.`type` = NTInt
          paramDef.typeSymbol = $NTInt
        else:
          paramDef.`type` = NTString
          paramDef.typeSymbol = $NTString
    else:
      p.setError(InvalidMixinDefinition % [ident.value], true)
    result.mixinParamsDef.add(paramDef)
    walk p
    if p.curr.kind == tkComma:
      if p.next.kind != tkIdentifier:
        p.setError(InvalidMixinDefinition % [ident.value], true)
      walk p
  walk p
  while p.curr.pos > this.pos:
    result.mixinBody.add p.parseExpression()

proc parseIncludeCall(p: var Parser): Node =
  result = newInclude(p.curr.value)
  walk p

proc parseComment(p: var Parser): Node =
  # Actually, will skip comments
  walk p

proc parseViewLoader(p: var Parser): Node =
  if p.templateType != Layout:
    p.setError(InvalidImportView % [$p.templateType])
    return
  elif p.hasView:
    p.setError(DuplicateViewLoader)
    return
  result = newView(p.curr)
  p.hasView = true
  walk p

proc parseDoBlock(p: var Parser): Node =
  let tk = p.curr
  walk p # do
  result = newRuntime(p.curr)
  # if p.curr.kind == tkColon:
  #   walk p
  #   while p.curr.pos > tk.pos:
  #     let node = p.parseExpression()
  #     if node != nil:
  #       add result.doRuntime, node
  #     else: return
  # else:
  p.setError("`@do` block missing assignment token")

proc getPrefixFn(p: var Parser, kind: TokenKind): PrefixFunction =
  result = case kind
    of tkInteger: parseInteger
    of tkBool: parseBoolean
    of tkString: parseString
    of tkIf: parseIfStmt
    of tkFor: parseForStmt
    of tkJs, tkSass, tkJson, tkYaml: parseSnippet
    of tkInclude: parseIncludeCall
    of tkMixin:
      if p.next.kind == tkLP:
        parseMixinCall
      elif p.next.kind == tkIdentifier:
        parseMixinCall
      else: nil
    of tkCall:
      if p.next.kind == tkLP:
        parseCall
      else: nil
    of tkVariable: parseVariable
    of tkSafevariable: parseSafeVariable
    of tkComment: parseComment
    of tkView: parseViewLoader
    # of tkDo: parseDoBlock
    else: parseHtmlElement

proc parseExpression(p: var Parser, exclude: set[NodeType] = {}): Node =
  var this = p.curr
  var prefixFunction = p.getPrefixFn(this.kind)
  var exp: Node = p.prefixFunction()
  if exp == nil: return
  if exclude.len != 0:
    if exp.nodeType in exclude:
      p.setError("Unexpected token \"$1\"" % [this.value])
  result = exp

proc parseExpressionStmt(p: var Parser): Node =
  var exp = p.parseExpression()
  if exp == nil or p.hasError():
    return
  result = ast.newExpression exp

proc parseStatement(p: var Parser): Node =
  case p.curr.kind:
    of tkVariable:    result = p.parseAssignment()
    else:              result = p.parseExpressionStmt()

proc parse*(engine: TimEngine, code, path: string, templateType: TemplateType): Parser =
  ## Parse a new Tim document
  var
    resHandle = resolve(code, path, engine, templateType)
    p: Parser = Parser(templateType: templateType, ids: newTable[string, int]())
  if p.templateType == Layout:
    jit(p) # force enabling jit for layout templates
  if resHandle.hasError():
    p.setError(resHandle.getError, resHandle.getErrorLine, resHandle.getErrorColumn)
    return p
  else:
    p.lexer = Lexer.init(resHandle.getFullCode(), allowMultilineStrings = true)
    p.filePath = path
  p.curr = p.lexer.getToken()
  p.next    = p.lexer.getToken()
  p.statements = Program()
  while p.hasError() == false and p.curr.kind != tkEof:
    var statement: Node = p.parseStatement()
    if statement != nil:
      p.statements.nodes.add(statement)
  p.lexer.close()
  result = p

proc parse*(code: string): Parser =
  var p = Parser(templateType: View, ids: newTable[string, int]())
  p.lexer = Lexer.init(code, allowMultilineStrings = true)
  p.curr = p.lexer.getToken
  p.next = p.lexer.getToken
  while p.hasError == false and p.curr.kind != tkEof:
    var stmtNode: Node = p.parseStatement()
    if stmtNode != nil:
      p.statements.nodes.add(stmtNode)
  p.lexer.close()
  result = p