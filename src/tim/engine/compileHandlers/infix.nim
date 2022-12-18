# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

proc handleInfixStmt(c: var Compiler, node: Node) = 
    if node.infixOp == AND:
        if node.infixLeft.nodeType == NTVariable:
            c.writeVarValue(node.infixLeft)
        elif node.infixLeft.nodeType == NTString:
            c.writeStrValue(node.infixLeft)
        elif node.infixLeft.nodeType == NTInfixStmt:
            c.handleInfixStmt(node.infixLeft)

        if node.infixRight.nodeType == NTVariable:
            c.writeVarValue(node.infixRight)
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
    if leftNode.dataStorage:
        jd = c.getJsonData(leftNode.varIdent)
        if jd.kind in {JArray, JObject}:
            jd = c.getJsonValue(leftNode, jd)
        case op
            of EQ: result = c.aEqualB(jd, rightNode, swap)
            of NE: result = c.aNotEqualB(jd, rightNode, swap)
            else: discard
    else:
        if c.memtable.hasKey(leftNode.varSymbol):
            jd = c.getJsonValue(leftNode, c.memtable[leftNode.varSymbol])
            if jd != nil:
                case op
                    of EQ: result = c.aEqualB(jd, rightNode, swap)
                    of NE: result = c.aNotEqualB(jd, rightNode, swap)
                    else: discard

proc compInfixNode(c: var Compiler, node: Node): bool =
    var jsonData = newJObject()
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
            else: discard
        elif node.infixLeft.nodeType == NTVariable and node.infixRight.nodeType in {NTBool, NTString, NTInt}:
            # compare `NTVariable == {NTBool, NTString, NTInt}`
            result = c.compareVarLit(leftNode = node.infixLeft, op = node.infixOp, rightNode = node.infixRight)
        elif node.infixLeft.nodeType in {NTBool, NTString, NTInt} and node.infixRight.nodeType == NTVariable:
            # compare `{NTBool, NTString, NTInt} == NTVariable`
            result = c.compareVarLit(leftNode = node.infixRight, op = node.infixOp, rightNode = node.infixLeft, swap = true)
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