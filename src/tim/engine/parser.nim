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
            ## Holds the entire Abstract Syntax Tree representation
        deferredStatements: OrderedTable[int, Node]
            ## An `OrderedTable of `Node` holding deferred elements
        prevln, currln, nextln: TokenTuple
            ## Holds TokenTuple representation of heads from prev, current and next 
        parentNode, prevNode: Node
            ## While in `walk` proc, we temporarily hold `parentNode`
            ## and prevNode for each iteration.
        data: Data
            ## An instance of Data to be evaluated on runtime.
        enableJit: bool
            ## Determine if current Timl document needs a JIT compilation.
            ## This is set true when current document contains either a
            ## conditional statement or other dynamic statements.
        error: string
            ## A parser/lexer error

    PrefixFunction = proc(p: var Parser): Node
    InfixFunction = proc(p: var Parser, left: Node): Node

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
    NestableStmtIndentation = "Nestable statement requires indentation"

const
    tkComparables = {TK_VARIABLE, TK_STRING, TK_INTEGER, TK_BOOL_TRUE, TK_BOOL_FALSE}
    tkOperators = {TK_EQ, TK_NEQ, TK_LT, TK_LTE, TK_GT, TK_GTE}
    tkConditionals = {TK_IF, TK_ELIF, TK_ELSE, TK_IN, TK_OR}
    tkLoops = {TK_FOR, TK_IN}
    tkCalc = {TK_PLUS, TK_MINUS, TK_DIVIDE, TK_MULTIPLY}
    tkCall = {TK_INCLUDE, TK_MIXIN}
    tkNone = (TK_NONE, "", 0,0,0,0)

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
    result = token notin tkComparables + tkOperators + tkConditionals + tkCalc + tkCall + tkLoops

proc parse*(engine: TimEngine, code, path: string,
            templateType: TimlTemplateType): Parser

proc getStatements*(p: Parser, asNodes = true): Program =
    ## Return all HtmlNodes available in current document
    result = p.statements

proc getStatementsStr*(p: Parser, prettyString = false): string = 
    ## Retrieve all HtmlNodes available in current document as stringified JSON
    if prettyString: 
        return pretty(toJson(p.getStatements()))
    result = $(toJson(p.statements))

template jit(p: var Parser) =
    ## Enable jit flag When current document contains
    ## either conditionals, or variable assignments
    if p.enableJit == false: p.enableJit = true

proc hasJIT*(p: var Parser): bool {.inline.} =
    ## Determine if current timl template requires a JIT compilation
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
    else: discard

# prefix / infix handlers
proc parseExpression(p: var Parser): Node
proc parseIfStmt(p: var Parser): Node
proc parseForStmt(p: var Parser): Node
proc getPrefixFn(kind: TokenKind): PrefixFunction
# proc getInfixFn(kind: TokenKind): InfixFunction

proc parseInfix(p: var Parser, infixLeft: Node): Node =
    let tk: TokenTuple = p.current
    jump p
    let infixRight: Node = p.parseExpression()
    result = ast.newInfix(infixLeft, infixRight, getOperator(tk.kind))

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
    result = ast.newString(p.current.value)
    if p.next.pos > p.prev.pos:                 # prevent other nests after new string declaration.
        p.setError(InvalidIndentation)
        return
    jump p

proc getHtmlAttributes(p: var Parser): HtmlAttributes =
    # Parse element attributes and returns a `Table[string, string]`
    # containing all HTML attributes.
    while true:
        if p.current.kind == TK_ATTR_CLASS:
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
            # TODO check wsno for other `attr` token
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

proc parseHtmlElement(p: var Parser): Node =
    # Parse a new `HTML` Element node
    result = ast.newHtmlElement(
                p.current.kind,
                p.current.line,
                p.current.pos,
                p.current.col,
                p.current.wsno
            )
    jump p
    while true:
        if p.prev.kind == TK_STRING:
            if p.prev.line == p.current.line:
                p.setError InvalidNestDeclaration, true
        if p.current.kind == TK_GT:
            # parse single line HTML elements and
            # create multi-dimensional nests
            jump p
            if not isHTMLElement(p.current.kind):
                p.setError InvalidNestDeclaration, true
                break
            result.nodes.add p.parseHtmlElement()
        elif p.current.kind == TK_COLON:
            jump p
            if p.current.kind == TK_STRING:
                result.nodes.add p.parseString()
            else:
                p.setError InvalidNestDeclaration, true
        elif p.current.kind in {TK_ATTR_CLASS, TK_ATTR_ID}:
            result.attrs = p.getHtmlAttributes()
        else:
            if isHTMLElement(p.current.kind) and (p.current.pos > p.prev.pos):
                result.nodes.add p.parseHtmlElement()
            else: break

proc parseAssignment(p: var Parser): Node =
    discard

proc parseElseBranch(p: var Parser, elseBody: var seq[Node], ifThis: TokenTuple) =
    if p.current.pos != ifThis.pos:
        p.setError InvalidConditionalStmt
        return
    var this = p.current
    jump p
    while p.current.pos > this.pos:
        elseBody.add p.parseExpression()

proc parseCondBranch(p: var Parser, this: TokenTuple): IfBranch =
    if p.next.kind notin tkComparables:
        p.setError(InvalidConditionalStmt)
        return
    jump p
    var infixLeft: Node
    let infixLeftFn = getPrefixFn(p.current.kind)
    if infixLeftFn != nil:
        infixLeft = infixLeftFn(p)
    else:
        p.setError(InvalidConditionalStmt)
        return
    if p.current.kind notin tkOperators:
        p.setError(InvalidConditionalStmt)
    let infixNode = p.parseInfix(infixLeft)

    if p.current.pos == this.pos:
        p.setError(InvalidIndentation)
        return

    var ifBody, elseBody: seq[Node]
    while p.current.pos > this.pos:     # parse body of `if` branch
        if p.current.kind in {TK_ELIF, TK_ELSE}:
            p.setError(InvalidIndentation, true)
        ifBody.add p.parseExpression()
    if ifBody.len == 0:                 # when missing `if body`
        p.setError(InvalidConditionalStmt)
        return
    result = (infixNode, ifBody)

proc parseIfStmt(p: var Parser): Node =
    var this = p.current
    var elseBody: seq[Node]
    result = newIfExpression(ifBranch = p.parseCondBranch(this))
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
    if p.next.kind != TK_IDENTIFIER:
        p.setError(InvalidIteration)
        return
    jump p # `item`
    let singularIdent = p.current.value
    if p.next.kind != TK_IN:
        p.setError(InvalidIteration)
        return
    jump p # `in`
    if p.next.kind != TK_IDENTIFIER:
        p.setError(InvalidIteration)
        return
    jump p # `items`
    let pluralIdent = p.current.value
    if p.next.line == p.current.line:
        p.setError(InvalidIndentation)
        return
    jump p

    var forBody: seq[Node]
    while p.current.pos > this.pos:
        forBody.add p.parseExpression()

    if forBody.len != 0:
        return newFor(singularIdent, pluralIdent, forBody)
    p.setError(NestableStmtIndentation)

proc parseMixinCall(p: var Parser): Node =
    result = newMixin(p.current.value)
    jump p

proc parseIncludeCall(p: var Parser): Node =
    result = newInclude(p.current.value)
    jump p

proc parseVariable(p: var Parser): Node =
    result = newVariable(p.current.value)
    jump p

proc getPrefixFn(kind: TokenKind): PrefixFunction =
    result = case kind
        of TK_INTEGER: parseInteger
        of TK_BOOL_TRUE, TK_BOOL_FALSE: parseBoolean
        of TK_STRING: parseString
        of TK_IF: parseIfStmt
        of TK_FOR: parseForStmt
        of TK_INCLUDE: parseIncludeCall
        of TK_MIXIN: parseMixinCall
        of TK_VARIABLE: parseVariable
        else: parseHtmlElement

# proc getInfixFn(kind: TokenKind): InfixFunction =
#     result = case kind:
#         of tkOperators: parseOp
#         else: nil

proc parseExpression(p: var Parser): Node =
    var prefixFunction = getPrefixFn(p.current.kind)
    var infixFunction: InfixFunction
    var leftExpression: Node = p.prefixFunction()
    if leftExpression != nil:
        result = leftExpression

proc parseExpressionStmt(p: var Parser): Node =
    let tk = p.current
    var exp = p.parseExpression()
    if exp == nil and p.hasError():
        # quit parsing and prompt the error
        return

    if exp.nodeType == NTHtmlElement:
        if exp.meta.pos == 0:
            if p.parentNode == nil:     # set a new parent node
                p.parentNode = exp
            else:                       # add parent node to ast
                result = ast.newExpression(p.parentNode)
                p.parentNode = nil
        else:
            p.parentNode.nodes.add exp
            return
    result = ast.newExpression exp

proc parseStatement(p: var Parser): Node =
    case p.current.kind:
        of TK_VARIABLE:    result = p.parseAssignment()
        else:              result = p.parseExpressionStmt()

proc parse*(engine: TimEngine, code, path: string, templateType: TimlTemplateType): Parser =
    ## Parse a new Tim document
    var iHandler = resolve(code, path, engine, templateType)
    var p: Parser = Parser(engine: engine)
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
