# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import std/[tables, json, jsonutils]

import tokens, ast
from resolver import resolve, hasError, getError,
                    getErrorLine, getErrorColumn, getFullCode

from meta import TimEngine, TimlTemplate, TimlTemplateType, getFileData
from std/strutils import `%`, isDigit, join, endsWith, parseInt, parseBool

type
    Parser* = object
        lvl: int
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
        parentNode: seq[Node]
        statements: Program
            ## Holds AST representation
        headliners: TableRef[int, Node]
        enableJit: bool
            ## Determine if current Timl document needs a JIT compilation.
            ## This is set true when current document contains either a
            ## conditional statement or other dynamic statements.
        error: string
            ## A parser/lexer error
        memory: VarStorage
            ## An index containing all variables (in order to prevent duplicates)
        templateType: TimlTemplateType

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
    tkSpecial = {TK_DOT, TK_COLON, TK_LCURLY, TK_RCURLY,
                  TK_LPAR, TK_RPAR, TK_ATTR_ID, TK_ASSIGN, TK_COMMA,
                  TK_AT, TK_NOT, TK_AND} + tkCalc + tkOperators
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
    if p.enableJit == false:
        p.enableJit = true

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

proc isAppStorage(tk: TokenTuple): bool =
    result = tk.value == "app"

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

template handleConcat() =
    while p.current.kind == TK_AND:
        if p.next.kind notin {TK_STRING, TK_VARIABLE, TK_SAFE_VARIABLE}:
            p.setError(InvalidStringConcat)
            return nil
        jump p
        let infixRight: Node = p.parseExpression()
        if result == nil:
            result = ast.newInfix(leftNode, infixRight, getOperator(TK_AND))
        else:
            result = ast.newInfix(result, infixRight, getOperator(TK_AND))

proc parseString(p: var Parser): Node =
    # Parse a new `string` node
    var concated: bool
    let this = p.current
    if p.next.kind == TK_AND:
        concated = true
        jump p
        var leftNode = ast.newString(this)
        handleConcat()
        if result == nil:
            result = leftNode
    if not concated:
        result = ast.newString(this)
        jump p

proc parseVariable(p: var Parser): Node =
    var leftNode: Node
    if p.current.isAppStorage() and p.next.kind == TK_DOT: 
        jump p, 2
        if p.current.kind == TK_IDENTIFIER:
            leftNode = newVariable(p.current, dataStorage = true)
            jump p
            handleConcat()
        else:
            p.setError(InvalidVarDeclaration)
            return
        if result == nil:
            result = leftNode
    else:
        if p.next.kind == TK_DOT:
            let varIdentToken = p.current
            jump p
            if p.next.kind == TK_IDENTIFIER or p.next.kind notin tkSpecial:
                jump p
                if p.current.value == "v":
                    leftNode = newVarCallValAccessor(varIdentToken)
                else:
                    leftNode = newVarCallKeyAccessor(varIdentToken, p.current.value)
                handleConcat()
            else:
                p.setError(InvalidVarDeclaration)
                return
        else:
            leftNode = newVariable(p.current)
            handleConcat()
            if result == nil:
                result = leftNode
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
            if p.next.kind notin tkSpecial:
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

proc newHtmlNode(p: var Parser): Node =
    var isSelfClosingTag = p.current.kind in scTags
    result = ast.newHtmlElement(p.current)
    result.issctag = isSelfClosingTag
    jump p
    if result.meta.pos != 0:
        result.meta.pos = p.lvl * 4 # set real indentation size
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
            if p.current.line > result.meta.line: break # prevent bad loop
            result.attrs = p.getHtmlAttributes()
            if p.hasError(): break
        else: break

proc parseHtmlElement(p: var Parser): Node =
    result = p.newHtmlNode()
    if p.parentNode.len == 0:
        p.parentNode.add(result)
    else:
        if result.meta.line > p.parentNode[^1].meta.line:
            p.parentNode.add(result)
    var node: Node
    while p.current.kind == TK_GT:
        jump p
        if not p.current.kind.isHTMLElement():
            p.setError(InvalidNestDeclaration)
        inc p.lvl
        node = p.parseHtmlElement()
        if p.current.kind != TK_EOF and p.current.pos != 0:
            if p.current.line > node.meta.line:
                let currentParent = p.parentNode[^1]
                # if p.current.pos > currentParent.meta.col:
                #     inc p.lvl
                while p.current.pos > currentParent.meta.col:
                    if p.current.kind == TK_EOF: break
                    var subNode = p.parseExpression()
                    if subNode != nil:
                        node.nodes.add(subNode)
                    if p.current.pos < currentParent.meta.pos:
                        dec p.lvl, currentParent.meta.col div p.current.pos
                        delete(p.parentNode, p.parentNode.high)
                        break
        result.nodes.add(node)
        if p.lvl != 0:
            dec p.lvl
        return result
    let currentParent = p.parentNode[^1]
    if p.current.pos > currentParent.meta.col:
        inc p.lvl
    while p.current.pos > currentParent.meta.col:
        if p.current.kind == TK_EOF: break
        var subNode = p.parseExpression()
        if subNode != nil:
            result.nodes.add(subNode)
        if p.current.kind == TK_EOF or p.current.pos == 0: break # prevent division by zero
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

proc parseElseBranch(p: var Parser, elseBody: var seq[Node], ifThis: TokenTuple) =
    if p.current.pos != ifThis.pos:
        p.setError(InvalidIndentation)
        return
    var this = p.current
    jump p
    if p.current.kind == TK_COLON: jump p
    if this.pos >= p.current.pos:
        p.setError(NestableStmtIndentation)
        return
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
    
    if infixNode.infixRight.nodeType == NTBool:
        # try match variable types based on infixRight node literal
        # todo find a better solution
        infixLeft.varType = NTBool

    if p.current.pos == this.pos:
        p.setError(InvalidIndentation)
        return
    if p.current.kind == TK_COLON: jump p
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
    if p.current.kind == TK_COLON: jump p
    var forBody: seq[Node]
    while p.current.pos > this.pos:
        let subNode = p.parseExpression()
        if subNode != nil: # TODO throw exception ?
            forBody.add subNode
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

proc parseComment(p: var Parser): Node =
    # Actually, will skip comments
    var this = p.current
    jump p
    while p.current.line == this.line:
        jump p

proc parseViewLoader(p: var Parser): Node =
    if p.templateType != Layout:
        p.setError("Trying to load a view inside a $1" % [$p.templateType])
        return
    result = newView(p.current)
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
        of TK_COMMENT: parseComment
        of TK_VIEW: parseViewLoader
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
    let tk = p.current
    var exp = p.parseExpression()
    if exp == nil or p.hasError():
        return
    result = ast.newExpression exp

proc parseStatement(p: var Parser): Node =
    case p.current.kind:
        of TK_VARIABLE:    result = p.parseAssignment()
        else:              result = p.parseExpressionStmt()

proc parse*(engine: TimEngine, code, path: string, templateType: TimlTemplateType): Parser =
    ## Parse a new Tim document
    var importsResolver = resolve(code, path, engine, templateType)
    var p: Parser = Parser(
        engine: engine,
        memory: newTable[string, TokenTuple](),
        headliners: newTable[int, Node](),
        templateType: templateType
    )
    if importsResolver.hasError():
        p.setError(
            importsResolver.getError(),
            importsResolver.getErrorLine(),
            importsResolver.getErrorColumn())
        return p
    else:
        p.lexer = Lexer.init(importsResolver.getFullCode(), allowMultilineStrings = true)
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
