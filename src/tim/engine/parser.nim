# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import std/[tables, json, jsonutils]

import tokens, ast
from resolver import resolve, hasError, getError,
                    getErrorLine, getErrorColumn, getFullCode

from meta import TimEngine, TimlTemplate, TimlTemplateType
from std/strutils import `%`, isDigit, join, endsWith, parseInt, parseBool, parseFloat

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
    # InfixFunction = proc(p: var Parser, left: Node): Node
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
    InvalidArrayIndex = "Invalid array access missing index"
    InvalidAccessorDeclaration = "Invalid accessor declaration"
    InvalidScopeVarContext = "Invalid usage of $this in this context"
    InvalidGlobalVarContext = "Invalid usage of $app in this context"
    NestableStmtIndentation = "Nestable statement requires indentation"
    TypeMismatch = "Type mismatch: x is type of $1 but y: $2"

const
    tkComparables = {TK_VARIABLE, TK_STRING, TK_INTEGER, TK_BOOL_TRUE, TK_BOOL_FALSE}
    tkOperators = {TK_EQ, TK_NEQ, TK_LT, TK_LTE, TK_GT, TK_GTE}
    tkConditionals = {TK_IF, TK_ELIF, TK_ELSE, TK_IN, TK_OR}
    tkLoops = {TK_FOR, TK_IN}
    tkCalc = {TK_PLUS, TK_MINUS, TK_DIVIDE, TK_MULTI}
    tkCall = {TK_INCLUDE, TK_MIXIN}
    tkNone = (TK_NONE, "", 0,0,0,0)
    tkSpecial = {TK_DOT, TK_COLON, TK_LCURLY, TK_RCURLY,
                  TK_LPAR, TK_RPAR, TK_ATTR_ID, TK_ASSIGN, TK_COMMA,
                  TK_AT, TK_NOT, TK_AND} + tkCalc + tkOperators + tkLoops
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

    tkHtml = {
        TK_A, TK_ABBR, TK_ACRONYM, TK_ADDRESS, TK_APPLET, TK_AREA, TK_ARTICLE, TK_ASIDE,
        TK_AUDIO, TK_BOLD, TK_BASE, TK_BASEFONT, TK_BDI, TK_BDO, TK_BIG, TK_BLOCKQUOTE,
        TK_BODY, TK_BR, TK_BUTTON, TK_CANVAS, TK_CAPTION, TK_CENTER, TK_CITE, TK_CODE,
        TK_COL, TK_COLGROUP, TK_DATA, TK_DATA, TK_DATALIST, TK_DD, TK_DEL, TK_DETAILS,
        TK_DFN, TK_DIALOG, TK_DIR, TK_DOCTYPE, TK_DL, TK_DT, TK_EM, TK_EMBED, TK_FIELDSET,
        TK_FIGCAPTION, TK_FIGURE, TK_FONT, TK_FOOTER, TK_H1, TK_H2, TK_H3, TK_H4, TK_H5, TK_H6,
        TK_HEAD, TK_HEADER, TK_HR, TK_HTML, TK_ITALIC, TK_IFRAME, TK_IMG, TK_INPUT, TK_INS,
        TK_KBD, TK_LABEL, TK_LEGEND, TK_LI, TK_LINK, TK_MAIN, TK_MAP, TK_MARK, TK_METER,
        TK_NAV, TK_NOFRAMES, TK_NOSCRIPT, TK_OBJECT, TK_OL, TK_OPTGROUP, TK_OPTION, TK_OUTPUT,
        TK_PARAGRAPH, TK_PARAM, TK_PRE, TK_PROGRESS, TK_QUOTATION, TK_RP, TK_RT, TK_RUBY, TK_STRIKE,
        TK_SAMP, TK_SECTION, TK_SELECT, TK_SMALL, TK_SOURCE, TK_SPAN, TK_STRIKE_LONG, TK_STRONG,
        TK_STYLE, TK_SUB, TK_SUMMARY, TK_SUP, TK_TABLE, TK_TBODY, TK_TD, TK_TEMPLATE,
        TK_TEXTAREA, TK_TFOOT, TK_TH, TK_THEAD, TK_TIME, TK_TITLE, TK_TR, TK_TRACK, TK_TT, TK_UNDERLINE,
        TK_UL, TK_VAR, TK_VIDEO, TK_WBR
    }

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

proc walk(p: var Parser, offset = 1) =
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

proc isGlobalVar(tk: TokenTuple): bool = tk.value == "app"
proc isScopeVar(tk: TokenTuple): bool = tk.value == "this"

proc parseInfix(p: var Parser, infixLeft: Node, strict = false): Node =
    let tk: TokenTuple = p.current
    walk p
    let infixRight: Node = p.parseExpression()
    result = ast.newInfix(infixLeft, infixRight, getOperator(tk.kind))
    if strict:
        let lit = {NTInt, NTString, NTBool}
        if infixLeft.nodeType in lit and infixRight.nodeType in lit and (infixLeft.nodeType != infixRight.nodeType):
            p.setError(TypeMismatch % [infixLeft.nodeName, infixRight.nodeName])
            result = nil

proc parseInteger(p: var Parser): Node =
    # Parse a new `integer` node
    result = ast.newInt(parseInt(p.current.value), p.current)
    walk p

proc parseBoolean(p: var Parser): Node =
    # Parse a new `boolean` node
    result = ast.newBool(parseBool(p.current.value))
    walk p

template handleConcat() =
    while p.current.kind == TK_AND:
        if p.next.kind notin {TK_STRING, TK_VARIABLE, TK_SAFE_VARIABLE}:
            p.setError(InvalidStringConcat)
            return nil
        walk p
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
    if p.current.kind in {TK_DOT, TK_LBRA}:
        walk p
    if p.current.kind == TK_IDENTIFIER or p.current.kind notin tkSpecial and p.current.kind != TK_EOF:
        this = p.current
        walk p
        while true:
            if p.current.kind == TK_EOF: break
            # if p.current.wsno != 0 or p.current.line != this.line:
            #     p.setError(InvalidAccessorDeclaration, true)
            if p.current.kind == TK_DOT:
                walk p # .
                if p.current.kind == TK_IDENTIFIER or p.current.kind notin tkSpecial:
                    accessors.add newString(p.current)
                    walk p # .
                else: p.setError(InvalidVarDeclaration, true)
            elif p.current.kind == TK_LBRA:
                if p.next.kind != TK_INTEGER:
                    p.setError(InvalidArrayIndex, true)
                walk p # [
                if p.next.kind != TK_RBRA:
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
    if p.current.kind == TK_AND: # support infix concatenation X & Y
        handleConcat()
    if result == nil:
        result = leftNode
    jit p

proc parseSafeVariable(p: var Parser): Node =
    result = newVariable(p.current, isSafeVar = true)
    walk p
    jit p

proc getHtmlAttributes(p: var Parser): HtmlAttributes =
    # Parse all attributes and return it as a
    # `Table[string, seq[string]]`
    while true:
        if p.current.kind == TK_DOT:
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
            else:
                p.setError(InvalidClassAttribute)
                walk p
                break
        elif p.current.kind == TK_ATTR_ID:
            # Set `id=""` HTML attribute
            let attrKey = "id"
            if not result.hasKey(attrKey):
                if p.next.kind notin tkSpecial:
                    walk p
                    if p.current.kind in {TK_VARIABLE, TK_SAFE_VARIABLE}:
                        result[attrKey] = @[p.parseVariable()]
                    else: 
                        result[attrKey] = @[newString(p.current)]
                        walk p
                else: p.setError InvalidAttributeId, true
            else: p.setError DuplicateAttrId % [p.next.value], true
        elif p.current.kind in {TK_STRING, TK_VARIABLE, TK_SAFE_VARIABLE, TK_IDENTIFIER} + tkHtml and p.next.kind == TK_ASSIGN:
            let attrName = p.current.value
            walk p
            if p.next.kind notin {TK_STRING, TK_VARIABLE, TK_SAFE_VARIABLE}:
                p.setError InvalidAttributeValue % [attrName], true
            if not result.hasKey(attrName):
                walk p
                if p.current.kind == TK_STRING:
                    result[attrName] = @[newString(p.current)]
                else:
                    result[attrName] = @[p.parseVariable()]
            else:
                p.setError DuplicateAttributeKey % [attrName], true
            if p.current.line > p.prev.line or p.current.kind == TK_GT:
                break
            else:
                walk p
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
        if p.current.kind == TK_COLON:
            walk p
            if p.current.kind == TK_STRING:
                result.nodes.add p.parseString()
            elif p.current.kind in {TK_VARIABLE, TK_SAFE_VARIABLE}:
                result.nodes.add p.parseVariable()
            else:
                p.setError InvalidNestDeclaration, true
        elif p.current.kind in {TK_DOT, TK_ATTR_ID, TK_IDENTIFIER} + tkHtml:
            if p.current.line > result.meta.line:
                break # prevent bad loop
            result.attrs = p.getHtmlAttributes()
            if p.hasError():
                break
        else: break

proc parseHtmlElement(p: var Parser): Node =
    result = p.newHtmlNode()
    if p.parentNode.len == 0:
        p.parentNode.add(result)
    else:
        if result.meta.line > p.parentNode[^1].meta.line:
            p.parentNode.add(result)
    var node: Node
    # if p.current.kind == TK_MULTI:
    #     # handle inline loop, example `li * $items`
    #     if p.next.kind in {TK_VARIABLE, TK_INTEGER}:
    #         echo p.current
    #         walk p
    while p.current.kind == TK_GT:
        walk p
        if not p.current.kind.isHTMLElement():
            p.setError(InvalidNestDeclaration)
        inc p.lvl
        node = p.parseHtmlElement()
        if p.current.kind != TK_EOF and p.current.pos != 0:
            if p.current.line > node.meta.line:
                let currentParent = p.parentNode[^1]
                while p.current.pos > currentParent.meta.col:
                    if p.current.kind == TK_EOF: break
                    var subNode = p.parseExpression()
                    if subNode != nil:
                        node.nodes.add(subNode)
                    if p.current.pos < currentParent.meta.pos:
                        dec p.lvl, currentParent.meta.col div p.current.pos
                        delete(p.parentNode, p.parentNode.high)
                        break
        if node != nil:
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
    walk p
    if p.current.kind == TK_COLON: walk p
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
    walk p
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
    if p.current.kind == TK_COLON: walk p
    
    var ifBody: seq[Node]
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
    walk p
    let singularIdent = p.parseVariable()
    if p.current.kind != TK_IN:
        p.setError(InvalidIteration)
        return
    walk p # `in`
    if p.current.kind != TK_VARIABLE:
        p.setError(InvalidIteration)
        return
    let pluralIdent = p.parseVariable()
    if p.current.kind == TK_COLON:
        walk p
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
    walk p

proc parseMixinDefinition(p: var Parser): Node =
    let this = p.current
    walk p
    let ident = p.current
    result = newMixinDef(p.current)
    if p.next.kind != TK_LPAR:
        p.setError(InvalidMixinDefinition % [ident.value])
        return
    walk p, 2

    while p.current.kind != TK_RPAR:
        var paramDef: ParamTuple
        if p.current.kind == TK_IDENTIFIER:
            paramDef.key = p.current.value
            walk p
            if p.current.kind == TK_COLON:
                if p.next.kind notin {TK_TYPE_BOOL, TK_TYPE_INT, TK_TYPE_STRING}: # todo handle float
                    p.setError(InvalidIndentation % [ident.value], true)
                walk p
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
        walk p
        if p.current.kind == TK_COMMA:
            if p.next.kind != TK_IDENTIFIER:
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
    var this = p.current
    walk p
    while p.current.line == this.line:
        walk p

proc parseViewLoader(p: var Parser): Node =
    if p.templateType != Layout:
        p.setError("Trying to load a view inside a $1" % [$p.templateType])
        return
    result = newView(p.current)
    walk p

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
    var resHandle = resolve(code, path, engine, templateType)
    var p: Parser = Parser(
        engine: engine,
        memory: newTable[string, TokenTuple](),
        headliners: newTable[int, Node](),
        templateType: templateType
    )
    if resHandle.hasError():
        p.setError(resHandle.getError, resHandle.getErrorLine, resHandle.getErrorColumn)
        return p
    else:
        p.lexer = Lexer.init(resHandle.getFullCode(), allowMultilineStrings = true)
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
    #echo $p.statements
