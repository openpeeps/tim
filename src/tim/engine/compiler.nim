
import ./ast
import jsony, emitter
import std/[json, ropes, tables, with]
from std/strutils import toLowerAscii, `%`, indent
from std/algorithm import reverse, SortOrder

type
    DeferTag = tuple[tag: string, meta: MetaNode, isInlineElement: bool]

    Compiler* = object
        index, line, offset: int
            ## The line number that is currently compiling
        minified: bool
            ## Whether to minify the output HTML or not
        program: Program
            ## All Nodes statements under a ``Program`` object instnace
        tags: Table[int, seq[DeferTag]]
            ## A sequence of tuple containing ``tag`` and its ``HtmlNode``
            ## representation used for rendering the closing tags
            ## after resolving multi dimensional nodes
        html: Rope
            ## A rope containg the entire HTML code

const NewLine = "\n"

proc indentLine[T: Compiler](compiler: var T, meta: MetaNode, fixTail = false, brAfter = true, shiftIndent = false) =
    if meta.indent != 0:
        var i: int
        i = meta.indent
        if fixTail:
            i = if shiftIndent: i - 4 else: i - 2
        if brAfter:
            add compiler.html, indent(NewLine, i)
        else:
            add compiler.html, indent("", i)
    else: add compiler.html, NewLine

proc indentEndLine[C: Compiler](compiler: var C, meta: MetaNode, fixTail = false, brAfter = false, shiftIndent = false) =
    if meta.indent != 0:
        var i: int
        i = meta.indent
        if fixTail:
            i = if shiftIndent: i - 2 else: i - 2
        if brAfter:
            add compiler.html, indent("\n", i)
        else:
            add compiler.html, indent("", i)

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
    if not compiler.minified:
        compiler.indentLine(node.meta)
    add compiler.html, "<" & toLowerAscii(tag)
    if node.hasIDAttribute:
        compiler.writeIDAttribute(node)
    if node.hasAttributes:
        compiler.writeAttributes(node)
    add compiler.html, ">"

# proc closeTag[T: Compiler](compiler: var T, tag: string, metaNode: MetaNode, brAfter = true, shiftIndent = false) =
#     ## Close an HTML tag
#     add compiler.html, "</" & toLowerAscii(tag) & ">"
#     if not compiler.minified:
#         compiler.indentEndLine(metaNode, fixTail = true, brAfter = brAfter, shiftIndent = shiftIndent)

proc getLineIndent[C: Compiler](compiler: C, index: int): int =
    result = compiler.program.nodes[index].htmlNode.meta.indent

proc getNextLevel[C: Compiler](c: var C, currentIndent, index: int): tuple[child, same, upper: bool] =
    try:
        let nextIndent = c.getLineIndent(index + 1)
        if nextIndent > currentIndent:
            result = (true, false, false)
        elif nextIndent == currentIndent:
            result = (false, true, false)
        elif nextIndent < currentIndent:
            result = (false, false, true)
    except:
        result = (false, false, false)

proc deferTag[C: Compiler](c: var C, tag: string, htmlNode: HtmlNode) =
    ## Add closing tags to ``tags`` table for resolving later
    let lineno = htmlNode.meta.line
    if not c.tags.hasKey(lineno):
        c.tags[lineno] = newSeq[DeferTag]()
    var isInlineElement: bool
    if htmlNode.nodes.len != 0:
        isInlineElement = htmlNode.nodes[0].nodeType == Htmltext
    c.tags[lineno].add (tag: tag, meta: htmlNode.meta, isInlineElement: isInlineElement)

proc resolveDeferredTags[C: Compiler](c: var C, lineno: int, withOffset = false) =
    ## Resolve all deferred closing tags and add to current ``Rope``
    let lineNo = if withOffset: lineno - c.offset else: lineno
    if c.tags.hasKey(lineNo):
        var tags = c.tags[lineNo]
        tags.reverse()
        for tag in tags:
            let htmlTag = "</" & toLowerAscii(tag.tag) & ">"
            if tag.isInlineElement:     add c.html, htmlTag
            else:                       add c.html, indent("\n" & htmlTag, tag.meta.indent)
            c.tags[lineNo].delete(0)
        c.tags.del(lineNo)

proc resolveAllDeferredTags[C: Compiler](c: var C) =
    ## Resolve remained deferred closing tags and add to current ``Rope``
    var i = 0
    var linesno: seq[int]
    for k in c.tags.keys():
        linesno.add(k)

    while true:
        if c.tags.len == 0: break
        let lineno = linesno[i]
        var tags = c.tags[lineno]
        tags.reverse()
        for tag in tags:
            let htmlTag = "</" & toLowerAscii(tag.tag) & ">"
            if tag.isInlineElement:     add c.html, htmlTag
            else:                       add c.html, indent("\n" & htmlTag, tag.meta.indent)
            c.tags[lineno].delete(0)
        c.tags.del(lineno)
        inc i

proc writeLine[C: Compiler](c: var C, nodes: seq[HtmlNode], index: var int)

proc writeElement[C: Compiler](c: var C, htmlNode: HtmlNode, index: var int) =
    ## Write an HTML element and its sub HTML nodes, if any
    let tag = htmlNode.nodeName
    c.openTag(tag, htmlNode)
    c.deferTag(tag, htmlNode)
    if htmlNode.nodes.len != 0:
        c.writeLine(htmlNode.nodes, index)

proc writeTextElement[C: Compiler](c: var C, node: HtmlNode) =
    ## Write ``HtmlText`` content
    add c.html, node.text

proc writeLine[C: Compiler](c: var C, nodes: seq[HtmlNode], index: var int) =
    ## Write current line of HTML Nodes.
    for node in nodes:
        case node.nodeType:
        of HtmlText:
            c.writeTextElement(node)
            c.resolveDeferredTags(node.meta.line)
        else:
            c.writeElement(node, index)

proc writeLine[C: Compiler](c: var C, fixBr = false) =
    ## Main procedure for writing HTMLelements line by line
    ## based on given BSON Abstract Syntax Tree
    var index = 0
    c.line = 1
    let nodeslen = c.program.nodes.len

    while true:
        let node = c.program.nodes[index]
        if node.nodeType == NodeType.HtmlElement:
            let tag = node.htmlNode.nodeName
            c.openTag(tag, node.htmlNode)
            c.deferTag(tag, node.htmlNode)
            if node.htmlNode.nodes.len != 0:
                c.writeLine(node.htmlNode.nodes, index)
            let next = c.getNextLevel(node.htmlNode.meta.indent, index)
            if next.upper:
                c.resolveDeferredTags(node.htmlNode.meta.line, true)
                c.offset = 0
            elif next.same:
                inc c.offset
                c.resolveDeferredTags(node.htmlNode.meta.line)
            elif next.child:
                inc c.offset
            else:
                c.resolveAllDeferredTags()
                break
        inc index

proc init*[C: typedesc[Compiler]](Compiler: C, astNodes: string, minified: bool, asNode = true): Compiler =
    ## By default, Tim engine output is pure minified.
    ## Set `minified` to false to disable this feature.
    var c = Compiler(minified: minified)
    c.program = fromJson(astNodes, Program)

    Event.listen("timl.jit.enabled") do(args: varargs[Arg]):
        # Listener for enabling the JIT Compiler
        # triggered when a `.timl` template contains any
        # dynamic data that needs to be computed at runtime,
        # like for example conditional statements, data assignments
        # and so on...
        echo "TODO"

    c.writeLine(fixBr = true)
    result = c