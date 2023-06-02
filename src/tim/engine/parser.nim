# A high-performance compiled template engine
# inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, json]
from pkg/nyml import yaml, toJsonStr
import pkg/jsony

import tokens, ast
from resolver import resolve, hasError, getError,
          getErrorLine, getErrorColumn, getFullCode

from meta import TimEngine, Template, TemplateType
from std/strutils import `%`, isDigit, join, endsWith, Newlines,
                            split, parseInt, parseBool, parseFloat

type
  Parser* = object
    lvl: int
    engine: TimEngine
      ## Holds current TimEngine instance
    lexer: Lexer
      ## A TokTok Lexer instance
    filePath: string
      ## Path to current `.timl` template. This is mainly used
      ## by internal Parser procs for 
    includes: seq[string]
      ## A sequence of file paths that are included
      ## in current `.timl` template
    prev, current, next: TokenTuple
      ## Hold `Tokentuple` siblinngs while parsing
    parentNode: seq[Node]
    statements: Program
      ## Holds AST representation
    enableJit: bool
      ## Determine if current Timl document needs a JIT compilation.
      ## This is set true when current document contains either a
      ## conditional statement or other dynamic statements.
    error: string
      ## A parser/lexer error
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

const
  tkVars = {TKVariable, TKSafeVariable}
  tkCallables = {TKCall}
  tkAssignables = {TKString, TKInteger, TKBOOL_TRUE, TKBOOL_FALSE} + tkVars
  tkComparables = tkAssignables + tkCallables
  tkOperators = {TKEQ, TKNEQ, TKLT, TKLTE, TKGT, TKGTE}
  tkConditionals = {TKIF, TKELIF, TKELSE, TKIN, TKOR, TKAND}
  tkLoops = {TKFOR, TKIN}
  tkCalc = {TKPLUS, TKMINUS, TKDIVIDE, TKMULTI}
  tkCall = {TKINCLUDE, TKMIXIN}
  tkNone = (TKNONE, "", 0,0,0,0)
  tkSpecial = {TKDOT, TKCOLON, TKLCURLY, TKRCURLY,
          TKLPAR, TKRPAR, TKID, TKASSIGN, TKCOMMA,
          TKAT, TKNOT, TKAMP} + tkCalc + tkOperators + tkLoops
  svgscTags = {
    TKSVG_PATH, TKSVG_CIRCLE, TKSVG_POLYLINE, TKSVG_ANIMATE,
    TKSVG_ANIMATETRANSFORM, TKSVG_ANIMATEMOTION,
    TKSVG_FE_BLEND, TKSVG_FE_COLORMATRIX, TKSVG_FE_COMPOSITE,
    TKSVG_FE_CONVOLVEMATRIX, TKSVG_FE_DISPLACEMENTMAP
  }
  scTags = {
    TKAREA, TKBASE, TKBR, TKCOL, TKEMBED,
    TKHR, TKIMG, TKINPUT, TKLINK, TKMETA,
    TKPARAM, TKSOURCE, TKTRACK, TKWBR} + svgscTags

  tkHtml = {
    TKA, TKABBR, TKACRONYM, TKADDRESS, TKAPPLET, TKAREA, TKARTICLE, TKASIDE,
    TKAUDIO, TKBOLD, TKBASE, TKBASEFONT, TKBDI, TKBDO, TKBIG, TKBLOCKQUOTE,
    TKBODY, TKBR, TKBUTTON, TKCANVAS, TKCAPTION, TKCENTER, TKCITE, TKCODE,
    TKCOL, TKCOLGROUP, TKDATA, TKDATA, TKDATALIST, TKDD, TKDEL, TKDETAILS,
    TKDFN, TKDIALOG, TKDIR, TKDOCTYPE, TKDL, TKDT, TKEM, TKEMBED, TKFIELDSET,
    TKFIGCAPTION, TKFIGURE, TKFONT, TKFOOTER, TKH1, TKH2, TKH3, TKH4, TKH5, TKH6,
    TKHEAD, TKHEADER, TKHR, TKHTML, TKITALIC, TKIFRAME, TKIMG, TKINPUT, TKINS,
    TKKBD, TKLABEL, TKLEGEND, TKLI, TKLINK, TKMAIN, TKMAP, TKMARK, TKMETER,
    TKNAV, TKNOFRAMES, TKNOSCRIPT, TKOBJECT, TKOL, TKOPTGROUP, TKOPTION, TKOUTPUT,
    TKPARAGRAPH, TKPARAM, TKPRE, TKPROGRESS, TKQUOTATION, TKRP, TKRT, TKRUBY, TKSTRIKE,
    TKSAMP, TKSECTION, TKSELECT, TKSMALL, TKSOURCE, TKSPAN, TKSTRIKE_LONG, TKSTRONG,
    TKSTYLE, TKSUB, TKSUMMARY, TKSUP, TKTABLE, TKTBODY, TKTD, TKTEMPLATE,
    TKTEXTAREA, TKTFOOT, TKTH, TKTHEAD, TKTIME, TKTITLE, TKTR, TKTRACK, TKTT, TKUNDERLINE,
    TKUL, TKVAR, TKVIDEO, TKWBR
  }

template setError(p: var Parser, msg: string, breakStmt: bool) =
  ## Set parser error
  p.error = "Error ($2:$3): $1\n$4" % [msg, $p.current.line, $p.current.pos, p.filePath]
  break

template setError(p: var Parser, msg: string) =
  ## Set parser error
  p.error = "Error ($2:$3): $1" % [msg, $p.current.line, $p.current.pos]

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
             tkConditionals + tkCalc + tkCall +
             tkLoops + {TKEOF}

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
    p.prev = p.current
    p.current = p.next
    p.next = p.lexer.getToken()
    inc i

proc getOperator(tk: TokenKind): OperatorType =
  case tk:
    of TKEQ: result = EQ
    of TKNEQ: result = NE
    of TKLT: result = LT
    of TKLTE: result = LTE
    of TKGT: result = GT
    of TKGTE: result = GTE
    of TKAND: result = AND
    of TKAMP: result  = AMP
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
  result = ast.newInt(parseInt(p.current.value), p.current)
  walk p

proc parseBoolean(p: var Parser): Node =
  # Parse a new `boolean` node
  result = ast.newBool(parseBool(p.current.value))
  walk p

template handleConcat() =
  while p.current.kind == TKAMP:
    if p.next.kind notin {TKString, TKVariable, TKSafeVariable}:
      p.setError(InvalidStringConcat)
      return nil
    walk p
    let infixRight: Node = p.parseExpression()
    if result == nil:
      result = ast.newInfix(leftNode, infixRight, getOperator(TKAMP))
    else:
      result = ast.newInfix(result, infixRight, getOperator(TKAMP))

proc parseString(p: var Parser): Node =
  # Parse a new `string` node
  if p.hasError(): return
  var concated: bool
  let this = p.current
  if p.next.kind == TKAMP:
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
    this = p.current
    accessors: seq[Node]
  if p.current.isGlobalVar(): 
    walk p
    varVisibility = VarVisibility.GlobalVar
  elif p.current.isScopeVar():
    varVisibility = VarVisibility.ScopeVar
    walk p
  else:
    varVisibility = VarVisibility.InternalVar
  if p.current.kind in {TKDOT, TKLBRA}:
    walk p
  if p.current.kind == TKIDENTIFIER or p.current.kind notin tkSpecial and p.current.kind != TKEOF:
    this = p.current
    walk p
    while true:
      if p.current.kind == TKEOF: break
      # if p.current.wsno != 0 or p.current.line != this.line:
      #     p.setError(InvalidAccessorDeclaration, true)
      if p.current.kind == TKDOT:
        walk p # .
        if p.current.kind == TKIDENTIFIER or p.current.kind notin tkSpecial:
          accessors.add newString(p.current)
          walk p # .
          if p.current.wsno != 0: break
        else: p.setError(InvalidVarDeclaration, true)
      elif p.current.kind == TKLBRA:
        if p.next.kind != TKInteger:
          p.setError(InvalidArrayIndex, true)
        walk p # [
        if p.next.kind != TKRBRA:
          p.setError(InvalidAccessorDeclaration, true)
        accessors.add(p.parseInteger())
        walk p # ]
        if p.current.wsno != 0: break
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
  if p.current.kind == TKAMP: # support infix concatenation X & Y
    handleConcat()
  if result == nil:
    result = leftNode
  jit p

proc parseSafeVariable(p: var Parser): Node =
  result = newVariable(p.current, isSafeVar = true)
  walk p
  jit p

template inHtmlAttributeNames(): untyped =
  (
    p.current.kind in {
      TKString, TKVariable, TKSafeVariable,
      TKIDENTIFIER, TKIF, TKFOR, TKELIF, TKELSE,
      TKOR, TKIN} + tkHtml and p.next.kind == TKASSIGN
  )

proc getHtmlAttributes(p: var Parser): HtmlAttributes =
  # Parse all attributes and return it as a
  # `TableRef[string, seq[string]]`
  while true:
    if p.current.kind == TKDOT:
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
        while p.current.kind == TKLCURLY and p.next.kind == TKVariable:
          # parse string interpolation
          walk p
          result[attrKey][^1].sConcat.add(p.parseVariable())
          if p.current.kind == TKRCURLY:
            walk p
          else: p.setError(InvalidStringInterpolation, true)
      else:
        p.setError(InvalidClassAttribute)
        walk p
        break
    elif p.current.kind == TKID:
      # Set `id=""` HTML attribute
      let attrKey = "id"
      if not result.hasKey(attrKey):
        if p.next.kind notin tkSpecial:
          walk p
          if p.current.kind in {TKVariable, TKSafeVariable}:
            result[attrKey] = @[p.parseVariable()]
          else:
            if p.ids.hasKey(p.current.value):
              p.setError InvalidIDNotUnique % [p.current.value, $(p.ids[p.current.value])], true
            let attrValue = newString(p.current)
            result[attrKey] = @[attrValue]
            p.ids[p.current.value] = attrValue.meta.line
            walk p
        else: p.setError InvalidAttributeId, true
      else: p.setError DuplicateAttrId % [p.next.value], true
    elif inHtmlAttributeNames:
      let attrName = p.current.value
      walk p
      if p.next.kind notin {TKString, TKVariable, TKSafeVariable}:
        p.setError InvalidAttributeValue % [attrName], true
      if not result.hasKey(attrName):
        walk p
        if p.current.kind == TKString:
          if attrName == "id":
            if p.ids.hasKey(p.current.value):
              p.setError InvalidIDNotUnique % [p.current.value, $(p.ids[p.current.value])], true
          let attrValue = newString(p.current)
          result[attrName] = @[attrValue]
          if attrName == "id":
            p.ids[p.current.value] = attrValue.meta.line
          walk p
        else:
          result[attrName] = @[p.parseVariable()]
      else:
        p.setError DuplicateAttributeKey % [attrName], true
      if p.current.line > p.prev.line or p.current.kind == TKGT:
        break
    elif p.current.kind == TKLPAR:
      # parse short hand conditional statement
      let this = p.current
      let infixNode = p.parseInfix()
      if p.current.kind == TKSIF:
        walk p # ?
        var ifBody = p.getHtmlAttributes()
        if p.current.kind != TKRPAR:
          p.setError(InvalidConditionalStmt, true)
        walk p # )
        let astNode = newShortIfExpression((infixNode, ifBody), this) 
        let condKey = "%_$1$2$3$4" % [$astNode.meta.line, $astNode.meta.pos,
                                      $astNode.meta.col, $astNode.meta.wsno]
        result[condKey] = @[astNode]
        jit p
      else:
        p.setError(InvalidConditionalStmt, true)
    elif p.current.kind notin tkSpecial and p.prev.line == p.current.line:
      let attrName = p.current.value
      if not result.hasKey(attrName):
        result[attrName] = @[]
        walk p
      else:
        p.setError DuplicateAttributeKey % [attrName], true
    else: break

proc newHtmlNode(p: var Parser): Node =
  var isSelfClosingTag = p.current.kind in scTags
  result = ast.newHtmlElement(p.current)
  result.issctag = isSelfClosingTag
  walk p
  if result.meta.pos != 0:
    result.meta.pos = p.lvl * 4 # set real indentation size
  while true:
    if p.hasError(): return nil
    if p.current.kind == TKCOLON:
      walk p
      if p.current.kind == TKString:
        result.nodes.add p.parseString()
      elif p.current.kind in {TKVariable, TKSafeVariable}:
        result.nodes.add p.parseVariable()
      elif p.current.kind == TKInteger:
        result.nodes.add p.parseInteger()
      elif p.current.kind == TkCall:
        result.nodes.add p.parseCall()
      else:
        p.setError InvalidValueAssignment, p.prev.line, p.prev.col, true
    # elif p.current.kind in {TKDOT, TKID, TKIDENTIFIER} + tkHtml:
    elif p.current.kind in {TKDOT, TKID} or inHtmlAttributeNames:
      if p.current.line > result.meta.line:
        break # prevent bad loop
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
  while p.current.kind == TKGT:
    walk p
    if not p.current.kind.isHTMLElement():
      p.setError(InvalidNestDeclaration)
    inc p.lvl
    node = p.parseHtmlElement()
    if p.current.kind != TKEOF and p.current.pos != 0:
      if p.current.line > node.meta.line:
        let currentParent = p.parentNode[^1]
        while p.current.pos > currentParent.meta.col:
          if p.current.kind == TKEOF: break
          var subNode = p.parseExpression()
          if subNode != nil:
            node.nodes.add(subNode)
          elif p.hasError(): break
          if p.current.pos < currentParent.meta.pos:
            dec p.lvl, currentParent.meta.col div p.current.pos
            delete(p.parentNode, p.parentNode.high)
            break
    if node != nil:
      result.nodes.add(node)
    elif p.hasError(): break
    if p.lvl != 0:
      dec p.lvl
    return result
  let currentParent = p.parentNode[^1]
  if p.current.pos > currentParent.meta.col:
    inc p.lvl
  while p.current.pos > currentParent.meta.col:
    if p.current.kind == TKEOF: break
    var subNode = p.parseExpression()
    if subNode != nil:
      result.nodes.add(subNode)
    elif p.hasError(): break
    if p.current.kind == TKEOF or p.current.pos == 0: break # prevent division by zero
    if p.current.pos < currentParent.meta.col:
      # dec lvl, currentParent.meta.col div p.current.pos
      dec p.lvl
      delete(p.parentNode, p.parentNode.high)
      break
    elif p.current.pos == currentParent.meta.col:
      dec p.lvl
  if p.current.pos == 0: p.lvl = 0 # reset level

proc parseAssignment(p: var Parser): Node =
  discard

# import re # lazy house
proc parseSnippet(p: var Parser): Node =
  if p.current.kind == TKJS:
    result = newSnippet(p.current)
    result.jsCode = p.current.value         # re.replace(p.current.value, re"\/\*(.*?)\*\/|\s\B")
  elif p.current.kind == TKSASS:
    result = newSnippet(p.current)
    result.sassCode = p.current.value
  elif p.current.kind in {TKJSON, TKYAML}:
    let code = p.current.value.split(Newlines, maxsplit = 1)
    var ident = code[0]
    p.current.value = code[1]
    if p.current.kind == TKJSON:
      result = newSnippet(p.current, ident)
      result.jsonCode = p.current.value
    else:
      p.current.kind = TKJSON
      result = newSnippet(p.current, ident)
      result.jsonCode = yaml(p.current.value).toJsonStr
  walk p

proc parseElseBranch(p: var Parser, elseBody: var seq[Node], ifThis: TokenTuple) =
  if p.current.pos == ifThis.pos:
    var this = p.current
    walk p
    if p.current.kind == TKCOLON: walk p
    if this.pos >= p.current.pos:
      p.setError(NestableStmtIndentation)
      return
    while p.current.pos > this.pos:
      let bodyNode = p.parseExpression(exclude = {NTInt, NTString, NTBool})
      elseBody.add bodyNode

proc parseInfix(p: var Parser, strict = false): Node =
  walk p # `if` or `(` for short hand conditions
  if p.current.kind notin tkComparables:
    p.setError(InvalidConditionalStmt)
    return
  let
    tkLeft = p.current
    infixLeftFn = p.getPrefixFn(tkLeft.kind)
  var infixLeft: Node
  if infixLeftFn != nil:
    infixLeft = infixLeftFn(p)
    if p.hasError(): return
  else:
    p.setError(InvalidConditionalStmt)
    return
  var infixNode = ast.newInfix(infixLeft)
  if p.current.kind == TKAND:
    infixNode.infixOp = getOperator(TKAND)
    infixNode.infixOpSymbol = getSymbolName(infixNode.infixOp)
    while p.current.kind == TKAND:
      infixNode.infixRight = p.parseInfix()
  elif p.current.kind in tkOperators:
    let op = p.current
    walk p
    if p.current.kind notin tkComparables:
      p.setError(InvalidConditionalStmt)
      return
    var
      infixRight: Node
      infixRightFn = p.getPrefixFn(p.current.kind)
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
  if p.current.pos == this.pos:
    p.setError(InvalidIndentation)
    return

  if p.current.kind == TKCOLON:
    walk p
  
  var ifBody: seq[Node]
  while p.current.pos > this.pos:     # parse body of `if` branch
    if p.current.kind in {TKELIF, TKELSE}:
      p.setError(InvalidIndentation, true)
      break
    ifBody.add p.parseExpression()
  if ifBody.len == 0:                 # when missing `if body`
    p.setError(InvalidConditionalStmt)
    return
  result = (infixNode, ifBody)

proc parseIfStmt(p: var Parser): Node =
  var this = p.current
  var elseBody: seq[Node]
  result = newIfExpression(ifBranch = p.parseCondBranch(this), this)
  while p.current.kind == TKELIF:
    let thisElif = p.current
    result.elifBranch.add p.parseCondBranch(thisElif)
    if p.hasError(): break

  if p.current.kind == TKELSE:       # parse body of `else` branch
    p.parseElseBranch(elseBody, this)
    if p.hasError(): return         # catch error from `parseElseBranch`
    result.elseBody = elseBody

proc parseForStmt(p: var Parser): Node =
  # Parse a new iteration statement
  let this = p.current
  walk p
  let singularIdent = p.parseVariable()
  if p.current.kind != TKIN:
    p.setError(InvalidIteration)
    return
  walk p # `in`
  if p.current.kind != TKVariable:
    p.setError(InvalidIteration)
    return
  let pluralIdent = p.parseVariable()
  if p.current.kind == TKCOLON:
    walk p
  var forBody: seq[Node]
  while p.current.pos > this.pos:
    let subNode = p.parseExpression()
    if subNode != nil:
      forBody.add subNode
    elif p.hasError(): break
  if forBody.len != 0:
    return newFor(singularIdent, pluralIdent, forBody, this)
  p.setError(NestableStmtIndentation)

proc parseCall(p: var Parser): Node =
  let tk = p.current
  walk p, 2 # ident + (
  var params: seq[Node]
  while p.current.line == tk.line:
    if p.current.kind == TKRPAR: break
    elif p.current.kind in tkComparables:
      let node = p.parseExpression()
      if node != nil:
        params.add(node)
      else: break
    elif p.current.kind == TKCOMMA:
      walk p
    else:
      break
  if p.current.kind == TKRPAR:
    walk p # )
  else:
    p.setError("EOL reached before closing call statement")
    return
  let callIdent = tk.value
  result = newCall(callIdent, params)

proc parseMixinCall(p: var Parser): Node =
  let this = p.current
  result = newMixin(p.current)
  walk p

proc parseMixinDefinition(p: var Parser): Node =
  let this = p.current
  walk p
  let ident = p.current
  result = newMixinDef(p.current)
  if p.next.kind != TKLPAR:
    p.setError(InvalidMixinDefinition % [ident.value])
    return
  walk p, 2

  while p.current.kind != TKRPAR:
    var paramDef: ParamTuple
    if p.current.kind == TKIDENTIFIER:
      paramDef.key = p.current.value
      walk p
      if p.current.kind == TKCOLON:
        if p.next.kind notin {TKTYPE_BOOL, TKTYPE_INT, TKTYPE_STRING}: # todo handle float
          p.setError(InvalidIndentation % [ident.value], true)
        walk p
        # todo in a fancy way, please
        if p.current.kind == TKTYPE_BOOL:
          paramDef.`type` = NTBool
          paramDef.typeSymbol = $NTBool
        elif p.current.kind == TKTYPE_INT:
          paramDef.`type` = NTInt
          paramDef.typeSymbol = $NTInt
        else:
          paramDef.`type` = NTString
          paramDef.typeSymbol = $NTString
    else:
      p.setError(InvalidMixinDefinition % [ident.value], true)
    result.mixinParamsDef.add(paramDef)
    walk p
    if p.current.kind == TKCOMMA:
      if p.next.kind != TKIDENTIFIER:
        p.setError(InvalidMixinDefinition % [ident.value], true)
      walk p
  walk p
  while p.current.pos > this.pos:
    result.mixinBody.add p.parseExpression()

proc parseIncludeCall(p: var Parser): Node =
  result = newInclude(p.current.value)
  walk p

proc parseComment(p: var Parser): Node =
  # Actually, will skip comments
  walk p

proc parseViewLoader(p: var Parser): Node =
  if p.templateType != Layout:
    p.setError(InvalidImportView % [$p.templateType])
    return
  result = newView(p.current)
  walk p

proc getPrefixFn(p: var Parser, kind: TokenKind): PrefixFunction =
  result = case kind
    of TKInteger: parseInteger
    of TKBOOL_TRUE, TKBOOL_FALSE: parseBoolean
    of TKString: parseString
    of TKIF: parseIfStmt
    of TKFOR: parseForStmt
    of TKJS, TKSASS, TKJSON, TKYAML: parseSnippet
    of TKINCLUDE: parseIncludeCall
    of TKMIXIN:
      if p.next.kind == TKLPAR:
        parseMixinCall
      elif p.next.kind == TKIDENTIFIER:
        parseMixinCall
      else: nil
    of TKCall:
      if p.next.kind == TKLPAR:
        parseCall
      else: nil
    of TKVariable: parseVariable
    of TKSafeVariable: parseSafeVariable
    of TKCOMMENT: parseComment
    of TKVIEW: parseViewLoader
    else: parseHtmlElement

proc parseExpression(p: var Parser, exclude: set[NodeType] = {}): Node =
  var this = p.current
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
  case p.current.kind:
    of TKVariable:    result = p.parseAssignment()
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
  p.current = p.lexer.getToken()
  p.next    = p.lexer.getToken()
  p.statements = Program()
  while p.hasError() == false and p.current.kind != TKEOF:
    var statement: Node = p.parseStatement()
    if statement != nil:
      p.statements.nodes.add(statement)
  p.lexer.close()
  result = p
