import ./ast
import std/[json, ropes, tables]

from std/strutils import toLowerAscii, `%`, indent, multiReplace
from std/algorithm import reverse, SortOrder
from ./meta import TimlTemplateType

type
    DeferTag = tuple[tag: string, meta: MetaNode, isInlineElement: bool]

    TypeLevel = enum
        None, Upper, Same, Child

    Compiler* = object
        index, line, offset: int
            ## The line number that is currently compiling
        program: Program
            ## All Nodes statements under a `Program` object instance
        tags: OrderedTable[int, seq[DeferTag]]
            ## A sequence of tuple containing `tag` name and `HtmlNode`
            ## representation used for rendering the closing tags
            ## after resolving multi dimensional nodes
        minified: bool
            ## Whether to minify the final HTML output (disabled by default)
        html, htmlTails: Rope
            ## A rope containg the final HTML output
        templateType: TimlTemplateType
        baseIndent: int
        data: JsonNode
        safeEscape: bool

const NewLine = "\n"

method getIndent(compiler: var Compiler, nodeIndent: int): int =
    if compiler.baseIndent == 2:
        return int(nodeIndent / compiler.baseIndent)
    result = nodeIndent

proc indentLine[C: Compiler](compiler: var C, meta: MetaNode, fixTail, skipBr = false) =
    if meta.indent != 0:
        if not skipBr:
            add compiler.html, NewLine
        add compiler.html, indent("", compiler.getIndent(meta.indent))
    else:
        if not skipBr:
            add compiler.html, NewLine

proc hasAttributes(node: HtmlNode): bool =
    ## Determine if current `HtmlNode` has any HTML attributes
    result = node.attributes.len != 0

proc writeAttributes[C: Compiler](c: var C, node: HtmlNode) =
    ## write one or more HTML attributes
    for attr in node.attributes.items():
        add c.html, ("$1=\"$2\"" % [attr.name, attr.value]).indent(1)

proc hasIDAttribute(node: HtmlNode): bool =
    ## Determine if current JsonNode has an HTML ID attribute attached to it
    result = node.id != nil

proc writeIDAttribute[C: Compiler](compiler: var C, node: HtmlNode) =
    ## Write an ID HTML attribute to current HTML Element
    add compiler.html, ("id=\"$1\"" % [node.id.value]).indent(1)

proc openTag[C: Compiler](compiler: var C, tag: string, node: HtmlNode, skipBr = false) =
    ## Open tag of the current JsonNode element
    if not compiler.minified:
        compiler.indentLine(node.meta, skipBr = skipBr)
    add compiler.html, "<" & toLowerAscii(tag)
    if node.hasIDAttribute:
        compiler.writeIDAttribute(node)
    if node.hasAttributes:
        compiler.writeAttributes(node)
    if node.nodeType.isSelfClosingTag:
        add compiler.html, "/"
    add compiler.html, ">"

proc closeTag[C: Compiler](c: var C, tag: DeferTag, templateType = View) =
    ## Close an HTML tag
    let htmlTag = "</" & toLowerAscii(tag.tag) & ">"
    var closingTag: string
    if tag.isInlineElement or c.minified:
        closingTag = htmlTag
    else:
        closingTag = indent("\n" & htmlTag, c.getIndent(tag.meta.indent))
    if templateType == View:
        add c.html, closingTag
    else:
        add c.htmlTails, closingTag

proc getNextLevel[C: Compiler](c: var C, currentIndent, index: int): tuple[meta: MetaNode, typeLevel: TypeLevel] =
    try:
        let next = c.program.nodes[index + 1].htmlNode
        let nextIndent = next.meta.indent
        if nextIndent > currentIndent:
            result = (next.meta, Child)
        elif nextIndent == currentIndent:
            result = (next.meta, Same)
        elif nextIndent < currentIndent:
            result = (next.meta, Upper)
    except:
        result = (meta: (0, 0, 0, 0, 0), typeLevel: None)

proc deferTag[C: Compiler](c: var C, tag: string, htmlNode: HtmlNode) =
    ## Add closing tags to `tags` table for resolving later
    if not htmlNode.nodeType.isSelfClosingTag:
        let lineno = htmlNode.meta.line
        if not c.tags.hasKey(lineno):
            c.tags[lineno] = newSeq[DeferTag]()
        var isInlineElement: bool
        if htmlNode.nodes.len != 0:
            isInlineElement = htmlNode.nodes[0].nodeType == Htmltext
        c.tags[lineno].add (tag: tag, meta: htmlNode.meta, isInlineElement: isInlineElement)

proc resolveDeferredTags(c: var Compiler, lineno: int, withOffset = false) =
    ## Resolve all deferred closing tags and add to current `Rope`
    if c.tags.hasKey(lineno):
        var tags = c.tags[lineno]
        tags.reverse() # tags list
        for tag in tags:
            c.closeTag(tag)
            c.tags[lineno].delete(0)
        c.tags.del(lineno)

proc resolveAllDeferredTags(c: var Compiler) =
    ## Resolve remained deferred closing tags and add to current `Rope`
    var i = 0
    var linesno: seq[int]
    for k in c.tags.keys():
        linesno.add(k)
    linesno.reverse()
    while true:
        if c.tags.len == 0: break
        let lineno = linesno[i]
        var tags = c.tags[lineno]
        tags.reverse()
        for tag in tags:
            c.closeTag(tag, c.templateType)
            c.tags[lineno].delete(0)
        c.tags.del(lineno)
        inc i

proc resolveTag(c: var Compiler, lineno: int) =
    ## Resolve a deferred tag by specified line number
    if c.tags.hasKey(lineno):
        var tags = c.tags[lineno]
        tags.reverse()
        for tag in tags:
            c.closeTag(tag)
            c.tags[lineno].delete(0)
        c.tags.del(lineno)

proc getAstLine(nodeName: string, indentSize: int) =
    # Used for debug-only
    echo indent(nodeName, indentSize)

proc writeLine(c: var Compiler, nodes: seq[HtmlNode], index: var int)

proc writeElement(c: var Compiler, htmlNode: HtmlNode, index: var int) =
    ## Write an HTML element and its sub HTML nodes, if any
    let tag = htmlNode.nodeName
    c.openTag(tag, htmlNode)
    c.deferTag(tag, htmlNode)   # TODO handle Self Closing Elements
    if htmlNode.nodes.len != 0:
        c.writeLine(htmlNode.nodes, index)

proc writeTextElement(c: var Compiler, node: HtmlNode) =
    ## Write `HtmlText` content
    add c.html, node.text
    if node.concat.len != 0:
        for nodeConcat in node.concat:
            add c.html, indent(nodeConcat.text, 1)

proc writeVarTextElement(c: var Compiler, node: HtmlNode) =
    ## Write `HtmlText` content from a variable
    var varValue = c.data[node.varAssignment.getVarName()].getStr
    if c.safeEscape:
        varValue = multiReplace(varValue,
            ("^", "&amp;"),
            ("<", "&lt;"),
            (">", "&gt;"),
            ("\"", "&quot;"),
            ("'", "&#x27;"),
            ("`", "&grave;")
        )
    add c.html, varValue

proc writeLine(c: var Compiler, nodes: seq[HtmlNode], index: var int) =
    ## Write current line of HTML Nodes.
    for node in nodes:
        case node.nodeType:
        of HtmlText:
            if node.varAssignment != nil:
                c.writeVarTextElement(node)
            else:
                c.writeTextElement(node)
            c.resolveDeferredTags(node.meta.line)
        else:
            c.writeElement(node, index)

proc writeHtmlElement(c: var Compiler, node: Node, index: var int, skipBr = false) =
    let tag = node.htmlNode.nodeName
    c.openTag(tag, node.htmlNode, skipBr = skipBr)
    c.deferTag(tag, node.htmlNode)

    if node.htmlNode.nodes.len != 0:
        c.writeLine(node.htmlNode.nodes, index)
    let next = c.getNextLevel(node.htmlNode.meta.indent, index)
    case next.typeLevel:
    of Upper:
        var i = index
        while true:
            var prev: MetaNode
            try:
                prev = c.program.nodes[i - 1].htmlNode.meta
            except IndexDefect:
                break
            if prev.column == next.meta.column:
                if c.tags.hasKey(prev.line):
                    # defTagLines.add prev.line
                    c.resolveTag(prev.line)
                break
            elif prev.column > next.meta.column:
                if c.tags.hasKey(prev.line):
                    # defTagLines.add prev.line
                    c.resolveTag(prev.line)
            dec i
    of Same:
        c.resolveTag(node.htmlNode.meta.line)
    of Child:
        discard
    else:
        c.resolveAllDeferredTags()

proc writeLine(c: var Compiler) =
    ## Main procedure for writing HTMLelements line by line
    ## based on given BSON Abstract Syntax Tree
    var index = 0
    let nodeslen = c.program.nodes.len
    if nodeslen != 0:
        c.line = c.program.nodes[0].htmlNode.meta.line # start line
    while true:
        if index == nodeslen: break
        let node = c.program.nodes[index]
        if node.nodeType == NodeType.HtmlElement:
            c.writeHtmlElement(node, index, index == 0)
        inc index

proc getHtmlJit*(c: Compiler): string {.inline.} =
    ## Returns compiled HTML based on dynamic data
    result = $(c.html)

proc getHtml*(c: Compiler): string {.inline.} =
    ## Returns compiled HTML for static `timl` templates
    result = $(c.html)

proc getHtmlTails*(c: Compiler): string {.inline.} =
    ## Retrieve the tails and deferred elements for current layout
    result = $(c.htmlTails)

proc init*(compilerInstance: typedesc[Compiler], astProgram: Program,
        minified: bool, templateType: TimlTemplateType,
        baseIndent: int, data = %*{}, safeEscape = true): Compiler =
    ## Create a new Compiler instance
    var c = compilerInstance(
        minified: minified,
        templateType: templateType,
        baseIndent: baseIndent,
        data: data,
        safeEscape: safeEscape
    )
    c.program = astProgram
    c.writeLine()
    result = c