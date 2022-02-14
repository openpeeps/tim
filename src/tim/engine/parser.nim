# High-performance, compiled template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim

import std/[json, jsonutils]
import ./tokens, ./lexer, ./ast, ./interpreter
import ../utils
import ./utils/parseutils

from std/strutils import `%`, isDigit

type
    Parser* = object
        lexer: Lexer
        prev, current, next: TokenTuple
        error: string
        statements: seq[HtmlNode]
        prevln, currln, nextln: int
        parentNode: HtmlNode
        interpreter: Interpreter

proc setError[T: Parser](p: var T, msg: string) = p.error = "Error ($2:$3): $1" % [msg, $p.current.line, $p.current.col]
proc hasError*[T: Parser](p: var T): bool = p.error.len != 0
proc getError*[T: Parser](p: var T): string = p.error

proc jump[T: Parser](p: var T, offset = 1) =
    var i = 0
    while offset > i: 
        p.prev = p.current
        p.current = p.next
        p.next = p.lexer.getToken()
        inc i

proc isElement(): bool =
    ## Determine if current token is an HTML Element
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

proc toJsonStr(nodes: HtmlNode) =
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
        TK_ATTR, TK_ATTR_CLASS, TK_ATTR_ID, TK_ASSIGN, TK_COLON,
        TK_INTEGER, TK_STRING, TK_NEST_OP, TK_INVALID, TK_EOF, TK_NONE
    }

proc isConditional*[T: TokenTuple](token: T): bool =
    ## Determine if current token is part of Conditional Tokens
    ## as TK_IF, TK_ELIF, TK_ELSE
    result = token.kind in {TK_IF, TK_ELIF, TK_ELSE}

template setHTMLAttributes[T: Parser](p: var T, htmlNode: HtmlNode): untyped =
    ## Set HTML attributes for current HtmlNode, this template covers
    ## all kind of attributes, including `id`, and `class` or custom.
    var id: IDAttribute
    while true:
        if p.current.kind == TK_ATTR_CLASS and p.next.kind == TK_IDENTIFIER:
            htmlNode.attributes.add(HtmlAttribute(name: "class", value: p.next.value))
            jump p, 2
        elif p.current.kind == TK_ATTR_ID and p.next.kind == TK_IDENTIFIER:
            if htmlNode.hasID():
                p.setError("Elements can hold a single ID attribute.")
            id = IDAttribute(value: p.next.value)
            if id != nil: htmlNode.id = id
            jump p, 2
        elif p.current.kind == TK_IDENTIFIER and p.next.kind == TK_ASSIGN:
            let attrName = p.current.value
            jump p
            if p.next.kind != TK_STRING:
                p.setError("Missing value for \"$1\" attribute" % [attrName])
                break
            htmlNode.attributes.add(HtmlAttribute(name: attrName, value: p.next.value))
            jump p, 2
        elif p.current.kind == TK_COLON:
            if p.next.kind != TK_STRING:
                p.setError("Missing string content for \"$1\" node" % [p.prev.value])
                break
            else:
                let htmlTextNode = HtmlNode(
                    nodeType: HtmlText,
                    nodeName: getSymbolName(HtmlText),
                    text: p.next.value,
                    meta: (column: p.next.col, indent: p.next.wsno, line: p.next.line)
                )
                htmlNode.nodes.add(htmlTextNode)
            jump p
            break
        else: break

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
    while true:
        if p.current.kind == TK_IF and p.next.kind != TK_VARIABLE:
            p.setError("Missing variable identifier for conditional statement")
            break
        jump p
        let tokenVar = p.current
        var varNode: VariableNode = p.parseVariable(tokenVar)

        echo pretty(toJson(varNode), 4)

        jump p
        if varNode == nil: break    # and prompt "Undeclared identifier" error
        elif p.current.kind notin {TK_EQ, TK_NEQ}:
            p.setError("Invalid conditional. Missing comparison operator")
            break
        elif p.next.kind == TK_VARIABLE:
            var varNode: VariableNode = p.parseVariable(p.next)
            if varNode == nil: break
        elif p.next.kind != TK_STRING:
            p.setError("Invalid conditional. Missing comparison value")
            break
        break

proc walk(p: var Parser) =
    var ndepth = 0
    var htmlNode: HtmlNode
    var conditionNode: ConditionalNode
    while p.hasError() == false and p.current.kind != TK_EOF:
        while p.current.isConditional():
            let conditionType = getConditionalNodeType(p.current)
            conditionNode = ConditionalNode(conditionType: conditionType)
            p.parseCondition(conditionNode)
            jump p

        while p.current.isNestable():
            let htmlNodeType = getHtmlNodeType(p.current)
            htmlNode = HtmlNode(
                nodeType: htmlNodeType,
                nodeName: getSymbolName(htmlNodeType),
                meta: (column: p.current.col, indent: nindent(ndepth), line: p.current.line)
            )
            jump p
            p.setHTMLAttributes(htmlNode)     # set available html attributes
            inc ndepth

        skipNilElement()

        # Collects the parent HtmlNode which is a headliner
        # Set current HtmlNode as parentNode. This is the headliner
        # that wraps the entire line
        if htmlNode != nil and p.parentNode == nil:
            p.parentNode = htmlNode

        var lazySequence: seq[HtmlNode]
        var child, childNodes: HtmlNode
        while p.current.line == p.currln:
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
            if p.current.kind == TK_EOF: break

        if lazySequence.len != 0:
            var i = 0
            var maxlen = (lazySequence.len - 1)
            while true:
                if i == maxlen: break
                lazySequence[(maxlen - (i + 1))].nodes.add(lazySequence[^1])
                lazySequence.delete( (maxlen - i) )
                inc i
            childNodes = lazySequence[0]
        if childNodes != nil and p.parentNode != nil:
            p.parentNode.nodes.add(childNodes)
            childNodes = nil

        registerNode(conditionNode)

        if p.current.line > p.currln:
            p.prevln = p.currln
            p.currln = p.current.line
            ndepth = 0
    jump p

proc getStatements*[T: Parser](p: T): string = 
    ## Retrieve all HtmlNodes available in current document as stringified JSON
    # result = pretty(toJson(p.statements))
    result = ""

proc getStatements*[T: Parser](p: T, asNodes: bool): seq[HtmlNode] =
    ## Return all HtmlNodes available in current document
    result = p.statements

proc parse*(contents: string, data: JsonNode): Parser =
    var p: Parser = Parser(lexer: Lexer.init(contents))
    p.interpreter = Interpreter.init(data = data)
    p.current = p.lexer.getToken()
    p.next    = p.lexer.getToken()
    p.currln  = p.current.line
    p.walk()

    assert isEqualBool(true, true) == true
    assert isNotEqualBool(false, true) == true

    assert isEqualString("a", "a") == true
    assert isNotEqualString("a", "b") == true
    assert isNotEqualFloat(12.000, 12.000) == false

    result = p
