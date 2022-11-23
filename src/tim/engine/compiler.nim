import ./ast, ./data
import std/[json, ropes, tables]

from std/strutils import `%`, indent, multiReplace, endsWith, join
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
            ## A sequence of tuple containing `tag` name and `Node`
            ## representation used for rendering the closing tags
            ## after resolving multi dimensional nodes
        minified: bool
            ## Whether to minify the final HTML output (disabled by default)
        html, htmlTails: Rope
            ## A rope containg the final HTML output
        templateType: TimlTemplateType
        baseIndent: int
        data: JsonNode

const NewLine = "\n"

proc getIndent(c: var Compiler, nodeIndent: int): int =
    if c.baseIndent == 2:
        return int(nodeIndent / c.baseIndent)
    result = nodeIndent

proc indentLine(c: var Compiler, meta: MetaNode, skipBr = false) =
    if meta.pos != 0:
        if not skipBr:
            add c.html, NewLine
        add c.html, indent("", c.getIndent(meta.pos))
    else:
        if not skipBr:
            add c.html, NewLine

proc hasAttributes(node: Node): bool =
    ## Determine if current `Node` has any HTML attributes
    result = node.attrs.len != 0

proc writeAttributes(c: var Compiler, node: Node) =
    ## write one or more HTML attributes
    for k, v in node.attrs.pairs():
        add c.html, ("$1=\"$2\"" % [k, join(v, " ")]).indent(1)

proc hasIDAttribute(node: Node): bool =
    ## Determine if current JsonNode has an HTML ID attribute attached to it
    result = node.attrs.hasKey("id")

proc writeIDAttribute(c: var Compiler, node: Node) =
    ## Write an ID HTML attribute to current HTML Element
    add c.html, ("id=\"$1\"" % [node.attrs["id"][0]]).indent(1)

proc openTag(c: var Compiler, tag: string, node: Node, skipBr = false) =
    ## Open tag of the current JsonNode element
    if not c.minified:
        c.indentLine(node.meta, skipBr = skipBr)
    add c.html, "<" & tag
    if node.hasIDAttribute():
        c.writeIDAttribute(node)
    if node.hasAttributes():
        c.writeAttributes(node)
    if node.issctag:
        add c.html, "/"
    add c.html, ">"

proc closeTag(c: var Compiler, node: Node, skipBr, fixTail = false) =
    ## Close an HTML tag
    if not node.issctag:
        if not fixTail and not c.minified:
            c.indentLine(node.meta, skipBr)
        add c.html, "</" & node.htmlNodeName & ">"

proc getHtmlJit*(c: Compiler): string {.inline.} =
    ## Returns compiled HTML based on dynamic data
    result = $(c.html)

proc getHtml*(c: Compiler): string {.inline.} =
    ## Returns compiled HTML for static `timl` templates
    result = $(c.html)

proc getHtmlTails*(c: Compiler): string {.inline.} =
    ## Retrieve the tails and deferred elements for current layout
    result = $(c.htmlTails)

var fixTail: bool

proc writeStrValue(c: var Compiler, node: Node) =
    add c.html, node.sVal
    fixTail = true

proc writeVarValue(c: var Compiler, varNode: Node) =
    if varNode.dataStorage:
        var varValue = c.data[varNode.varIdent].getStr
        if c.data.hasKey(varNode.varIdent):
            if varNode.isSafeVar:
                varValue = multiReplace(varValue,
                    ("^", "&amp;"),
                    ("<", "&lt;"),
                    (">", "&gt;"),
                    ("\"", "&quot;"),
                    ("'", "&#x27;"),
                    ("`", "&grave;")
                )
        add c.html, varValue
    else: discard # todo command line warning

proc handleInfixStmt(c: var Compiler, node: Node) = 
    if node.infixOp == AND:
        # write string concatenation
        if node.infixLeft.nodeType == NTString:
            c.writeStrValue(node.infixLeft)
        if node.infixRight.nodeType == NTVariable:
            c.writeVarValue(node.infixRight)

proc compInfixNode(c: var Compiler, node: Node): bool =
    case node.infixOp
    of EQ:
        if node.infixLeft.nodeType == node.infixRight.nodeType:
            case node.infixLeft.nodeType:
            of NTInt:
                return isEqualInt(node.infixLeft.iVal, node.infixRight.iVal)
            of NTString:
                return isEqualString(node.infixLeft.sVal, node.infixRight.sVal)
            else: discard
    of NE:
        if node.infixLeft.nodeType == node.infixRight.nodeType:
            case node.infixLeft.nodeType:
            of NTInt:
                return isNotEqualInt(node.infixLeft.iVal, node.infixRight.iVal)
            of NTString:
                return isNotEqualString(node.infixLeft.sVal, node.infixRight.sVal)
            else: discard
    of GT:
        if node.infixLeft.nodeType == node.infixRight.nodeType:
            case node.infixLeft.nodeType:
            of NTInt:
                return isGreaterInt(node.infixLeft.iVal, node.infixRight.iVal)
            else: discard
    of GTE:
        if node.infixLeft.nodeType == node.infixRight.nodeType:
            case node.infixLeft.nodeType:
            of NTInt:
                return isGreaterEqualInt(node.infixLeft.iVal, node.infixRight.iVal)
            else: discard
    of LT:
        if node.infixLeft.nodeType == node.infixRight.nodeType:
            case node.infixLeft.nodeType:
            of NTInt:
                return isLessInt(node.infixLeft.iVal, node.infixRight.iVal)
            else: discard
    of LTE:
        if node.infixLeft.nodeType == node.infixRight.nodeType:
            case node.infixLeft.nodeType:
            of NTInt:
                return isLessEqualInt(node.infixLeft.iVal, node.infixRight.iVal)
            else: discard
    else: discard

proc writeNewLine(c: var Compiler, nodes: seq[Node]) =
    for node in nodes:
        case node.nodeType:
        of NTHtmlElement:
            let tag = node.htmlNodeName
            c.openTag(tag, node)
            if node.nodes.len != 0:
                c.writeNewLine(node.nodes)
            c.closeTag(node, false, fixTail)
            if fixTail: fixTail = false
        of NTVariable:
            c.writeVarValue(node)
        of NTInfixStmt:
            c.handleInfixStmt(node)
        of NTConditionStmt:
            echo c.compInfixNode(node.ifCond)
        of NTString:
            c.writeStrValue(node)
        else: discard

proc init*(cInstance: typedesc[Compiler], astProgram: Program,
        minified: bool, templateType: TimlTemplateType,
        baseIndent: int, data = %*{}): Compiler =
    ## Create a new Compiler instance
    var c = cInstance(
        minified: minified,
        templateType: templateType,
        baseIndent: baseIndent,
        data: data
    )
    c.program = astProgram
    for node in c.program.nodes:
        case node.stmtList.nodeType:
        of NTHtmlElement:
            let tag = node.stmtList.htmlNodeName
            c.openTag(tag, node.stmtList)
            if node.stmtList.nodes.len != 0:
                c.writeNewLine(node.stmtList.nodes)
            c.closeTag(node.stmtList)
        of NTConditionStmt:
            if c.compInfixNode(node.stmtList.ifCond):
                c.writeNewLine(node.stmtList.ifBody)
            elif node.stmtList.elifBranch.len != 0:
                var skipElse: bool
                for elifNode in node.stmtList.elifBranch:
                    if c.compInfixNode(elifNode.cond):
                        c.writeNewLine(elifNode.body)
                        skipElse = true
                        break
                if not skipElse and node.stmtList.elseBody.len != 0:
                    c.writeNewLine(node.stmtList.elseBody)
            else:
                if node.stmtList.elseBody.len != 0:
                    c.writeNewLine(node.stmtList.elseBody)
        else: discard
    result = c