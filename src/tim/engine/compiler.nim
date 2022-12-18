# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import ./ast, ./compileHandlers/logger
import std/[json, ropes, tables]

from std/strutils import `%`, indent, multiReplace, join
from ./meta import TimlTemplate, setPlaceHolderId

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
        timlTemplate: TimlTemplate
        baseIndent: int
            ## Document base indentation
        data: JsonNode
            ## JSON data, if any
        logs: Logger
            ## A logger that raise errors at runtime without breaking the app
        hasViewCode: bool
        viewCode: string
            ## When compiler is initialized for layout,
            ## this field will contain the view code (HTML)
        memtable: MemStorage
        fixTail: bool

    MemStorage = TableRef[string, JsonNode]

const
    NewLine = "\n"
    InvalidAccessorKey = "Invalid property accessor \"$1\" for $2 ($3)"
    InvalidConversion = "Failed to convert $1 \"$2\" to string"
    InvalidComparison = "Can't compare $1 and $2 values"
    InvalidObjectAccess = "Invalid object access"
    UndefinedPropertyAccessor = "Undefined property accessor \"$1\" in data storage"
    UndefinedArray = "Undefined array"
    InvalidArrayAccess = "Array indices must be positive integers. Got $1[\"$2\"]"
    ArrayIndexOutBounds = "Index out of bounds [$1]. \"$2\" size is [$3]"
    UndefinedProperty = "Undefined property \"$1\""
    UndefinedVariable = "Undefined property \"$1\" in \"$2\""

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

proc getHtml*(c: Compiler): string {.inline.} =
    ## Returns compiled HTML for static `timl` templates
    result = $(c.html)

proc getHtmlTails*(c: Compiler): string {.inline.} =
    ## Retrieve the tails and deferred elements for current layout
    result = $(c.htmlTails)

proc writeStrValue(c: var Compiler, node: Node) =
    add c.html, node.sVal
    c.fixTail = true

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

proc getJsonData(c: var Compiler, key: string): JsonNode =
    if c.data.hasKey(key):
        result = c.data[key]
    elif c.data.hasKey("globals"):
        if c.data["globals"].hasKey(key):
            result = c.data["globals"][key]
    elif c.data.hasKey("scope"):
        if c.data["scope"].hasKey(key):
            result = c.data["scope"][key]

proc writeVar(c: var Compiler, node: Node, jNode: JsonNode) =
    let nKind = jNode.kind
    case nKind:
    of JString: 
        add c.html, jNode.getStr
    of JInt:
        add c.html, $(jNode.getInt)
    of JFloat:
        add c.html, $(jNode.getFloat)
    of JBool:
        add c.html, $(jNode.getBool)
    of JObject, JArray, JNull:
        c.logs.add(InvalidConversion % [$nKind, node.varIdent])

proc getJsonValue(c: var Compiler, node: Node, jsonNodes: JsonNode): JsonNode =
    var
        lvl = 0
        levels = node.accessors.len
        propNode = node.accessors[lvl]

    proc getJValue(c: var Compiler, jN: JsonNode): JsonNode =
        if propNode.nodeType == NTInt:
            if jN.kind == JArray:
                let jNSize = jN.len
                if propNode.iVal > (jNSize - 1):
                    c.logs.add(ArrayIndexOutBounds % [$propNode.iVal, node.varIdent, $(jNSize)])
                else:
                    result = jN[propNode.iVal]
                    inc lvl
                    if levels > lvl:
                        propNode = node.accessors[lvl]
                        result = c.getJValue(result)
            else:
                if propNode.nodeType == NTString:
                    c.logs.add(InvalidArrayAccess % [node.varIdent, propNode.sVal])
                else: c.logs.add(UndefinedArray)
        elif propNode.nodeType == NTString:
            if jN.kind == JObject:
                if jn.hasKey(propNode.sVal):
                    result = jN[propNode.sVal]
                    inc lvl
                    if levels > lvl:
                        propNode = node.accessors[lvl]
                        result = c.getJValue(result)
                else: c.logs.add(UndefinedProperty % [propNode.sVal])
            else: c.logs.add(UndefinedProperty % [propNode.sVal])
    result = c.getJValue(jsonNodes)

proc writeVarValue(c: var Compiler, varNode: Node, indentValue = false) =
    template writeInternalVar() =
        if c.data.hasKey(varNode.varIdent):
            add c.html, c.getVarValue(varNode)
            c.fixTail = true
        else: c.logs.add(UndefinedPropertyAccessor % [varNode.varIdent])
    if varNode.dataStorage == false and
        varNode.accessors.len == 0 and
        c.memtable.hasKey(varNode.varSymbol) == false:
            writeInternalVar()
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
            let jsonSubNode = c.getJsonValue(varNode, c.memtable[varNode.varSymbol])
            if jsonSubNode != nil:
                c.writeVar(varNode, jsonSubNode)
            # case varNode.accessorKind:
            # of AccessorKind.Key:
            #     if varNode.byKey == "k":
            #         for k, v in pairs(c.memtable[varNode.varSymbol]):
            #             add c.html, k
            #     else:
            #         if c.memtable[varNode.varSymbol].hasKey(varNode.byKey):
            #             add c.html, c.memtable[varNode.varSymbol][varNode.byKey].getStr
            #         else: c.logs.add(InvalidAccessorKey % [varNode.byKey, $(c.memtable[varNode.varSymbol].kind)])
            # of AccessorKind.Value:
            #     for k, v in pairs(c.memtable[varNode.varSymbol]):
            #         add c.html, v.getStr
            # else: discard
        else: discard
        c.fixTail = true
    elif varNode.visibility == GlobalVar:
        if varNode.accessors.len == 0:
            if c.data["globals"].hasKey(varNode.varIdent):
                let jsonNode = c.data["globals"][varNode.varIdent]
                c.writeVar(varNode, jsonNode)
            else: c.logs.add(UndefinedVariable % [varNode.varIdent, "globals"])
        else:
            if c.data["globals"].hasKey(varNode.varIdent):
                let jsonNode = c.data["globals"][varNode.varIdent]
                let jsonSubNode = c.getJsonValue(varNode, jsonNode)
                if jsonSubNode != nil:
                    c.writeVar(varNode, jsonSubNode)
            else: c.logs.add(UndefinedVariable % [varNode.varIdent, "globals"])
        c.fixTail = true
    elif varNode.visibility == ScopeVar:
        if c.data["scope"].hasKey(varNode.varIdent):
            let jsonNode = c.data["scope"][varNode.varIdent]
            let jsonSubNode = c.getJsonValue(varNode, jsonNode)
            if jsonSubNode != nil:
                c.writeVar(varNode, jsonSubNode)
        else: c.logs.add(UndefinedVariable % [varNode.varIdent, "scope"])
        c.fixTail = true
    else: discard # handle internal vars

include ./compileHandlers/[comparators, infix]

proc hasAttributes(node: Node): bool =
    ## Determine if current `Node` has any HTML attributes
    result = node.attrs.len != 0

proc writeAttributes(c: var Compiler, node: Node) =
    ## write one or more HTML attributes
    for k, attrNodes in node.attrs.pairs():
        if k == "id": continue # handled by `writeIDAttribute`
        add c.html, indent("$1=" % [k], 1) & "\""
        var strAttrs: seq[string]
        for attrNode in attrNodes:
            if attrNode.nodeType == NTString:
                strAttrs.add attrNode.sVal
            elif attrNode.nodeType == NTVariable:
                # TODO handle concat
                c.writeVarValue(attrNode)
        if strAttrs.len != 0:
            add c.html, join(strAttrs, " ")
        add c.html, "\""
        # add c.html, ("$1=\"$2\"" % [k, join(v, " ")]).indent(1)

proc hasIDAttribute(node: Node): bool =
    ## Determine if current JsonNode has an HTML ID attribute attached to it
    result = node.attrs.hasKey("id")

proc writeIDAttribute(c: var Compiler, node: Node) =
    ## Write an ID HTML attribute to current HTML Element
    add c.html, indent("id=", 1) & "\""
    let idAttrNode = node.attrs["id"][0]
    if idAttrNode.nodeType == NTString:
        add c.html, idAttrNode.sVal
    else: c.writeVarValue(idAttrNode)
    add c.html, "\""
    # add c.html, ("id=\"$1\"" % [node.attrs["id"][0]]).indent(1)

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

proc closeTag(c: var Compiler, node: Node, skipBr = false) =
    ## Close an HTML tag
    if node.issctag == false:
        if not c.fixTail and not c.minified:
            c.indentLine(node.meta, skipBr)
        add c.html, "</" & node.htmlNodeName & ">"

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

    proc handleJArray(c: var Compiler, jdata: JsonNode) =
        for item in jdata:
            c.storeValue(forNode.forItem.varSymbol, item)
            c.writeNewLine(forNode.forBody)
            c.memtable.del(forNode.forItem.varSymbol)

    proc handleJObject(c: var Compiler, jdata: JsonNode) =
        for k in keys(jdata):
            var kvObject = newJObject()
            kvObject[k] = jdata[k]
            c.storeValue(forNode.forItem.varSymbol, kvObject)
            c.writeNewLine(forNode.forBody)
            c.memtable.del(forNode.forItem.varSymbol)

    if c.data["globals"].hasKey(forNode.forItems.varIdent):
        case c.data["globals"][forNode.forItems.varIdent].kind:
        of JArray:
            c.handleJArray(c.data["globals"][forNode.forItems.varIdent])
        of JObject:
            c.handleJObject(c.data["globals"][forNode.forItems.varIdent])
        else: discard
    else: discard # todo console warning

proc handleViewInclude(c: var Compiler) =
    if c.hasViewCode:
        add c.html, c.viewCode
    else:
        add c.html, c.timlTemplate.setPlaceHolderId()

proc writeNewLine(c: var Compiler, nodes: seq[Node]) =
    for node in nodes:
        if node == nil: continue # TODO sometimes we get nil. check parser
        case node.nodeType:
        of NTHtmlElement:
            let tag = node.htmlNodeName
            c.openTag(tag, node)
            if node.nodes.len != 0:
                c.writeNewLine(node.nodes)
            c.closeTag(node, false)
            if c.fixTail: c.fixTail = false
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
        of NTView:
            c.handleViewInclude()
        else: discard

proc init*(cInstance: typedesc[Compiler], astProgram: Program,
        minified: bool, timlTemplate: TimlTemplate,
        baseIndent: int, filePath: string, data = %*{}, viewCode = ""): Compiler =
    ## Create a new Compiler instance
    var c = Compiler(
            minified: minified,
            timlTemplate: timlTemplate,
            baseIndent: baseIndent,
            data: data,
            memtable: newTable[string, JsonNode](),
            logs: Logger(),
            viewCode: viewCode
        )

    if viewCode.len != 0:
        c.hasViewCode = true
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
        of NTView:
            c.handleViewInclude()
        else: discard
    result = c

    if c.logs.logs.len != 0:
        echo filePath
        for error in c.logs.logs:
            echo indent("Warning: " & error.message, 2)
