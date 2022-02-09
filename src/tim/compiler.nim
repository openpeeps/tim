# ⚡️ High-performance compiled
# template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim

import ./ast
from ./parser import Parser
from std/strutils import toLowerAscii, `%`

type
    Compiler* = object
        nodes: seq[HtmlNode]
        solved: int
        html: string

proc hasNodes[T: HtmlNode](node: T): bool =
    ## Determine if current HtmlNode has any child nodes
    result = node.nodes.len != 0

proc writeAttributes[T: Compiler](c: var T, node: HtmlNode) =
    let total: int = (node.attributes.len - 1)
    for k, attr in node.attributes.pairs():
        add c.html, "$1=\"$2\"" % [attr.name, attr.value]
        if k != total: add c.html, " "

proc hasAttributes[T: HtmlNode](node: T): bool =
    result = node.attributes.len != 0

proc writeTagStart[T: Compiler](c: var T, node: HtmlNode) =
    ## Open tag of the current HtmlNode element
    add c.html, "<" & toLowerAscii(node.nodeName)
    if node.hasAttributes():
        add c.html, " "
        c.writeAttributes(node)
    add c.html, ">"

proc writeTagEnd[T: Compiler](c: var T, node: HtmlNode) =
    ## Close the current HtmlNode element
    add c.html, "</" & toLowerAscii(node.nodeName) & ">"

proc writeText[T: Compiler](c: var T, node: HtmlNode) =
    add c.html, node.text

proc getHtml*[T: Compiler](c: T, minified = true): string =
    ## Return compiled timl as html. By default the output is minfied,
    ## Set `minified` to `false` for regular output.
    result = c.html

proc program[T: Compiler](c: var T, childNodes: seq[HtmlNode] = @[]) =
    var i = 0
    let nodeseq = if childNodes.len == 0: c.nodes else: childNodes
    while i < nodeseq.len:
        let mainNode: HtmlNode = nodeseq[i]
        if mainNode.nodeType == HtmlText:
            c.writeText(mainNode)
        else:
            c.writeTagStart(mainNode)   # start tag
            if mainNode.hasNodes():     # parse child nodes, if any
                c.program(mainNode.nodes)
            c.writeTagEnd(mainNode)     # end tag
        inc i

proc init*[T: typedesc[Compiler]](C: T, parser: Parser) =
    var compile = C(nodes: parser.getStatements(nodes = true))
    compile.program()
    echo compile.getHTML(minified = false)