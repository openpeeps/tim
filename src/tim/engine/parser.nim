# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import std/[json, jsonutils]
import std/[tables, with]
import ./tokens, ./lexer, ./ast, ./interpreter

from ./meta import TimEngine, TimlTemplate, getContents, getFileData
from std/strutils import `%`, isDigit, join

type
    Parser* = object
        lexer: Lexer
        prev, current, next: TokenTuple
        error: string
        statements: Program
        htmlStatements: OrderedTable[int, HtmlNode]
        prevln, currln, nextln: TokenTuple
            # Holds TokenTuple representation of heads from prev, current and next 
        prevlnEndWithContent: bool
        parentNode, prevNode, subNode, lastParent: HtmlNode
        interpreter*: Interpreter
        enableJit: bool

proc setError[T: Parser](p: var T, msg: string) =
    p.error = "Error ($2:$3): $1" % [msg, $p.current.line, $p.current.col]

proc hasError*[T: Parser](p: var T): bool =
    result = p.error.len != 0 or p.lexer.error.len != 0

proc getError*[T: Parser](p: var T): string = 
    if p.error.len != 0:
        result = p.error
    elif p.lexer.error.len != 0:
        result = p.lexer.error

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

proc isAttributeOrText(token: TokenTuple): bool =
    ## Determine if current token is an attribute name based on its siblings.
    result = token.kind in {TK_ATTR_CLASS, TK_ATTR_ID, TK_IDENTIFIER, TK_COLON}

proc hasID[T: HtmlNode](node: T): bool {.inline.} =
    ## Determine if current HtmlNode has an ID attribute
    result = node.id != nil

# proc toJsonStr*(nodes: HtmlNode) =
#     ## Print a stringified representation of the current Abstract Syntax Tree
#     echo pretty(toJson(nodes))

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

include ./parseutils

proc isConditional*[T: TokenTuple](token: T): bool =
    ## Determine if current token is part of Conditional Tokens
    ## as TK_IF, TK_ELIF, TK_ELSE
    result = token.kind in {TK_IF, TK_ELIF, TK_ELSE}

proc isEOF[T: TokenTuple](token: T): bool {.inline.} =
    ## Determine if given token kind is TK_EOF
    result = token.kind == TK_EOF

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

proc rezolveInlineNest(lazySeq: var seq[HtmlNode]): HtmlNode =
    ## Rezolve lazy sequence of nodes collected from last inline nest
    # starting from tail, each node will be assigned to its sibling node
    # until we reach the begining of the sequence
    var i = 0
    var maxlen = (lazySeq.len - 1)
    while true:
        if i == maxlen: break
        lazySeq[(maxlen - (i + 1))].nodes.add(lazySeq[^1])
        lazySeq.delete( (maxlen - i) )
        inc i
    result = lazySeq[0]

template parseNewNode(p: var Parser, ndepth: var int, isDimensional = false) =
    ## Parse a new HTML Node with HTML attributes, if any
    # !> p # Ensure a good nest
    p.prevln = p.currln
    p.currln = p.current
    let htmlNodeType = getHtmlNodeType(p.current)
    htmlNode = new HtmlNode
    with htmlNode:
        nodeType = htmlNodeType
        nodeName = getSymbolName(htmlNodeType)
        meta = (column: p.current.col, indent: nindent(ndepth), line: p.current.line)
    inc ndepth

    if p.next.kind == TK_NEST_OP:
        # set as current ``htmlNode`` as ``parentNode`` in case current
        # node has opened an inline nestable elements with `>`
        jump p
    elif p.next.isAttributeOrText():
        jump p
        p.setHTMLAttributes(htmlNode)     # set available html attributes
    else: jump p
    p.htmlStatements[htmlNode.meta.line] = htmlNode

template parseNewSubNode(p: var Parser, ndepth: var int) =
    p.prevln = p.currln
    p.currln = p.current
    let htmlNodeType = getHtmlNodeType(p.current)
    htmlNode = new HtmlNode
    with htmlNode:
        nodeType = htmlNodeType
        nodeName = htmlNodeType.getSymbolName
        meta = (column: p.current.col, indent: nindent(ndepth), line: p.current.line)
    
    if p.next.kind == TK_NEST_OP:
        jump p
    elif p.next.isAttributeOrText():
        # parse html attributes, `id`, `class`, or any other custom attributes
        jump p
        p.setHTMLAttributes(htmlNode)
    else: jump p
    inc ndepth
    deferChildSeq.add htmlNode

template parseInlineNest(p: var Parser, depth: var int) =
    ## Walk along the line and collect single-line nests
    while p.current.line == p.currln.line:
        if p.current.isEOF: break
        !> p
        if p.current.isNestable():
            p.parseNewSubNode(depth)
        else: jump p

proc walk(p: var Parser) =
    var 
        ndepth = 0
        node: Node
        htmlNode: HtmlNode
        conditionNode: ConditionalNode
        heads: OrderedTable[int, TokenTuple]
        isMultidimensional: bool

    var childNodes: HtmlNode
    var deferChildSeq: seq[HtmlNode]

    p.statements = Program()
    while p.hasError() == false and p.current.kind != TK_EOF:
        var origin: TokenTuple = p.current

        # Handle current line headliner
        if not p.htmlStatements.hasKey(p.current.line):
            if p.current.isNestable():
                p.parseNewNode(ndepth, false)
            else:
                p.setError("Invalid HTMLElement name \"$1\"" % [p.current.value])
                break

        p.parseInlineNest(ndepth)   # Handle inline nestable nodes, if any

        if htmlNode != nil:
            if deferChildSeq.len != 0:
                childNodes = rezolveInlineNest(deferChildSeq)
                setLen(deferChildSeq, 0)
            if childNodes != nil:
                p.htmlStatements[p.currln.line].nodes.add(childNodes)
                childNodes = nil
        else:
            ndepth = 0
            htmlNode = nil
            p.parentNode = nil
    for k, n in pairs(p.htmlStatements):
        node = new Node
        with node:
            nodeName = getSymbolName(HtmlElement)
            nodeType = HtmlElement
            htmlNode = n
        p.statements.nodes.add(node)

proc getStatements*[T: Parser](p: T, asNodes = true): Program =
    ## Return all HtmlNodes available in current document
    result = p.statements

# proc getStatements*[T: Parser](p: T, asJsonNode = true): string =
#     ## Return all HtmlNodes available in current document as JsonNode
#     result = toJson(p.statements)

proc getStatementsStr*[T: Parser](p: T, prettyString = false): string = 
    ## Retrieve all HtmlNodes available in current document as stringified JSON
    # if prettyString: 
    #     result = pretty(p.getStatements(asJsonNode = true))
    # else:
    result = $(toJson(p.statements))

proc parse*[T: TimEngine](engine: T, templateObject: TimlTemplate): Parser {.thread.} =
    var p: Parser = Parser(lexer: Lexer.init(templateObject.getSourceCode))
    # p.interpreter = Interpreter.init(data = data)

    p.current = p.lexer.getToken()
    p.next    = p.lexer.getToken()
    p.currln  = p.current

    p.walk()
    result = p
