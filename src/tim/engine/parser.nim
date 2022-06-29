# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import std/[json, jsonutils]
import std/[tables, with]

import tokens, ast, data
from resolver import resolveWithImports, hasError, getError, getErrorLine, getErrorColumn, getFullCode

from meta import TimEngine, TimlTemplate, TimlTemplateType, getContents, getFileData
from std/strutils import `%`, isDigit, join, endsWith

type
    Parser* = object
        depth: int
            ## Incremented depth of levels while parsing inline nests
        baseIndent: int
            ## The preferred indentation size, It can be either 2 or 4
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
        htmlStatements: OrderedTable[int, HtmlNode]
            ## An `OrderedTable` of `HtmlNode`
        deferredStatements: OrderedTable[int, HtmlNode]
            ## An `OrderedTable of `HtmlNode` holding deferred elements
        prevln, currln, nextln: TokenTuple
            ## Holds TokenTuple representation of heads from prev, current and next 
        parentNode, prevNode: HtmlNode
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

const
    InvalidIndentation = "Invalid indentation"
    DuplicateClassName = "Duplicate class entry found for \"$1\""
    InvalidAttributeId = "Invalid ID attribute"
    InvalidAttributeValue = "Missing value for \"$1\" attribute"
    DuplicateAttributeKey = "Duplicate attribute name for \"$1\""
    InvalidTextNodeAssignment = "Expect text assignment for \"$1\" node"
    UndeclaredVariable = "Undeclared variable \"$1\""
    InvalidIterationMissingVar = "Invalid iteration missing variable identifier"
    InvalidIteration = "Invalid iteration"
    InvalidConditionalStmt = "Invalid conditional statement"
    InvalidInlineNest = "Invalid inline nest missing `>`"
    InvalidNestDeclaration = "Invalid nest declaration"
    InvalidHTMLElementName = "Invalid HTMLElement name \"$1\""

template setError[P: Parser](p: var P, msg: string, breakStmt: bool) =
    ## Set parser error
    p.error = "Error ($2:$3): $1" % [msg, $p.current.line, $p.current.col]
    break

template setError[P: Parser](p: var P, msg: string) =
    ## Set parser error
    p.error = "Error ($2:$3): $1" % [msg, $p.current.line, $p.current.col]

proc setError[P: Parser](p: var P, msg: string, line, col: int) =
    ## Set a Parser error on a specific line and col number
    p.current.line = line
    p.current.col = col
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

proc parse*[T: TimEngine](engine: T, code, path: string, templateType: TimlTemplateType, data: JsonNode = %*{}): Parser

proc getStatements*[P: Parser](p: P, asNodes = true): Program =
    ## Return all HtmlNodes available in current document
    result = p.statements

proc getHtmlStatements*[P: Parser](p: P): OrderedTable[int, HtmlNode] =
    ## Return all `HtmlNode` available in current document
    result = p.htmlStatements

proc getStatementsStr*[P: Parser](p: P, prettyString = false): string = 
    ## Retrieve all HtmlNodes available in current document as stringified JSON
    # if prettyString: 
    #     result = pretty(p.getStatements(asJsonNode = true))
    # else:
    result = pretty(toJson(p.statements))

template jit[P: Parser](p: var P) =
    ## Enable jit flag When current document contains
    ## either conditionals, or variable assignments
    if p.enableJit == false: p.enableJit = true

proc hasJIT*[P: Parser](p: var P): bool {.inline.} =
    ## Determine if current timl template requires a JIT compilation
    result = p.enableJit == true

proc getBaseIndent*[P: Parser](p: var P): int {.inline.} =
    ## Get the preferred indentation size
    result = p.baseIndent

proc jump[P: Parser](p: var P, offset = 1) =
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

const svgSelfClosingTags = {TK_SVG_PATH, TK_SVG_CIRCLE, TK_SVG_POLYLINE, TK_SVG_ANIMATE,
                            TK_SVG_ANIMATETRANSFORM, TK_SVG_ANIMATEMOTION,
                            TK_SVG_FE_BLEND, TK_SVG_FE_COLORMATRIX, TK_SVG_FE_COMPOSITE,
                            TK_SVG_FE_CONVOLVEMATRIX, TK_SVG_FE_DISPLACEMENTMAP}
const selfClosingTags = {TK_AREA, TK_BASE, TK_BR, TK_COL, TK_EMBED,
                         TK_HR, TK_IMG, TK_INPUT, TK_LINK, TK_META,
                         TK_PARAM, TK_SOURCE, TK_TRACK, TK_WBR} + svgSelfClosingTags

proc isNestable*[T: TokenTuple](token: T): bool =
    ## Determine if current token can contain more nodes
    ## TODO filter only nestable tokens
    result = token.kind notin {
        TK_IDENTIFIER, TK_ATTR, TK_ATTR_CLASS, TK_ATTR_ID, TK_ASSIGN, TK_COLON,
        TK_INTEGER, TK_STRING, TK_NEST_OP, TK_UNKNOWN, TK_EOF, TK_NONE
    }

proc getParentLine[P: Parser](p: var P): int =
    if p.current.col == 0:
        p.depth = 0
        result = 0
    elif p.parentNode != nil:
        if p.parentNode.meta.column > p.current.col:
            # Handle `Upper` levels
            var found: bool
            var prevlineno = p.parentNode.meta.childOf
            while true:
                if p.htmlStatements.hasKey(prevlineno):
                    let prevline = p.htmlStatements[prevlineno]
                    if prevline.meta.column == p.current.col:
                        p.depth = prevline.meta.indent
                        p.current.col = p.depth
                        result = prevline.meta.childOf
                        found = true
                        break
                dec prevlineno
            if not found:
                result = p.current.line
        elif p.parentNode.meta.column == p.current.col:
            # Handle `Same` levels
            p.depth = p.parentNode.meta.depth
            result = p.parentNode.meta.childOf
            p.current.col = p.depth
        elif p.current.col > p.parentNode.meta.column:
            # Handle `Child` levels
            if p.parentNode.meta.column == 0:
                inc p.depth, 4
            else:
                p.depth = p.parentNode.meta.indent
                inc p.depth, 4
            result = p.parentNode.meta.line
            p.current.col = p.depth

include ./parseutils

proc isConditional*[T: TokenTuple](token: T): bool =
    ## Determine if current token is part of Conditional Tokens
    ## as TK_IF, TK_ELIF, TK_ELSE
    result = token.kind in {TK_IF, TK_ELIF, TK_ELSE}

proc isIteration*[T: TokenTuple](token: T): bool =
    result = token.kind == TK_FOR

proc isEOF[T: TokenTuple](token: T): bool {.inline.} =
    ## Determine if given token kind is TK_EOF
    result = token.kind == TK_EOF

template `!>`[P: Parser](p: var P): untyped =
    ## Ensure nest token `>` exists for inline statements
    if p.current.isNestable() and p.next.isNestable():
        if p.current.line == p.next.line and p.current.kind != TK_AND:
            p.setError InvalidInlineNest, true
    elif p.current.isNestable() and not p.next.isNestable():
        # echo p.next
        if p.next.kind notin {TK_NEST_OP, TK_ATTR_CLASS, TK_ATTR_ID, TK_IDENTIFIER, TK_COLON, TK_VARIABLE}:
            p.setError InvalidNestDeclaration, true

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

template parseNewNode(p: var Parser, isSelfClosing = false) =
    ## Parse a new HTML Node with HTML attributes, if any
    !> p # Ensure a good nest
    p.currln = p.current
    let initialCol = p.current.col
    let nodeIndent = p.current.col
    let childOfLineno = p.getParentLine()
    let htmlNodeType = getHtmlNodeType(p.current)
    htmlNode = new HtmlNode
    with htmlNode:
        nodeType = htmlNodeType
        nodeName = getSymbolName(htmlNodeType)
        meta = (column: initialCol, indent: p.current.col, line: p.current.line, childOf: childOfLineno, depth: p.depth)

    if p.next.kind == TK_NEST_OP:
        jump p
    elif p.next.isAttributeOrText():
        jump p
        p.setHTMLAttributes(htmlNode, nodeIndent)     # set available html attributes
    else: jump p
    p.htmlStatements[htmlNode.meta.line] = htmlNode
    p.parentNode = htmlNode
    p.prevln = p.currln
    # TODO, check if `isSelfClosing` and prevent
    # nestables or text assignment for self closing tags.

template parseNewSubNode(p: var Parser) =
    p.currln = p.current
    let initialCol = p.current.col
    p.current.col = 4 + p.depth
    
    let htmlNodeType = getHtmlNodeType(p.current)
    # let childOfLine = p.getParentLine()
    var htmlSubNode = new HtmlNode
    with htmlSubNode:
        nodeType = htmlNodeType
        nodeName = htmlNodeType.getSymbolName
        meta = (column: initialCol, indent: p.current.col, line: p.current.line, childOf: 0, depth: p.depth)

    if p.next.kind == TK_NEST_OP:
        jump p
    elif p.next.isAttributeOrText():
        # parse html attributes, `id`, `class`, or any other custom attributes
        jump p
        p.setHTMLAttributes(htmlSubNode)
    else: jump p

    deferChildSeq.add htmlSubNode
    p.prevln = p.currln
    p.prevNode = htmlSubNode

template parseInlineNest(p: var Parser) =
    ## Walk along the line and collect single-line nests
    while p.current.line == p.currln.line:
        if p.current.isEOF: break
        elif p.hasError(): break
        !> p
        if p.current.isNestable():
            p.parseNewSubNode()
            inc p.depth, 4
        else: jump p

proc walk(p: var Parser) =
    var 
        shouldCloseNode: bool
        node: Node
        htmlNode: HtmlNode
        conditionNode: ConditionalNode
        iterationNode: IterationNode

        childNodes: HtmlNode
        deferChildSeq: seq[HtmlNode]
    p.statements = Program()
    jit p
    while p.hasError() == false and p.current.kind != TK_EOF:
        if p.current.isConditional():
            conditionNode = newConditionNode(p.current)
            p.parseCondition(conditionNode)
            continue
        elif p.current.isIteration():
            iterationNode = IterationNode()
            p.parseIteration(iterationNode)
            continue

        if not p.htmlStatements.hasKey(p.current.line):
            if p.current.isNestable():
                p.parseNewNode()
            else:
                if p.current.kind in selfClosingTags:
                    p.parseNewNode(isSelfClosing = true)
                else:
                    p.setError InvalidHTMLElementName % [p.current.value], true
                    break

        p.parseInlineNest()
        shouldCloseNode = true # temporary need to figure

        if htmlNode != nil:
            if deferChildSeq.len != 0:
                childNodes = rezolveInlineNest(deferChildSeq)
                setLen(deferChildSeq, 0)
            if childNodes != nil:
                p.htmlStatements[p.currln.line].nodes.add(childNodes)
                childNodes = nil
            node = new Node
            with node:
                nodeName = getSymbolName(HtmlElement)
                nodeType = HtmlElement
                htmlNode = p.htmlStatements[p.currln.line]
            if iterationNode != nil:
                iterationNode.nodes.add(node)
            else:
                p.statements.nodes.add(node)
        if shouldCloseNode:
            if iterationNode != nil:
                node = new Node
                with node:
                    nodeName = getSymbolName(LoopStatement)
                    nodeType = LoopStatement
                    iterationNode = iterationNode
                p.statements.nodes.add(node)
            node = nil

proc parse*[T: TimEngine](engine: T, code, path: string, templateType: TimlTemplateType, data: JsonNode = %*{} ): Parser =
    var importHandler = resolveWithImports(code, path, templateType)
    var p: Parser = Parser(engine: engine)
    # echo importHandler.getFullCode()
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
