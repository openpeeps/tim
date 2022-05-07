
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

proc indentLine[T: Compiler](c: var T, meta: MetaNode, fixTail = false, brAfter = true, shiftIndent = false) =
    if c.minified == false:
        if meta.column != 0 and meta.indent != 0:
            var i: int
            i = meta.indent
            if fixTail:
                i = if shiftIndent: i - 4 else: i - 2
            if brAfter:
                add c.html, indent("\n", i)
            else:
                add c.html, indent("", i)

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

proc closeTag[T: Compiler](compiler: var T, tag: string, metaNode: MetaNode, brAfter = true, shiftIndent = false) =
    ## Close an HTML tag
    add compiler.html, "</" & toLowerAscii(tag) & ">"
    compiler.indentLine(metaNode, fixTail = true, brAfter = brAfter, shiftIndent = shiftIndent)

proc getLineIndent[C: Compiler](compiler: C, index: int): int =
    result = compiler.program.nodes[index].htmlNode.meta.column

proc closeTagIfNotDeferred[C: Compiler](compiler: var C, htmlNode: HtmlNode, tag: string, index:int) = 
    let currentIndent = compiler.getLineIndent(index)
    try:
        let nextIndent = compiler.getLineIndent(index + 1)
        if nextIndent > currentIndent:
            compiler.deferTags.add (tag: tag, meta: htmlNode.meta)
        elif nextIndent == currentIndent:
            compiler.closeTag(tag, htmlNode.meta, shiftIndent = true, brAfter = false)
    except:
        compiler.closeTag(tag, htmlNode.meta, brAfter = true)
        if compiler.deferTags.len != 0:
            while true:
                if compiler.deferTags.len == 0: break
                let dtag = compiler.deferTags[0]
                compiler.closeTag(dtag.tag, dtag.meta, brAfter = true)
                compiler.deferTags.delete(0)

proc writeLine[T: Compiler](compiler: var T, nodes: seq[HtmlNode], index: int)

proc writeElement[T: Compiler](compiler: var T, htmlNode: HtmlNode, index: int) =
    ## Write an HTML element and its sub HTML nodes, if any
    let tag = htmlNode.nodeName
    compiler.openTag(tag, htmlNode)
    if htmlNode.nodes.len != 0:
        compiler.writeLine(htmlNode.nodes, index)
    compiler.closeTagIfNotDeferred(htmlNode, tag, index)

proc writeTextElement[T: Compiler](compiler: var T, node: HtmlNode) =
    ## Write ``HtmlText`` content
    add compiler.html, node.text

proc writeLine[T: Compiler](compiler: var T, nodes: seq[HtmlNode], index: int) =
    ## Write current line of HTML Nodes.
    for node in nodes:
        case node.nodeType:
        of HtmlText:
            compiler.writeTextElement(node)
        else:
            compiler.writeElement(node, index)

proc writeLine[C: Compiler](compiler: var C, fixBr = false) =
    ## Main procedure for writing HTMLelements line by line
    ## based on given BSON Abstract Syntax Tree
    var index = 0
    compiler.line = 1
    let nodeslen = compiler.program.nodes.len
    while index < nodeslen:
        let node = compiler.program.nodes[index]
        if node.nodeType == NodeType.HtmlElement:
            let tag = node.htmlNode.nodeName
            compiler.openTag(tag, node.htmlNode)
            if node.htmlNode.nodes.len != 0:
                compiler.writeLine(node.htmlNode.nodes, index)
            compiler.closeTagIfNotDeferred(node.htmlNode, tag, index)
        inc index

proc init*[C: typedesc[Compiler]](Compiler: C, astNodes: string, minified: bool, asNode = true): Compiler =
    ## By default, Tim engine output is pure minified.
    ## Set `minified` to false to disable this feature.
    var compiler = Compiler(minified: minified)
    compiler.program = fromJson(astNodes, Program)
    compiler.writeLine(fixBr = true)
    result = compiler