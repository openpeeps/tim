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