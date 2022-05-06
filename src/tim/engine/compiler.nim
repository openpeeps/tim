
import ./ast
import std/[json, ropes]
import jsony
from std/strutils import toLowerAscii, `%`, indent

type
    Compiler* = object
        index, line: int
            ## The line number that is currently compiling
        minified: bool
            ## Whether to minify the output HTML or not
        program: Program
            ## All Nodes statements under a ``Program`` object instnace
        deferTags: seq[tuple[tag: string, meta: MetaNode]]
            ## A sequence containing a ``tag`` name and its ``HtmlNode`` representation
            ## used for rendering the closing tags after resolving
            ## multi dimensional nodes
        html: Rope
            ## A rope containg HTML code

proc indentLine[T: Compiler](c: var T, meta: MetaNode, fixTail = false, isDeferred = false) =
    if c.minified == false:
        if meta.column != 0 and meta.indent != 0:
            var i: int
            i = meta.indent
            if fixTail:
                i = if isDeferred: i - 4 else: i - 2
            add c.html, indent("\n", i)

proc hasAttributes(node: HtmlNode): bool =
    ## Determine if current ``HtmlNode`` has any HTML attributes
    result = node.attributes.len != 0

proc writeAttributes[T: Compiler](c: var T, node: HtmlNode) =
    ## write one or more HTML attributes
    for attr in node.attributes.items():
        add c.html, ("$1=\"$2\"" % [attr.name, attr.value]).indent(1)

proc hasIDAttribute(node: HtmlNode): bool =
    ## Determine if current JsonNode has an HTML ID attribute attached to it
    result = node.id != nil

proc writeIDAttribute[T: Compiler](compiler: var T, node: HtmlNode) =
    ## Write an ID HTML attribute to current HTML Element
    add compiler.html, ("id=\"$1\"" % [node.id.value]).indent(1)

proc getHtml*[T: Compiler](c: T): string {.inline.} =
    ## Return compiled timl as html. By default the output is minfied,
    ## Set `minified` to `false` for regular output.
    result = $(c.html)

proc openTag[T: Compiler](compiler: var T, tag: string, node: HtmlNode) =
    ## Open tag of the current JsonNode element
    compiler.indentLine(node.meta)
    add compiler.html, "<" & toLowerAscii(tag)
    if node.hasIDAttribute:
        compiler.writeIDAttribute(node)
    if node.hasAttributes:
        compiler.writeAttributes(node)
    add compiler.html, ">"

proc closeTag[T: Compiler](compiler: var T, tag: string, metaNode: MetaNode, isDeferred = false) =
    ## Close HTML tag
    add compiler.html, "</" & toLowerAscii(tag) & ">"
    compiler.indentLine(metaNode, true, isDeferred)

proc getLineIndent[C: Compiler](compiler: C, index: int): int =
    result = compiler.program.nodes[index].htmlNode.meta.column

proc isDeferringClosingTag[C: Compiler](compiler: C, node: HtmlNode): bool =
    ## Determine if next HtmlNode is child of current HtmlNode
    ## In this case will defer the closing tag
    let index = node.meta.line - 1
    # if node.nodes.len == 1:    
    #     if node.nodes[0].nodeType == HtmlText:
    #         # echo node.nodeName
    #         return false

    let currentIndent = compiler.getLineIndent(index)
    try:
        let nextIndent = compiler.getLineIndent(index + 1)
        if nextIndent > currentIndent:
            if node.nodes.len == 1:
                if node.nodes[0].nodeType == Htmltext:
                    return false
            result = true
        elif nextIndent == currentIndent:
            result = true
    except:
        result = false

proc closeTagIfNotDeferred[C: Compiler](compiler: var C, htmlNode: HtmlNode, tag: string, lineno: int) =
    ## Handles closing tags based on depth level
    if compiler.isDeferringClosingTag(htmlNode):
        compiler.deferTags.add (tag: tag, meta: htmlNode.meta)
    else:
        compiler.closeTag(tag, htmlNode.meta)
        if compiler.deferTags.len != 0:
            var i = 0
            while true:
                if compiler.deferTags.len == 0: break
                let dtag = compiler.deferTags[i]
                compiler.closeTag(dtag.tag, dtag.meta)
                compiler.deferTags.delete(0)

proc writeLine[T: Compiler](compiler: var T, nodes: seq[HtmlNode], lineno: int)

proc writeElement[T: Compiler](compiler: var T, htmlNode: HtmlNode, lineno: int) =
    ## Write an HTML element and its sub HTML nodes, if any
    let tag = htmlNode.nodeName
    compiler.openTag(tag, htmlNode)
    if htmlNode.nodes.len != 0:
        compiler.writeLine(htmlNode.nodes, lineno)
    compiler.closeTagIfNotDeferred(htmlNode, tag, lineno)

proc writeTextElement[T: Compiler](compiler: var T, node: HtmlNode) =
    ## Write ``HtmlText`` content
    add compiler.html, node.text

proc writeLine[T: Compiler](compiler: var T, nodes: seq[HtmlNode], lineno: int) =
    ## Write current line of HTML Nodes.
    for node in nodes:
        case node.nodeType:
        of HtmlText:
            compiler.writeTextElement(node)
        else:
            compiler.writeElement(node, lineno)

proc writeLine[C: Compiler](compiler: var C, fixBr = false) =
    ## Main procedure for writing HTMLelements line by line
    ## based on given BSON Abstract Syntax Tree
    var lineno = 0
    compiler.line = 1
    let nodeslen = compiler.program.nodes.len
    while lineno < nodeslen:
        let node = compiler.program.nodes[lineno]
        if node.nodeType == NodeType.HtmlElement:
            let tag = node.htmlNode.nodeName
            compiler.openTag(tag, node.htmlNode)
            if node.htmlNode.nodes.len != 0:
                compiler.writeLine(node.htmlNode.nodes, lineno)
            compiler.closeTagIfNotDeferred(node.htmlNode, tag, lineno)
        inc lineno

proc init*[C: typedesc[Compiler]](Compiler: C, astNodes: string, minified: bool, asNode = true): Compiler =
    ## By default, Tim engine output is pure minified.
    ## Set `minified` to false to disable this feature.
    var compiler = Compiler(minified: minified)
    compiler.program = fromJson(astNodes, Program)
    compiler.writeLine(fixBr = true)
    result = compiler