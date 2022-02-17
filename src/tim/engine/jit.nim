# High-performance, compiled template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim
import std/json
from std/strutils import toLowerAscii, `%`, indent

type
    JIT* = object
        minified: bool
        nodes: JsonNode
        solved: int
        html: string

proc indentIfEnabled[T: JIT](c: var T, meta: JsonNode, fixTail = false) =
    if c.minified == false:
        if meta["column"].getInt != 0 and meta["indent"].getInt != 0:
            var i: int
            i = meta["indent"].getInt
            if fixTail: i = i - 2
            add c.html, "\n".indent(i)

proc hasNodes[T: JsonNode](node: T): bool =
    ## Determine if current JsonNode has any child nodes
    result = node["nodes"].len != 0

proc hasAttributes[T: JsonNode](node: T): bool =
    ## Determine if current JsonNode has any HTML attributes attached 
    result = node["attributes"].len != 0

proc writeAttributes[T: JIT](c: var T, node: JsonNode) =
    ## Inser HTML Attributes to current JsonNode
    let total: int = (node["attributes"].len - 1)
    for aobj in node["attributes"].items:
        for attrName in aobj.keys():
            add c.html, ("$1=\"$2\"" % [attrName, aobj[attrName].getStr]).indent(1)

proc hasIDAttribute[T: JsonNode](node: T): bool =
    ## Determine if current JsonNode has an HTML ID attribute attached to it
    result = node["id"].kind != JNull

proc writeIDAttribute[T: JIT](c: var T, node: JsonNode) =
    ## Insert ID HTML attribute to current JsonNode
    add c.html, ("id=\"$1\"" % [node["id"]["value"].getStr]).indent(1)

proc writeTagStart[T: JIT](c: var T, node: JsonNode) =
    ## Open tag of the current JsonNode element
    ## TODO Handle indentation when minification disabled
    c.indentIfEnabled(node["meta"])
    add c.html, "<" & toLowerAscii(node["nodeName"].getStr)
    if node.hasIDAttribute():   c.writeIDAttribute(node)
    if node.hasAttributes():    c.writeAttributes(node)
    add c.html, ">"

proc writeTagEnd[T: JIT](c: var T, node: JsonNode, fixTail = false) =
    ## Close the current JsonNode element
    ## TODO Handle self closers in JsonNode based on JsonNodeType
    ## TODO Handle indentation when minification disabled
    add c.html, "</" & toLowerAscii(node["nodeName"].getStr) & ">"
    c.indentIfEnabled(node["meta"], true)

proc writeText[T: JIT](c: var T, node: JsonNode) =
    ## Add JsonNode to final HTML output
    add c.html, node["text"].getStr

proc getHtml*[T: JIT](c: T): string {.inline.} =
    ## Return compiled timl as html. By default the output is minfied,
    ## Set `minified` to `false` for regular output.
    result = c.html

proc program[T: JIT](c: var T, childNodes: JsonNode = %*[], fixBr = false) =
    ## Start "compile" the current JsonNode document
    var i = 0
    let nodeseq = if childNodes.len == 0: c.nodes else: childNodes
    while i < nodeseq.len:
        let mainNode: JsonNode = nodeseq[i]
        if mainNode["nodeName"].getStr == "TEXT":
            c.writeText(mainNode)
        else:
            if fixBr: add c.html, "\n"
            c.writeTagStart(mainNode)                   # start tag
            if mainNode.hasNodes():                     # parse child nodes, if any
                c.program(mainNode["nodes"])               # TODO iteration over recursion
            c.writeTagEnd(mainNode, true)               # end tag
        inc i

proc init*[T: typedesc[JIT]](jit: T, jsonContents: JsonNode, minified: bool, asNode = true): JIT =
    ## By default, Tim engine output is pure minified.
    ## Set `minified` to false to disable this feature.
    var c = jit(nodes: jsonContents, minified: minified)
    c.program(fixBr = true)
    result = c
