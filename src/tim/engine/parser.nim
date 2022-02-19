# High-performance, compiled template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim
import std/[json, jsonutils, tables]
import ./tokens, ./lexer, ./ast, ./interpreter

from ./meta import TimEngine, TimlTemplate, getContents, getFileData

import ../utils
import ./utils/parseutils

from std/strutils import `%`, isDigit, join

type
    Parser* = object
        lexer: Lexer
        prev, current, next: TokenTuple
        error: string
        statements: seq[HtmlNode]
        prevln, currln, nextln: int
        prevlnEndWithContent: bool
        parentNode: HtmlNode
        interpreter: Interpreter
        enableJit: bool

proc setError[T: Parser](p: var T, msg: string) = p.error = "Error ($2:$3): $1" % [msg, $p.current.line, $p.current.col]
proc hasError*[T: Parser](p: var T): bool = p.error.len != 0
proc getError*[T: Parser](p: var T): string = p.error

proc hasJIT*[T: Parser](p: var T): bool {.inline.} =
    ## Determine if current timl template requires a JIT compilation
    result = p.enableJit == true

proc jump[T: Parser](p: var T, offset = 1) =
    var i = 0
    while offset > i: 
        p.prev = p.current
        p.current = p.next
        p.next = p.lexer.getToken()
        inc i

proc isElement(): bool =
    ## Determine if current token is a HTML Element
    ## TODO
    discard

proc isAttributeName(): bool =
    ## Determine if current token is an attribute name based on its siblings.
    ## For example `title` is by default considered an HTMLElement,
    ## but it can be an HTMLAttribute too.
    ## TODO
    discard

proc isInline[T: TokenTuple](token: T): bool =
    ## Determine if current token is an inliner HTML Node
    ## such as TK_SPAN, TK_EM, TK_I, TK_STRONG TK_LINK and so on.
    ## TODO
    discard

proc hasID[T: HtmlNode](node: T): bool {.inline.} =
    ## Determine if current HtmlNode has an ID attribute
    result = node.id != nil

proc getID[T: HtmlNode](node: T): string {.inline.} =
    ## Retrieve the HTML ID attribute, if any
    result = if node.id != nil: node.id.value else: ""

proc toJsonStr*(nodes: HtmlNode) =
    ## Print a stringified representation of the current Abstract Syntax Tree
    echo pretty(toJson(nodes))

proc nindent(depth: int = 0): int {.inline.} =
    ## Sets indentation based on depth of nodes when minifier is turned off.
    ## TODO Support for base indent number: 2, 3, or 4 spaces (default 2)
    result = if depth == 0: 0 else: 2 * depth

proc isNestable*[T: TokenTuple](token: T): bool =
    ## Determine if current token can contain more nodes
    ## TODO filter only nestable tokens
    result = token.kind notin {
        TK_IDENTIFIER, TK_ATTR, TK_ATTR_CLASS, TK_ATTR_ID, TK_ASSIGN, TK_COLON,
        TK_INTEGER, TK_STRING, TK_NEST_OP, TK_INVALID, TK_EOF, TK_NONE
    }

proc isConditional*[T: TokenTuple](token: T): bool =
    ## Determine if current token is part of Conditional Tokens
    ## as TK_IF, TK_ELIF, TK_ELSE
    result = token.kind in {TK_IF, TK_ELIF, TK_ELSE}

proc isIdent[T: TokenTuple](token: T): bool =
    result = token.kind == TK_IDENTIFIER

proc isChild[T: Parser](p: var T, childNode, parentNode: TokenTuple): bool =
    result = childNode.col > parentNode.col
    if result == true:
        result = (childNode.col and 1) != 1 and (parentNode.col and 1) != 1
        if result == false:
            p.setError("Invalid indentation. Use 2 or 4 spaces to indent your rules")

proc isEOF[T: TokenTuple](token: T): bool {.inline.} =
    ## Determine if given token kind is TK_EOF
    result = token.kind == TK_EOF

proc getPrev[T: Parser](p: var T, h: OrderedTable[int, TokenTuple]): TokenTuple = 
    ## Retrieve previous line from headliners
    let prevln = if p.current.line == 1: 0 else: p.current.line - 1
    result = h[prevln]

proc isBadNest[T: Parser](p: var T, h: OrderedTable[int, TokenTuple]): bool =
    ## Determine if current headline has a bad nest. This applies
    ## only if previous line ends with a string content
    if p.prevlnEndWithContent == true:
        let prev = p.getPrev(h)
        result = prev.col < p.current.col

template setHTMLAttributes[T: Parser](p: var T, htmlNode: HtmlNode): untyped =
    ## Set HTML attributes for current HtmlNode, this template covers
    ## all kind of attributes, including `id`, and `class` or custom.
    var id: IDAttribute
    var hasAttributes: bool
    var attributes: Table[string, seq[string]]
    while true:
        if p.current.kind == TK_ATTR_CLASS and p.next.kind == TK_IDENTIFIER:
            # TODO check for wsno for `.` token and prevent mess
            hasAttributes = true
            if attributes.hasKey("class"):
                attributes["class"].add(p.next.value)
            else:
                attributes["class"] = @[p.next.value]
            jump p, 2
        elif p.current.kind == TK_ATTR_ID and p.next.kind == TK_IDENTIFIER:
            # TODO check for wsno for `#` token
            if htmlNode.hasID():
                p.setError("Elements can hold a single ID attribute.")
            id = IDAttribute(value: p.next.value)
            if id != nil: htmlNode.id = id
            jump p, 2
        elif p.current.kind == TK_IDENTIFIER and p.next.kind == TK_ASSIGN:
            # TODO check for wsno for other `attr` token
            let attrName = p.current.value
            jump p
            if p.next.kind != TK_STRING:
                p.setError("Missing value for \"$1\" attribute" % [attrName])
                break
            if attributes.hasKey(attrName):
                p.setError("Duplicate attribute name for \"$1\" identifier" % [attrName])
            else:
                attributes[attrName] = @[p.next.value]
                hasAttributes = true
            jump p, 2
        elif p.current.kind == TK_COLON:
            if p.next.kind != TK_STRING:
                p.setError("Missing string content for \"$1\" node" % [p.prev.value])
                break
            else:
                jump p
                if (p.current.line == p.next.line) and not p.next.isEOF:
                    p.setError("Bad indentation after enclosed string")      # TODO a better error message?
                    break
                let htmlTextNode = HtmlNode(
                    nodeType: HtmlText,
                    nodeName: getSymbolName(HtmlText),
                    text: p.current.value,
                    meta: (column: p.current.col, indent: p.current.wsno, line: p.current.line)
                )
                htmlNode.nodes.add(htmlTextNode)
                p.prevlnEndWithContent = true
            break
        else: break

    if hasAttributes:
        for attrName, attrValues in attributes.pairs:
            htmlNode.attributes.add(HtmlAttribute(name: attrName, value: attrValues.join(" ")))
        hasAttributes = false
    clear(attributes)

proc parseVariable[T: Parser](p: var T, tokenVar: TokenTuple): VariableNode =
    ## Parse and validate given VariableNode
    var varNode: VariableNode
    let varName: string = tokenVar.value
    if not p.interpreter.hasVar(varName):
        p.setError("Undeclared variable for \"$1\" identifier" % [varName])
        return nil
    result = newVariableNode(varName, p.interpreter.getVar(varName))

template parseCondition[T: Parser](p: var T, conditionNode: ConditionalNode): untyped =
    ## Parse and validate given ConditionalNode 
    let currln: int = p.current.line
    var compToken: TokenTuple
    var varNode1, varNode2: VariableNode
    var comparatorNode: ComparatorNode
    while true:
        if p.current.kind == TK_IF and p.next.kind != TK_VARIABLE:
            p.setError("Missing variable identifier for conditional statement")
            break
        jump p
        varNode1 = p.parseVariable(p.current)
        jump p
        if varNode1 == nil: break    # and prompt "Undeclared identifier" error
        elif p.current.kind in {TK_EQ, TK_NEQ}:
            compToken = p.current
            if p.next.kind == TK_VARIABLE:
                jump p
                varNode2 = p.parseVariable(p.current)
            comparatorNode = newComparatorNode(compToken, @[varNode1, varNode2])
            conditionNode.comparatorNode = comparatorNode
        elif p.next.kind != TK_STRING:
            p.setError("Invalid conditional. Missing comparison value")
            break
        break

template `!>`[T: Parser](p: var T): untyped =
    ## Ensure nest token `>` exists for inline statements
    if p.current.isNestable() and p.next.isNestable():
        if p.current.line == p.next.line:
            p.setError("Missing `>` token for single line nest")
            break

template jit[T: Parser](p: var T): untyped =
    ## Enable jit flag When current document contains
    ## either conditionals, or variable assignments
    if p.enableJit == false: p.enableJit = true

proc walk(p: var Parser) =
    var ndepth = 0
    var htmlNode: HtmlNode
    var conditionNode: ConditionalNode
    var heads: OrderedTable[int, TokenTuple]
    while p.hasError() == false and p.current.kind != TK_EOF:
        # jit p
        while p.current.isConditional():
            jit p
            conditionNode = newConditionNode(p.current, meta = (column: p.current.col, indent: nindent(ndepth), line: p.current.line))
            p.parseCondition(conditionNode)
            jump p

        var origin: TokenTuple = p.current
        while p.current.isNestable():
            !> p # Check for missing `>` nest token, in case next token is nestable too
            if not heads.hasKey(p.current.line):
                if p.isBadNest(heads):
                    p.setError("Bad indentation. Previous line is not nestable")
                heads[p.current.line] = p.current

            let htmlNodeType = getHtmlNodeType(p.current)
            htmlNode = HtmlNode(
                nodeType: htmlNodeType,
                nodeName: getSymbolName(htmlNodeType),
                meta: (column: p.current.col, indent: nindent(ndepth), line: p.current.line)
            )
            # echo p.isChild(p.current, origin)
            jump p
            p.setHTMLAttributes(htmlNode)     # set available html attributes
            inc ndepth

        skipNilElement()        # todo template
        
        if htmlNode != nil and p.parentNode == nil:
            p.parentNode = htmlNode

        # Walks the entire line and collect all HtmlNodes from current nest
        var lazySequence: seq[HtmlNode]
        var child, childNodes: HtmlNode

        if p.current.line > p.currln:
            p.prevln = p.currln
            p.currln = p.current.line
            ndepth = 0

        while p.current.line == p.currln:
            if p.current.kind == TK_EOF: break
            !> p # Check for missing `>` nest token, in case next token is nestable too
            if p.current.isNestable():
                let htmlNodeType = getHtmlNodeType(p.current)
                child = HtmlNode(
                    nodeType: htmlNodeType,
                    nodeName: getSymbolName(htmlNodeType),
                    meta: (column: p.current.col, indent: nindent(ndepth), line: p.current.line))
                jump p
                p.setHTMLAttributes(child)     # set available html attributes
                lazySequence.add(child)
                inc ndepth
            jump p

        if lazySequence.len != 0:
            var i = 0
            var maxlen = (lazySequence.len - 1)
            while true:
                if i == maxlen: break
                lazySequence[(maxlen - (i + 1))].nodes.add(lazySequence[^1])
                lazySequence.delete( (maxlen - i) )
                inc i
            childNodes = lazySequence[0]
        
        if conditionNode != nil:
            discard
            # echo pretty(toJson(conditionNode))
            # p.parentNode.add(conditionNode)
        elif childNodes != nil and p.parentNode != nil:
            p.parentNode.nodes.add(childNodes)
            childNodes = nil

        registerNode(conditionNode)

        if p.current.line > p.currln:
            p.prevln = p.currln
            p.currln = p.current.line
            ndepth = 0
        else: jump p

proc getStatements*[T: Parser](p: T, asNodes = true): seq[HtmlNode] =
    ## Return all HtmlNodes available in current document
    result = p.statements

proc getStatements*[T: Parser](p: T, asJsonNode = true): JsonNode =
    ## Return all HtmlNodes available in current document as JsonNode
    result = toJson(p.statements)

proc getStatementsStr*[T: Parser](p: T, prettyString = false): string = 
    ## Retrieve all HtmlNodes available in current document as stringified JSON
    if prettyString: 
        result = pretty(p.getStatements(asJsonNode = true))
    else:
        result = $(toJson(p.statements))

proc parse*[T: TimEngine](engine: var T, templateObject: TimlTemplate, data: JsonNode = %*{}): Parser {.thread.} =
    var p: Parser = Parser(lexer: Lexer.init(templateObject.getSourceCode))
    p.interpreter = Interpreter.init(data = data)

    p.current = p.lexer.getToken()
    p.next    = p.lexer.getToken()
    p.currln  = p.current.line

    p.walk()
    result = p
