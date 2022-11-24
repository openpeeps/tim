# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import std/[tables, json, jsonutils]

import tokens, ast, data
from resolver import resolve, hasError, getError,
                    getErrorLine, getErrorColumn, getFullCode

from meta import TimEngine, TimlTemplate, TimlTemplateType, getContents, getFileData
from std/strutils import `%`, isDigit, join, endsWith, parseInt, parseBool

type
    Parser* = object
        depth: int
            ## Incremented depth of levels while parsing inline nests
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
        statements: Program
            ## Holds AST representation
        data: Data
            ## An instance of Data to be evaluated on runtime.
        enableJit: bool
            ## Determine if current Timl document needs a JIT compilation.
            ## This is set true when current document contains either a
            ## conditional statement or other dynamic statements.
        error: string
            ## A parser/lexer error
        memory: VarStorage
            ## An index containing all variables (in order to prevent duplicates)

    PrefixFunction = proc(p: var Parser): Node
    InfixFunction = proc(p: var Parser, left: Node): Node
    VarStorage = TableRef[string, TokenTuple]

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
    InvalidHTMLElementName = "Invalid HTMLElement name \"$1\""
    InvalidMixinDefinition = "Invalid mixin definition \"$1\""
    InvalidStringConcat = "Invalid string concatenation"
    InvalidVarDeclaration = "Invalid variable declaration"
    NestableStmtIndentation = "Nestable statement requires indentation"
    TypeMismatch = "Type mismatch: x is type of $1 but y: $2"

const
    tkComparables = {TK_VARIABLE, TK_STRING, TK_INTEGER, TK_BOOL_TRUE, TK_BOOL_FALSE}
    tkOperators = {TK_EQ, TK_NEQ, TK_LT, TK_LTE, TK_GT, TK_GTE}
    tkConditionals = {TK_IF, TK_ELIF, TK_ELSE, TK_IN, TK_OR}
    tkLoops = {TK_FOR, TK_IN}
    tkCalc = {TK_PLUS, TK_MINUS, TK_DIVIDE, TK_MULTIPLY}
    tkCall = {TK_INCLUDE, TK_MIXIN}
    tkNone = (TK_NONE, "", 0,0,0,0)
    svgscTags = {
        TK_SVG_PATH, TK_SVG_CIRCLE, TK_SVG_POLYLINE, TK_SVG_ANIMATE,
        TK_SVG_ANIMATETRANSFORM, TK_SVG_ANIMATEMOTION,
        TK_SVG_FE_BLEND, TK_SVG_FE_COLORMATRIX, TK_SVG_FE_COMPOSITE,
        TK_SVG_FE_CONVOLVEMATRIX, TK_SVG_FE_DISPLACEMENTMAP
    }
    scTags = {
        TK_AREA, TK_BASE, TK_BR, TK_COL, TK_EMBED,
        TK_HR, TK_IMG, TK_INPUT, TK_LINK, TK_META,
        TK_PARAM, TK_SOURCE, TK_TRACK, TK_WBR} + svgscTags

template setError[P: Parser](p: var P, msg: string, breakStmt: bool) =
    ## Set parser error
    p.error = "Error ($2:$3): $1" % [msg, $p.current.line, $p.current.pos]
    break

template setError[P: Parser](p: var P, msg: string) =
    ## Set parser error
    p.error = "Error ($2:$3): $1" % [msg, $p.current.line, $p.current.pos]

proc setError[P: Parser](p: var P, msg: string, line, col: int) =
    ## Set a Parser error on a specific line and col number
    p.current.line = line
    p.current.pos = col
    p.setError(msg)

proc hasError*[P: Parser](p: var P): bool =
    ## Determine if current parser instance has any errors
    result = p.error.len != 0 or p.lexer.hasError()

proc getError*[P: Parser](p: var P): string = 
    ## Retrieve current parser instance errors,
    ## including lexer-side unrecognized token errors
    if p.lexer.hasError():
        result = p.lexer.getError()
    elif p.error.len != 0:
        result = p.error

proc isHTMLElement(token: TokenKind): bool =
    result = token notin tkComparables + tkOperators +
                         tkConditionals + tkCalc + tkCall +
                         tkLoops + {TK_EOF}

proc parse*(engine: TimEngine, code, path: string,
            templateType: TimlTemplateType): Parser

proc getStatements*(p: Parser, asNodes = true): Program =
    ## Return all HtmlNodes available in current document
    result = p.statements

proc getStatementsStr*(p: Parser, prettyString, prettyPlain = false): string = 
    ## Retrieve all HtmlNodes available in current document as stringified JSON
    if prettyString or prettyPlain: 
        return pretty(toJson(p.getStatements()))
    result = $(toJson(p.statements))

template jit(p: var Parser) =
    ## Enable jit flag When current document contains
    ## either conditionals, or variable assignments
    if p.enableJit == false: p.enableJit = true

proc hasJIT*(p: var Parser): bool {.inline.} =
    ## Determine if current timl template
    ## requires a JIT compilation
    result = p.enableJit == true

proc jump(p: var Parser, offset = 1) =
    var i = 0
    while offset != i:
        p.prev = p.current
        p.current = p.next
        p.next = p.lexer.getToken()
        inc i

proc getOperator(tk: TokenKind): OperatorType =
    case tk:
    of TK_EQ: result = EQ
    of TK_NEQ: result = NE
    of TK_LT: result = LT
    of TK_LTE: result = LTE
    of TK_GT: result = GT
    of TK_GTE: result = GTE
    of TK_AND: result = AND
    else: discard

# prefix / infix handlers
proc parseExpressionStmt(p: var Parser): Node
proc parseStatement(p: var Parser): Node
proc parseExpression(p: var Parser, exclude: set[NodeType] = {}): Node
proc parseIfStmt(p: var Parser): Node
proc parseForStmt(p: var Parser): Node
proc getPrefixFn(p: var Parser, kind: TokenKind): PrefixFunction
# proc getInfixFn(kind: TokenKind): InfixFunction

proc isDataStorage(tk: TokenTuple): bool =
    result = tk.value == "data"

proc resolveInlineNest(lazySeq: var seq[Node]): Node =
    var i = 0
    var maxlen = (lazySeq.len - 1)
    while true:
        if i == maxlen: break
        lazySeq[(maxlen - (i + 1))].nodes.add(lazySeq[^1])
        lazySeq.delete( (maxlen - i) )
        inc i
    result = lazySeq[0]

proc parseInfix(p: var Parser, infixLeft: Node, strict = false): Node =
    let tk: TokenTuple = p.current
    jump p
    let infixRight: Node = p.parseExpression()
    result = ast.newInfix(infixLeft, infixRight, getOperator(tk.kind))
    if strict:
        let lit = {NTInt, NTString, NTBool}
        if infixLeft.nodeType in lit and infixRight.nodeType in lit and (infixLeft.nodeType != infixRight.nodeType):
            p.setError(TypeMismatch % [infixLeft.nodeName, infixRight.nodeName])
            result = nil

proc parseInteger(p: var Parser): Node =
    # Parse a new `integer` node
    result = ast.newInt(parseInt(p.current.value))
    jump p

proc parseBoolean(p: var Parser): Node =
    # Parse a new `boolean` node
    result = ast.newBool(parseBool(p.current.value))
    jump p

proc parseString(p: var Parser): Node =
    # Parse a new `string` node
    # if p.prev.kind == TK_STRING:
    #     result = ast.newNode(NTHtmlElement, p.current)
    #     result.htmlNodeType = Html_Br
    #     result.htmlNodeName = "br"
    #     result.issctag = true
    #     result.nodes.add ast.newString(p.current)
    #     jump p
    # else:
    var concated: bool
    let strToken = p.current
    if p.next.kind == TK_AND:
        concated = true
        jump p
    while p.current.kind == TK_AND:
        if p.next.kind notin {TK_STRING, TK_VARIABLE, TK_SAFE_VARIABLE}:
            p.setError(InvalidStringConcat)
            return nil
        jump p
        let infixRight: Node = p.parseExpression()
        if result == nil:
            result = ast.newInfix(ast.newString(strToken), infixRight, getOperator(TK_AND))
        else:
            result = ast.newInfix(result, infixRight, getOperator(TK_AND))
    if not concated:
        result = ast.newString(strToken)
        jump p

proc parseVariable(p: var Parser): Node =
    if p.current.isDataStorage() and p.next.kind == TK_DOT:
        jump p, 2
        if p.current.kind == TK_IDENTIFIER:
            result = newVariable(p.current, dataStorage = true)
            jump p
        else:
            p.setError(InvalidVarDeclaration)
            return nil
    else:
        result = newVariable(p.current)
        jump p
    jit p

proc parseSafeVariable(p: var Parser): Node =
    result = newVariable(p.current, isSafeVar = true)
    jump p
    jit p

proc getHtmlAttributes(p: var Parser): HtmlAttributes =
    # Parse all attributes and return it as a
    # `Table[string, seq[string]]`
    while true:
        if p.current.kind == TK_DOT:
            # Add `class=""` html attribute
            let attrKey = "class"
            if p.next.kind == TK_IDENTIFIER:
                if result.hasKey(attrKey):
                    if p.next.value in result[attrKey]:
                        p.setError DuplicateClassName % [p.next.value], true
                    else: result[attrKey].add(p.next.value)
                else:
                    result[attrKey] = @[p.next.value]
                jump p, 2
            else:
                p.setError(InvalidClassAttribute)
                jump p
                break
        elif p.current.kind == TK_ATTR_ID:
            # Set `id=""` HTML attribute
            let attrKey = "id"
            if not result.hasKey(attrKey):
                if p.next.kind == TK_IDENTIFIER:
                    result[attrKey] = @[p.next.value]
                    jump p, 2
                else: p.setError(InvalidAttributeId, true)
            else: p.setError DuplicateAttrId % [p.next.value], true
        elif p.current.kind in {TK_IDENTIFIER, TK_STYLE, TK_TITLE} and p.next.kind == TK_ASSIGN:
            p.current.kind = TK_IDENTIFIER
            let attrName = p.current.value
            jump p
            if p.next.kind != TK_STRING:
                p.setError InvalidAttributeValue % [attrName], true
            if result.hasKey(attrName):
                p.setError DuplicateAttributeKey % [attrName], true
            else:
                result[attrName] = @[p.next.value]
            jump p, 2 
        else: break
var lvl = 0
proc newHtmlNode(p: var Parser): Node =
    var isSelfClosingTag = p.current.kind in scTags
    result = ast.newHtmlElement(p.current)
    result.issctag = isSelfClosingTag
    jump p
    if result.meta.pos != 0:
        result.meta.pos = lvl * 4 # set real indentation size
    while true:
        if p.current.kind == TK_COLON:
            jump p
            if p.current.kind == TK_STRING:
                result.nodes.add p.parseString()
            elif p.current.kind in {TK_VARIABLE, TK_SAFE_VARIABLE}:
                result.nodes.add p.parseVariable()
            else:
                p.setError InvalidNestDeclaration, true
        elif p.current.kind in {TK_DOT, TK_ATTR_ID, TK_IDENTIFIER}:
            result.attrs = p.getHtmlAttributes()
        else: break

proc parseHtmlElement(p: var Parser): Node =
    result = p.newHtmlNode()
    var node, prevNode: Node
    var i = 0
    while p.current.kind == TK_GT:
        jump p
        if not p.current.kind.isHTMLElement():
            p.setError(InvalidNestDeclaration, true)
        inc lvl
        inc i
        node = p.parseHtmlElement()
        if p.current.pos > result.meta.pos:
            inc lvl
        elif p.current.line > node.meta.line:
            dec lvl, i
            i = 0
        while p.current.line > node.meta.line and p.current.pos * lvl > node.meta.pos:
            if p.current.kind == TK_EOF: break
            inc i
            node.nodes.add(p.parseExpression())
        dec lvl, i
        i = 0
        result.nodes.add(node)
    while p.current.line > result.meta.line and p.current.pos > result.meta.col:
        if p.current.kind == TK_EOF: break
        if p.current.pos > result.meta.col:
            if prevNode != nil:
                if p.current.pos == prevNode.meta.pos:
                    discard
                elif p.current.pos < prevNode.meta.pos:
                    dec lvl
            else:
                inc lvl
        inc i
        prevNode = p.parseExpression()
        result.nodes.add(prevNode)
    
    if p.current.pos == 0: lvl = 0 # reset level

    if p.current.pos < result.meta.col or p.current.pos == result.meta.col:
        if lvl > i: # prevent `value out of range`
            dec lvl,  i
            i = 0
        # else:
        #     dec lvl

proc parseAssignment(p: var Parser): Node =
    discard

proc parseElseBranch(p: var Parser, elseBody: var seq[Node], ifThis: TokenTuple) =
    if p.current.pos != ifThis.pos:
        p.setError(InvalidIndentation)
        return
    var this = p.current
    jump p
    while p.current.pos > this.pos:
        let bodyNode = p.parseExpression(exclude = {NTInt, NTString, NTBool})
        elseBody.add bodyNode

proc parseCondBranch(p: var Parser, this: TokenTuple): IfBranch =
    if p.next.kind notin tkComparables:
        p.setError(InvalidConditionalStmt)
        return
    jump p
    var infixLeft: Node
    let infixLeftFn = p.getPrefixFn(p.current.kind)
    if infixLeftFn != nil:
        infixLeft = infixLeftFn(p)
    else:
        p.setError(InvalidConditionalStmt)
        return
    if p.current.kind notin tkOperators:
        p.setError(InvalidConditionalStmt)
    let infixNode = p.parseInfix(infixLeft, strict = true)

    if p.current.pos == this.pos:
        p.setError(InvalidIndentation)
        return
    var ifBody, elseBody: seq[Node]
    while p.current.pos > this.pos:     # parse body of `if` branch
        if p.current.kind in {TK_ELIF, TK_ELSE}:
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
    while p.current.kind == TK_ELIF:
        let thisElif = p.current
        result.elifBranch.add p.parseCondBranch(thisElif)
        if p.hasError(): break

    if p.current.kind == TK_ELSE:       # parse body of `else` branch
        p.parseElseBranch(elseBody, this)
        if p.hasError(): return         # catch error from `parseElseBranch`
        result.elseBody = elseBody

proc parseForStmt(p: var Parser): Node =
    # Parse a new iteration statement
    let this = p.current
    jump p
    let singularIdent = p.parseVariable()
    if p.current.kind != TK_IN:
        p.setError(InvalidIteration)
        return
    jump p # `in`
    if p.current.kind != TK_VARIABLE:
        p.setError(InvalidIteration)
        return
    let pluralIdent = p.parseVariable()
    var forBody: seq[Node]
    while p.current.pos > this.pos:
        forBody.add p.parseExpression()
    if forBody.len != 0:
        return newFor(singularIdent, pluralIdent, forBody, this)
    p.setError(NestableStmtIndentation)

proc parseMixinCall(p: var Parser): Node =
    result = newMixin(p.current)
    jump p

proc parseMixinDefinition(p: var Parser): Node =
    let this = p.current
    jump p
    let ident = p.current
    result = newMixinDef(p.current)
    if p.next.kind != TK_LPAR:
        p.setError(InvalidMixinDefinition % [ident.value])
        return
    jump p, 2

    while p.current.kind != TK_RPAR:
        var paramDef: ParamTuple
        if p.current.kind == TK_IDENTIFIER:
            paramDef.key = p.current.value
            jump p
            if p.current.kind == TK_COLON:
                if p.next.kind notin {TK_TYPE_BOOL, TK_TYPE_INT, TK_TYPE_STRING}: # todo handle float
                    p.setError(InvalidIndentation % [ident.value], true)
                jump p
                # todo in a fancy way, please
                if p.current.kind == TK_TYPE_BOOL:
                    paramDef.`type` = NTBool
                    paramDef.typeSymbol = $NTBool
                elif p.current.kind == TK_TYPE_INT:
                    paramDef.`type` = NTInt
                    paramDef.typeSymbol = $NTInt
                else:
                    paramDef.`type` = NTString
                    paramDef.typeSymbol = $NTString
        else:
            p.setError(InvalidMixinDefinition % [ident.value], true)
        result.mixinParamsDef.add(paramDef)
        jump p
        if p.current.kind == TK_COMMA:
            if p.next.kind != TK_IDENTIFIER:
                p.setError(InvalidMixinDefinition % [ident.value], true)
            jump p
    jump p
    while p.current.pos > this.pos:
        result.mixinBody.add p.parseExpression()

proc parseIncludeCall(p: var Parser): Node =
    result = newInclude(p.current.value)
    jump p


proc getPrefixFn(p: var Parser, kind: TokenKind): PrefixFunction =
    result = case kind
        of TK_INTEGER: parseInteger
        of TK_BOOL_TRUE, TK_BOOL_FALSE: parseBoolean
        of TK_STRING: parseString
        of TK_IF: parseIfStmt
        of TK_FOR: parseForStmt
        of TK_INCLUDE: parseIncludeCall
        of TK_MIXIN:
            if p.next.kind == TK_LPAR:
                parseMixinCall
            elif p.next.kind == TK_IDENTIFIER:
                parseMixinDefinition
            else: nil
        of TK_VARIABLE: parseVariable
        of TK_SAFE_VARIABLE: parseSafeVariable
        else: parseHtmlElement

proc parseExpression(p: var Parser, exclude: set[NodeType] = {}): Node =
    var this = p.current
    var prefixFunction = p.getPrefixFn(this.kind)
    var exp: Node = p.prefixFunction()
    if exclude.len != 0:
        if exp.nodeType in exclude:
            p.setError("Unexpected token \"$1\"" % [this.value])
    if exp != nil:
        result = exp

proc parseExpressionStmt(p: var Parser): Node =
    let tk = p.current
    var exp = p.parseExpression()
    if exp == nil and p.hasError():
        return
    result = ast.newExpression exp

proc parseStatement(p: var Parser): Node =
    case p.current.kind:
        of TK_VARIABLE:    result = p.parseAssignment()
        else:              result = p.parseExpressionStmt()

proc parse*(engine: TimEngine, code, path: string, templateType: TimlTemplateType): Parser =
    ## Parse a new Tim document
    var iHandler = resolve(code, path, engine, templateType)
    var p: Parser = Parser(engine: engine, memory: newTable[string, TokenTuple]())
    if iHandler.hasError():
        p.setError(
            iHandler.getError(),
            iHandler.getErrorLine(),
            iHandler.getErrorColumn())
        return p
    else:
        p.lexer = Lexer.init(iHandler.getFullCode(), allowMultilineStrings = true)
        p.filePath = path

    p.current = p.lexer.getToken()
    p.next    = p.lexer.getToken()

    p.statements = Program()
    while p.hasError() == false and p.current.kind != TK_EOF:
        var statement: Node = p.parseStatement()
        if statement != nil:
            p.statements.nodes.add(statement)
    p.lexer.close()
    result = p
