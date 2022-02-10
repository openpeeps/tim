# ⚡️ High-performance compiled
# template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim

import std/[json, jsonutils]
import ./lexer, ./tokens, ./ast
from std/strutils import `%`

type
    Parser* = object
        lexer: Lexer
        prev, current, next: TokenTuple
        error: string
        statements: seq[HtmlNode]
        prevln, currln, nextln: int

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

proc isNestable[T: TokenTuple](token: T): bool =
    ## Determine if current token can contain more nodes
    ## TODO filter only nestable tokens
    return token.kind in {TK_ARTICLE, TK_DIV, TK_SECTION, TK_SPAN}

proc isInline[T: TokenTuple](token: T): bool =
    ## Determine if current token is an inliner HTML Node
    ## such as TK_SPAN, TK_EM, TK_I, TK_STRONG TK_LINK and so on.
    ## TODO
    discard

proc walk(p: var Parser, pNode: HtmlNode = nil, recursive = false): HtmlNode =
    ## Magically walk and collect HtmlNodes, assign HtmlAttributes
    ## for creating document node of the current timl page
    var htmlNode: HtmlNode = nil
    var parentNode: HtmlNode = pNode
    var isRecursive = recursive
    while p.hasError() == false and p.current.kind != TK_EOF:
        if p.current.isNestable():
            let htmlNodeType = getHtmlNodeType(p.current)
            htmlNode = HtmlNode(nodeType: htmlNodeType, nodeName: getSymbolName(htmlNodeType))
            var attrs: seq[HtmlAttribute]
            var id: IDAttribute
            jump p
            while true:
                if p.current.kind == TK_ATTR_CLASS and p.next.kind == TK_IDENTIFIER:
                    attrs.add(HtmlAttribute(name: "class", value: p.next.value))
                    jump p, 2
                elif p.current.kind == TK_ATTR_ID and p.next.kind == TK_IDENTIFIER:
                    id = IDAttribute(value: p.next.value)
                    jump p, 2
                elif p.current.kind == TK_IDENTIFIER and p.next.kind == TK_ASSIGN:
                    let attrName = p.current.value
                    jump p
                    if p.next.kind != TK_STRING:
                        p.setError("Missing value for \"$1\" attribute" % [attrName])
                        break
                    attrs.add(HtmlAttribute(name: attrName, value: p.next.value))
                    jump p, 2
                elif p.current.kind == TK_CONTENT:
                    if p.next.kind != TK_STRING:
                        p.setError("Missing string content for \"$1\" node" % [p.prev.value])
                        break
                    else:
                        let htmlTextNode = HtmlNode(nodeType: HtmlText, nodeName: getSymbolName(HtmlText), text: p.next.value)
                        htmlNode.nodes.add(htmlTextNode)
                    jump p, 2 
                    break
                else: break

            htmlNode.attributes = attrs     # set available html attributes
            if id != nil:
                htmlNode.id = id                # set ID html attribute or null

        if isRecursive:
            parentNode.nodes.add(htmlNode)
        elif htmlNode != nil and isRecursive == false:
            p.statements.add(htmlNode)
        
        if p.current.line > p.currln or p.current.kind == TK_STRING:
            isRecursive = false
        elif p.current.kind in {TK_NEST_OP}:
            jump p
            discard p.walk(htmlNode, true)

        if p.current.line > p.currln:
            p.prevln = p.currln
            p.currln = p.current.line

    return htmlNode

proc getStatements*[T: Parser](p: T): string = 
    return pretty(toJson(p.statements))

proc getStatements*[T: Parser](p: T, nodes: bool): seq[HtmlNode] = p.statements

proc parse*(contents: string): Parser =
    var p: Parser = Parser(lexer: Lexer.init(contents))
    p.current = p.lexer.getToken()
    p.next    = p.lexer.getToken()
    p.currln = p.current.line
    discard p.walk()
    return p
