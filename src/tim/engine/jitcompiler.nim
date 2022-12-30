# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import ./ast
import std/[json, ropes, tables, macros]

from std/strutils import `%`, indent, multiReplace, join
from ./meta import TimlTemplate, setPlaceHolderId

type
    Compiler* = object
        ## Compiles current AST program to HTML or SCF (Source Code Filters)
        program: Program
            ## All Nodes statements under a `Program` object instance
        minify: bool
            ## Whether to minify the final HTML output (disabled by default)
        html: Rope
            ## A rope representing the final HTML output
        timlTemplate: TimlTemplate
        baseIndent: int
            ## Document base indentation
        data: JsonNode
            ## JSON data, if any
        logs: seq[string]
            ## Store errors at runtime without breaking the process
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

proc getJsonValue(c: var Compiler, node: Node, jsonNodes: JsonNode): JsonNode =
    if node.accessors.len == 0:
        return jsonNodes
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

proc getValue(c: var Compiler, node: Node): JsonNode =
    # if node.dataStorage == false and node.accessors.len == 0 and c.memtable.hasKey(node.varSymbol) == false:
        # discard # TODO 
            # result = c.data["globals"][node.varIdent]
    if node.dataStorage == false and c.memtable.hasKey(node.varSymbol):
        result = c.memtable[node.varSymbol]
        case result.kind:
            of JObject:
                result = c.getJsonValue(node, result)
            else: discard
    elif node.visibility == GlobalVar and c.data.hasKey("globals"):
        if node.accessors.len == 0:
            if c.data["globals"].hasKey(node.varIdent):
                result = c.data["globals"][node.varIdent]
            else: c.logs.add(UndefinedVariable % [node.varIdent, "globals"])
        else:
            if c.data["globals"].hasKey(node.varIdent):
                let jsonNode = c.data["globals"][node.varIdent]
                result = c.getJsonValue(node, jsonNode)
            else: c.logs.add(UndefinedVariable % [node.varIdent, "globals"])
    elif node.visibility == ScopeVar and c.data.hasKey("scope"):
        if c.data["scope"].hasKey(node.varIdent):
            let jsonNode = c.data["scope"][node.varIdent]
            result = c.getJsonValue(node, jsonNode)
        else: c.logs.add(UndefinedVariable % [node.varIdent, "scope"])

proc writeValue(c: var Compiler, node: Node) =
    let jsonValue = c.getValue(node)
    if jsonValue != nil:
        case jsonValue.kind:
        of JString:     add c.html, jsonValue.getStr
        of JInt:        add c.html, $(jsonValue.getInt)
        of JFloat:      add c.html, $(jsonValue.getFloat)
        of JBool:       add c.html, $(jsonValue.getBool)
        of JObject, JArray, JNull:
            c.logs.add(InvalidConversion % [$jsonValue.kind, node.varIdent])
        c.fixTail = true

macro `?`*(a: bool, body: untyped): untyped =
    let b = body[1]
    let c = body[2]
    result = quote:
        if `a`: `b` else: `c`

macro isEqualBool*(a, b: bool): untyped =
    result = quote:
        `a` == `b`

macro isNotEqualBool*(a, b: bool): untyped =
    result = quote:
        `a` != `b`

macro isEqualInt*(a, b: int): untyped =
    result = quote:
        `a` == `b`

macro isNotEqualInt*(a, b: int): untyped =
    result = quote:
        `a` != `b`

macro isGreaterInt*(a, b: int): untyped =
    result = quote:
        `a` > `b`

macro isGreaterEqualInt*(a, b: int): untyped =
    result = quote:
        `a` >= `b`

macro isLessInt*(a, b: int): untyped =
    result = quote:
        `a` < `b`

macro isLessEqualInt*(a, b: int): untyped =
    result = quote:
        `a` <= `b`

macro isEqualFloat*(a, b: float64): untyped =
    result = quote:
        `a` == `b`

macro isNotEqualFloat*(a, b: float64): untyped =
    result = quote:
        `a` != `b`

macro isEqualString*(a, b: string): untyped =
    result = quote:
        `a` == `b`

macro isNotEqualString*(a, b: string): untyped =
    result = quote:
        `a` != `b`

proc handleInfixStmt(c: var Compiler, node: Node) = 
    if node.infixOp == AND:
        if node.infixLeft.nodeType == NTVariable:
            c.writeValue(node.infixLeft)
        elif node.infixLeft.nodeType == NTString:
            c.writeStrValue(node.infixLeft)
        elif node.infixLeft.nodeType == NTInfixStmt:
            c.handleInfixStmt(node.infixLeft)

        if node.infixRight.nodeType == NTVariable:
            c.writeValue(node.infixRight)
        elif node.infixRight.nodeType == NTString:
            c.writeStrValue(node.infixRight)
        elif node.infixRight.nodeType == NTInfixStmt:
            c.handleInfixStmt(node.infixRight)

proc aEqualB(c: var Compiler, a: JsonNode, b: Node, swap: bool): bool =
    if a.kind == JString and b.nodeType == NTString:
        result = isEqualString(a.getStr, b.sVal)
    elif a.kind == JInt and b.nodeType == NTInt:
        result = isEqualInt(a.getInt, b.iVal)
    elif a.kind == JBool and b.nodeType == NTBool:
        result = isEqualBool(a.getBool, b.bVal)
    else:
        if swap:    c.logs.add(InvalidComparison % [b.nodeName, $a.kind])
        else:       c.logs.add(InvalidComparison % [$a.kind, b.nodeName])

proc aNotEqualB(c: var Compiler, a: JsonNode, b: Node, swap: bool): bool =
    if a.kind == JString and b.nodeType == NTString:
        result = isNotEqualString(a.getStr, b.sVal)
    elif a.kind == JInt and b.nodeType == NTInt:
        result = isNotEqualInt(a.getInt, b.iVal)
    elif a.kind == JBool and b.nodeType == NTBool:
        result = isNotEqualBool(a.getBool, b.bVal)
    else:
        if swap:    c.logs.add(InvalidComparison % [b.nodeName, $a.kind])
        else:       c.logs.add(InvalidComparison % [$a.kind, b.nodeName])

proc compareVarLit(c: var Compiler, leftNode, rightNode: Node, op: OperatorType, swap = false): bool =
    var jd: JsonNode
    var continueCompare: bool
    if leftNode.dataStorage:
        jd = c.getJsonData(leftNode.varIdent)
        if jd != nil:
            if jd.kind in {JArray, JObject}:
                jd = c.getJsonValue(leftNode, jd)
            continueCompare = true
    else:
        if c.memtable.hasKey(leftNode.varSymbol):
            jd = c.getJsonValue(leftNode, c.memtable[leftNode.varSymbol])
            if jd != nil:
                continueCompare = true
    if continueCompare:
        case op
            of EQ: result = c.aEqualB(jd, rightNode, swap)
            of NE: result = c.aNotEqualB(jd, rightNode, swap)
            of GT:
                if jd.kind == JInt:
                    if swap:    result = isLessInt(jd.getInt, rightNode.iVal)
                    else:       result = isGreaterInt(jd.getInt, rightNode.iVal)
            of GTE:
                if jd.kind == JInt:
                    if swap:    result = isLessEqualInt(jd.getInt, rightNode.iVal)
                    else:       result = isGreaterEqualInt(jd.getInt, rightNode.iVal)
            of LT:
                if jd.kind == JInt:
                    if swap:    result = isGreaterInt(jd.getInt, rightNode.iVal)
                    else:       result = isLessInt(jd.getInt, rightNode.iVal)
            of LTE:
                if jd.kind == JInt:
                    if swap:    result = isGreaterEqualInt(jd.getInt, rightNode.iVal)
                    else:       result = isLessEqualInt(jd.getInt, rightNode.iVal)
            else: discard

proc compInfixNode(c: var Compiler, node: Node): bool =
    case node.infixOp
    of EQ, NE:
        if node.infixLeft.nodeType == node.infixRight.nodeType:
            # compare two values sharing the same type
            case node.infixLeft.nodeType:
            of NTInt:
                result = isEqualInt(node.infixLeft.iVal, node.infixRight.iVal)
            of NTString:
                result = isEqualString(node.infixLeft.sVal, node.infixRight.sVal)
            of NTVariable:
                discard
                # result = c.compareVarVar(leftNode = node.infixLeft, op = node.infixOp, rightNode = node.infixRight)
            else: discard
        elif node.infixLeft.nodeType == NTVariable and node.infixRight.nodeType in {NTBool, NTString, NTInt}:
            # compare `NTVariable == {NTBool, NTString, NTInt}`
            result = c.compareVarLit(leftNode = node.infixLeft, op = node.infixOp, rightNode = node.infixRight)
        elif node.infixLeft.nodeType in {NTBool, NTString, NTInt} and node.infixRight.nodeType == NTVariable:
            # compare `{NTBool, NTString, NTInt} == NTVariable`
            result = c.compareVarLit(leftNode = node.infixRight, op = node.infixOp, rightNode = node.infixLeft, true)
    of GT, GTE, LT, LTE:
        if node.infixLeft.nodeType == node.infixRight.nodeType:
            case node.infixLeft.nodeType:
            of NTInt:
                case node.infixOp:
                of GT:
                    result = isGreaterInt(node.infixLeft.iVal, node.infixRight.iVal)
                of GTE:
                    result = isGreaterEqualInt(node.infixLeft.iVal, node.infixRight.iVal)
                of LT:
                    result = isLessInt(node.infixLeft.iVal, node.infixRight.iVal)
                of LTE:
                    result = isLessEqualInt(node.infixLeft.iVal, node.infixRight.iVal)
                else: discard
            else: discard
        
        elif node.infixLeft.nodeType == NTVariable and node.infixRight.nodeType == NTInt:
            result = c.compareVarLit(node.infixLeft, node.infixRight, node.infixOp)
        
        elif node.infixleft.nodeType == NTInt and node.infixRight.nodeType == NTVariable:
            result = c.compareVarLit(node.infixRight, node.infixLeft, node.infixOp, true)

        else: c.logs.add(InvalidComparison % [
            node.infixLeft.nodeName, node.infixRight.nodeName
        ])
    else: discard


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
                c.writeValue(attrNode)
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
    else: c.writeValue(idAttrNode)
    add c.html, "\""
    # add c.html, ("id=\"$1\"" % [node.attrs["id"][0]]).indent(1)

proc openTag(c: var Compiler, tag: string, node: Node, skipBr = false) =
    ## Open tag of the current JsonNode element
    if not c.minify:
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
        if not c.fixTail and not c.minify:
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

    var jitems: JsonNode
    if c.data["globals"].hasKey(forNode.forItems.varIdent):
        jitems = c.getJsonValue(forNode.forItems, c.data["globals"][forNode.forItems.varIdent])
        case jitems.kind:
        of JArray:
            for item in jitems:
                c.storeValue(forNode.forItem.varSymbol, item)
                c.writeNewLine(forNode.forBody)
                c.memtable.del(forNode.forItem.varSymbol)
        of JObject:
            for k in keys(jitems):
                var kvObject = newJObject()
                kvObject[k] = jitems[k]
                c.storeValue(forNode.forItem.varSymbol, kvObject)
                c.writeNewLine(forNode.forBody)
                c.memtable.del(forNode.forItem.varSymbol)
        else: discard # todo compile warning
    elif c.memtable.haskey(forNode.forItems.varSymbol):
        let jsonSubNode = c.getJsonValue(forNode.forItems, c.memtable[forNode.forItems.varSymbol])
        if jsonSubNode != nil:
            case jsonSubNode.kind
            of JArray:  c.handleJArray(jsonSubNode)
            of JObject: c.handleJObject(jsonSubNode)
            else: discard

proc handleViewInclude(c: var Compiler) =
    if c.hasViewCode:
        if c.minify:
            add c.html, c.viewCode
        else:
            add c.html, indent(c.viewCode, c.baseIndent * 2)
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
            c.writeValue(node)
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
        minify: bool, timlTemplate: TimlTemplate,
        baseIndent: int, filePath: string, data = %*{}, viewCode = ""): Compiler =
    ## Create a new Compiler instance
    var c = Compiler(
            minify: minify,
            timlTemplate: timlTemplate,
            baseIndent: baseIndent,
            data: data,
            memtable: newTable[string, JsonNode](),
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

    if c.logs.len != 0:
        echo filePath
        for error in c.logs:
            echo indent("Warning: " & error, 2)