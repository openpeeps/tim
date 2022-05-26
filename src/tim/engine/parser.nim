# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import std/[json, jsonutils]
import std/[tables, with]

import tokens, ast, data
from resolver import resolveWithImports, hasError, getError, getErrorLine, getErrorColumn, getFullCode

from meta import TimEngine, TimlTemplate, getContents, getFileData
from std/strutils import `%`, isDigit, join, endsWith

type
    Parser* = object
        offsetLine: int
        engine: TimEngine
            ## Holds current TimEngine instance
        lexer: Lexer
            ## A TokTok Lexer instance
        filePath: string
            ## Path to current ``.timl`` template. This is mainly used
            ## by internal Parser procs for 
        includes: seq[string]
            ## A sequence of file paths that are included
            ## in current ``.timl`` template
        prev, current, next: TokenTuple
        statements: Program
            ## Holds the entire Abstract Syntax Tree representation
        htmlStatements: OrderedTable[int, HtmlNode]
            ## An ``OrderedTable`` of ``HtmlNode``
        prevln, currln, nextln: TokenTuple
            ## Holds TokenTuple representation of heads from prev, current and next 
        parentNode, prevNode: HtmlNode
            ## While in ``walk`` proc, we temporarily hold ``parentNode``
            ## and prevNode for each iteration.
        data: Data
            ## An instance of Data to be evaluated on runtime.
        enableJit: bool
            ## Determine if current Timl document needs a JIT compilation.
            ## This is set true when current document contains either a
            ## conditional statement or other dynamic statements.
        warnings: seq[Warning]
            ## Holds warning messages related to current HTML Rope
            ## These messages are shown during compile-time
            ## via command line interface.
        error: string
            ## A parser/lexer error

    WarningType = enum
        Semantics

    Warning = ref object
        ## Object for creating warnings during compile time
        warnType: WarningType
        element: string
        line: int

# proc newWarning[C: Compiler](c: var C, warnType: WarningType, element: string) =
#     ## Create a new Warning to be shown during compile time
#     let warning = new Warning
#     with warning:
#         warnType = warnType
#         element = element
#         line = line
#     c.warnings.add(warning)

proc setError[P: Parser](p: var P, msg: string) =
    ## Set parser error
    p.error = "Error ($2:$3): $1" % [msg, $p.current.line, $p.current.col]

proc setError[P: Parser](p: var P, msg: string, line, col: int) =
    ## Set a Parser error on a specific line and col number
    p.current.line = line
    p.current.col = col
    p.setError(msg)

proc hasError*[T: Parser](p: var T): bool =
    ## Determine if current parser instance has any errors
    result = p.error.len != 0 or p.lexer.hasError()

proc getError*[T: Parser](p: var T): string = 
    ## Retrieve current parser instance errors,
    ## including lexer-side unrecognized token errors
    if p.lexer.hasError():
        result = p.lexer.getError()
    elif p.error.len != 0:
        result = p.error

proc parse*[T: TimEngine](engine: T, code, path: string, data: JsonNode = %*{}): Parser

proc getStatements*[T: Parser](p: T, asNodes = true): Program =
    ## Return all HtmlNodes available in current document
    result = p.statements

proc getHtmlStatements*[P: Parser](p: P): OrderedTable[int, HtmlNode] =
    ## Return all ``HtmlNode`` available in current document
    result = p.htmlStatements

# proc getStatements*[T: Parser](p: T, asJsonNode = true): string =
#     ## Return all HtmlNodes available in current document as JsonNode
#     result = toJson(p.statements)

proc getStatementsStr*[T: Parser](p: T, prettyString = false): string = 
    ## Retrieve all HtmlNodes available in current document as stringified JSON
    # if prettyString: 
    #     result = pretty(p.getStatements(asJsonNode = true))
    # else:
    result = pretty(toJson(p.statements))

template jit[T: Parser](p: var T) =
    ## Enable jit flag When current document contains
    ## either conditionals, or variable assignments
    if p.enableJit == false: p.enableJit = true

proc hasJIT*[T: Parser](p: var T): bool {.inline.} =
    ## Determine if current timl template requires a JIT compilation
    result = p.enableJit == true

proc jump[T: Parser](p: var T, offset = 1) =
    var i = 0
    while offset != i: 
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

proc nindent(depth: int = 0, shouldIncDepth = false): int {.inline.} =
    ## Sets indentation based on depth of nodes when minifier is turned off.
    ## TODO Support for base indent number: 2, 3, or 4 spaces (default 2)
    if shouldIncDepth:
        result = if depth == 0: 0 else: depth * 2
    else:
        result = depth

const selfClosingTags* = {TK_AREA, TK_BASE, TK_BR, TK_COL, TK_EMBED,
                         TK_HR, TK_IMG, TK_INPUT, TK_LINK, TK_META,
                         TK_PARAM, TK_SOURCE, TK_TRACK, TK_WBR}

proc isNestable*[T: TokenTuple](token: T): bool =
    ## Determine if current token can contain more nodes
    ## TODO filter only nestable tokens
    result = token.kind notin {
        TK_IDENTIFIER, TK_ATTR, TK_ATTR_CLASS, TK_ATTR_ID, TK_ASSIGN, TK_COLON,
        TK_INTEGER, TK_STRING, TK_NEST_OP, TK_UNKNOWN, TK_EOF, TK_NONE
    } + selfClosingTags

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
            p.setError("Invalid nest missing `>` token for inline declarations")
            break
    elif p.current.isNestable() and not p.next.isNestable():
        if p.next.kind notin {TK_NEST_OP, TK_ATTR_CLASS, TK_ATTR_ID, TK_IDENTIFIER, TK_COLON}:
            p.setError("Invalid nest declaration")
            break

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

template parseNewNode(p: var Parser, ndepth: var int) =
    ## Parse a new HTML Node with HTML attributes, if any
    !> p # Ensure a good nest
    p.prevln = p.currln
    p.currln = p.current
    var shouldIncDepth = true
    if p.current.col == 0:
        ndepth = 0
    elif p.prevNode != nil:
        if p.prevNode.meta.column == p.current.col:
            ndepth = p.prevNode.meta.indent
            shouldIncDepth = false

    let htmlNodeType = getHtmlNodeType(p.current)
    htmlNode = new HtmlNode
    with htmlNode:
        nodeType = htmlNodeType
        nodeName = getSymbolName(htmlNodeType)
        meta = (column: p.current.col, indent: nindent(ndepth, shouldIncDepth), line: p.current.line)
    
    if shouldIncDepth:
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
    p.prevNode = htmlNode

template parseNewSubNode(p: var Parser, ndepth: var int) =
    p.prevln = p.currln
    p.currln = p.current
    var shouldIncDepth = true
    if p.prevNode != nil:
        if p.prevNode.meta.column == p.current.col:
            ndepth = p.prevNode.meta.indent
            shouldIncDepth = false
        # elif p.current.col > p.prevNode.meta.column:

    let htmlNodeType = getHtmlNodeType(p.current)
    var htmlSubNode = new HtmlNode
    with htmlSubNode:
        nodeType = htmlNodeType
        nodeName = htmlNodeType.getSymbolName
        meta = (column: p.current.col, indent: nindent(ndepth, shouldIncDepth), line: p.current.line)
    
    if p.next.kind == TK_NEST_OP:
        jump p
    elif p.next.isAttributeOrText():
        # parse html attributes, `id`, `class`, or any other custom attributes
        jump p
        p.setHTMLAttributes(htmlSubNode)
    else: jump p
    if shouldIncDepth:
        inc ndepth
    deferChildSeq.add htmlSubNode

template parseInlineNest(p: var Parser, depth: var int) =
    ## Walk along the line and collect single-line nests
    while p.current.line == p.currln.line:
        if p.current.isEOF: break
        elif p.hasError(): break
        !> p
        if p.current.isNestable():
            p.parseNewSubNode(depth)
        else: jump p

proc walk(p: var Parser) =
    var 
        ndepth = 0
        htmlNode: HtmlNode
        conditionNode: ConditionalNode
        isMultidimensional: bool
        childNodes: HtmlNode
        deferChildSeq: seq[HtmlNode]
    p.statements = Program()
    while p.hasError() == false and p.current.kind != TK_EOF:
        if p.current.isConditional():
            conditionNode = newConditionNode(p.current)
            p.parseCondition(conditionNode)
            continue
        if not p.htmlStatements.hasKey(p.current.line):
            if p.current.isNestable():
                p.parseNewNode(ndepth)
            else:
                if p.current.kind in selfClosingTags:
                    p.parseNewSubNode(ndepth)
                else:
                    p.setError("Invalid HTMLElement name \"$1\"" % [p.current.value])
                    break
        p.parseInlineNest(ndepth)
        if htmlNode != nil:
            if deferChildSeq.len != 0:
                childNodes = rezolveInlineNest(deferChildSeq)
                setLen(deferChildSeq, 0)
            if childNodes != nil:
                p.htmlStatements[p.currln.line].nodes.add(childNodes)
                childNodes = nil
            var node = new Node
            with node:
                nodeName = getSymbolName(HtmlElement)
                nodeType = HtmlElement
                htmlNode = p.htmlStatements[p.currln.line]
            p.statements.nodes.add(node)
        elif conditionNode != nil:
            echo "condition"    # TODO support conditional statements
        else:
            # ndepth = 0
            p.parentNode = nil

proc parse*[T: TimEngine](engine: T, code, path: string, data: JsonNode = %*{}): Parser =
    var importHandler = resolveWithImports(code, path)
    var p: Parser = Parser(engine: engine)

    if importHandler.hasError():
        p.setError(importHandler.getError(), importHandler.getErrorLine(), importHandler.getErrorColumn())
        return p
    else:
        p.lexer = Lexer.init(importHandler.getFullCode())
        p.data = Data.init(data)
        p.filePath = path

    p.current = p.lexer.getToken()
    p.next    = p.lexer.getToken()
    p.currln  = p.current
    
    p.walk()
    p.lexer.close()
    result = p
