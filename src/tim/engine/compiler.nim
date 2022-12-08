# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import ./ast, ./compileHandlers/logger
import std/[json, ropes, tables]

from std/strutils import `%`, indent, multiReplace, endsWith, join
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
        memtable: MemStorage
        logs: Logger

    MemStorage = TableRef[string, JsonNode]

const
    NewLine = "\n"
    InvalidAccessorKey = "Invalid property accessor \"$1\" for $2 ($3)"
    InvalidObjectAccess = "Invalid object access [object:$1]"
    UndefinedDataStorageVariable = "Undefined property accessor \"$1\" in data storage"

proc writeNewLine(c: var Compiler, nodes: seq[Node])

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
    if node.issctag == false and node.htmlNodeName notin ["html", "head", "body"]:
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

proc getVarValue(c: var Compiler, varNode: Node): string =
        result = c.data[varNode.varIdent].getStr
        if varNode.dataStorage:
            if varNode.isSafeVar:
                result = multiReplace(result,
                    ("^", "&amp;"),
                    ("<", "&lt;"),
                    (">", "&gt;"),
                    ("\"", "&quot;"),
                    ("'", "&#x27;"),
                    ("`", "&grave;")
                )

proc writeVarValue(c: var Compiler, varNode: Node) =
    if c.data.hasKey(varNode.varIdent):
        add c.html, c.getVarValue(varNode)
        fixTail = true
    elif c.memtable.hasKey(varNode.varSymbol):
        case c.memtable[varNode.varSymbol].kind:
        of JString:
            add c.html, c.memtable[varNode.varSymbol].getStr
        of JInt:
          add c.html, $(c.memtable[varNode.varSymbol].getInt)
        of JFloat:
          add c.html, $(c.memtable[varNode.varSymbol].getFloat)
        of JBool:
          add c.html, $(c.memtable[varNode.varSymbol].getBool)
        of JObject:
            case varNode.accessorKind:
            of AccessorKind.Key:
                if varNode.byKey == "k":
                    for k, v in pairs(c.memtable[varNode.varSymbol]):
                        add c.html, k
                else:
                    if c.memtable[varNode.varSymbol].hasKey(varNode.byKey):
                        add c.html, c.memtable[varNode.varSymbol][varNode.byKey].getStr
                    else: c.logs.add(InvalidAccessorKey % [varNode.byKey, $(c.memtable[varNode.varSymbol].kind)])
            of AccessorKind.Value:
                for k, v in pairs(c.memtable[varNode.varSymbol]):
                    add c.html, v.getStr
            else:
                c.logs.add(InvalidObjectAccess % ["attributes"])
        else: discard
        fixTail = true
    else: c.logs.add(UndefinedDataStorageVariable % [varNode.varIdent])

include ./compileHandlers/[comparators, infix]

proc handleConditionStmt(c: var Compiler, ifCond: Node, ifBody: seq[Node],
                            elifBranch: ElifBranch, elseBranch: seq[Node]) =
    if c.compInfixNode(ifCond):
        c.writeNewLine(ifBody)
    elif elifBranch.len != 0:
        var skipElse: bool
        for elifNode in elifBranch:
            if c.compInfixNode(elifNode.cond):
                c.writeNewLine(elifNode.body)
                skipElse = true
                break
        if not skipElse and elseBranch.len != 0:
            c.writeNewLine(elseBranch)
    else:
        if elseBranch.len != 0:
            c.writeNewLine(elseBranch)

proc storeValue(c: var Compiler, symbol: string, item: JsonNode) =
    c.memtable[symbol] = item

proc handleForStmt(c: var Compiler, forNode: Node) =
    if c.data.hasKey(forNode.forItems.varIdent):
        case c.data[forNode.forItems.varIdent].kind:
        of JArray:
            for item in c.data[forNode.forItems.varIdent]:
                c.storeValue(forNode.forItem.varSymbol, item)
                c.writeNewLine(forNode.forBody)
                c.memtable.del(forNode.forItem.varSymbol)
        of JObject:
            for k in keys(c.data[forNode.forItems.varIdent]):
                var kvObject = newJObject()
                kvObject[k] = c.data[forNode.forItems.varIdent][k]
                c.storeValue(forNode.forItem.varSymbol, kvObject)
                c.writeNewLine(forNode.forBody)
                c.memtable.del(forNode.forItem.varSymbol)
        else: discard
    else: discard # todo console warning

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
            c.handleConditionStmt(node.ifCond, node.ifBody, node.elifBranch, node.elseBody)
        of NTString:
            c.writeStrValue(node)
        of NTForStmt:
            c.handleForStmt(node)
        else: discard

proc init*(cInstance: typedesc[Compiler], astProgram: Program,
        minified: bool, templateType: TimlTemplateType,
        baseIndent: int, filePath: string, data = %*{}): Compiler =
    ## Create a new Compiler instance
    var c = Compiler(
            minified: minified,
            templateType: templateType,
            baseIndent: baseIndent,
            data: data,
            memtable: newTable[string, JsonNode](),
            logs: Logger()
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
            c.handleConditionStmt(
                node.stmtList.ifCond,
                node.stmtList.ifBody,
                node.stmtList.elifBranch,
                node.stmtList.elseBody)
        of NTForStmt:
            c.handleForStmt(node.stmtList)
        else: discard
    result = c
    if c.logs.logs.len != 0:
        echo filePath
        for error in c.logs.logs:
            echo indent(error.message, 2)
