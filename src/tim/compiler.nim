# ⚡️ High-performance compiled
# template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim

import ./ast
from ./parser import Parser
from std/strutils import toLowerAscii, `%`, indent

type
    Compiler* = object
        nodes: seq[HtmlNode]
        solved: int
        html: string

proc hasNodes[T: HtmlNode](node: T): bool =
    ## Determine if current HtmlNode has any child nodes
    result = node.nodes.len != 0

proc hasAttributes[T: HtmlNode](node: T): bool =
    ## Determine if current HtmlNode has any HTML attributes attached 
    result = node.attributes.len != 0

proc writeAttributes[T: Compiler](c: var T, node: HtmlNode) =
    ## Inser HTML Attributes to current HtmlNode
    let total: int = (node.attributes.len - 1)
    for k, attr in node.attributes.pairs():
        add c.html, ("$1=\"$2\"" % [attr.name, attr.value]).indent(1)
        if k != total: add c.html, " "

proc hasIDAttribute[T: HtmlNode](node: T): bool =
    ## Determine if current HtmlNode has an HTML ID attribute attached to it
    result = node.id != nil

proc writeIDAttribute[T: Compiler](c: var T, node: HtmlNode) =
    ## Insert ID HTML attribute to current HtmlNode
    add c.html, ("id=\"$1\"" % [node.id.value]).indent(1)

proc writeTagStart[T: Compiler](c: var T, node: HtmlNode) =
    ## Open tag of the current HtmlNode element
    ## TODO Handle indentation when minification disabled
    add c.html, "<" & toLowerAscii(node.nodeName)
    if node.hasIDAttribute():   c.writeIDAttribute(node)
    if node.hasAttributes():    c.writeAttributes(node)
    add c.html, ">"

proc writeTagEnd[T: Compiler](c: var T, node: HtmlNode) =
    ## Close the current HtmlNode element
    ## TODO Handle self closers in HtmlNode based on HtmlNodeType
    ## TODO Handle indentation when minification disabled
    add c.html, "</" & toLowerAscii(node.nodeName) & ">"

proc writeText[T: Compiler](c: var T, node: HtmlNode) =
    ## Add HtmlNode to final HTML output
    add c.html, node.text

proc getHtml*[T: Compiler](c: T): string =
    ## Return compiled timl as html. By default the output is minfied,
    ## Set `minified` to `false` for regular output.
    result = c.html

proc program[T: Compiler](c: var T, childNodes: seq[HtmlNode] = @[], minified = true) =
    ## Start "compile" the current HtmlNode document
    ## By default, Tim engine output is pure minified.
    ## Set `minified` to false to disable this feature.
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
    compile.program(minified = false)
    
    echo compile.getHtml()