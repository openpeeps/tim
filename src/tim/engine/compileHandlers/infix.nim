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

proc compInfixNode(c: var Compiler, node: Node): bool =
    var jsonData = newJObject()
    case node.infixOp
    of EQ:
        if node.infixLeft.nodeType == node.infixRight.nodeType:
            # compare two values sharing the same type
            case node.infixLeft.nodeType:
            of NTInt:
                return isEqualInt(node.infixLeft.iVal, node.infixRight.iVal)
            of NTString:
                return isEqualString(node.infixLeft.sVal, node.infixRight.sVal)
            of NTVariable:
                discard
            else: discard
        elif node.infixLeft.nodeType == NTVariable and node.infixRight.nodeType == NTString:
            # compare `NTVariable == NTString`
            if node.infixLeft.dataStorage:
                jsonData = c.getJsonData(node.infixLeft.varIdent)
                if jsonData.hasKey(node.infixLeft.varIdent):
                    return isEqualString(jsonData[node.infixLeft.varIdent].getStr, node.infixRight.sVal)
            else:
                if c.memtable.hasKey(node.infixLeft.varSymbol):
                    let jn = c.getJsonValue(node.infixLeft, c.memtable[node.infixLeft.varSymbol])
                    if jn != nil:
                        return isEqualString(jn.getStr, node.infixRight.sVal)
                    return false
        elif node.infixLeft.nodeType == NTString and node.infixRight.nodeType == NTVariable:
            # compare `NTString == NTVariable`
            if node.infixRight.dataStorage:
                jsonData = c.getJsonData(node.infixRight.varIdent)
                if jsonData.hasKey(node.infixRight.varIdent):
                    return isEqualString(node.infixLeft.sVal, jsonData[node.infixRight.varIdent].getStr)
            else:
                if c.memtable.hasKey(node.infixRight.varSymbol):
                    let jn = c.getJsonValue(node.infixRight, c.memtable[node.infixRight.varSymbol])
                    if jn != nil:
                        return isEqualString(jn.getStr, node.infixLeft.sVal)
        elif node.infixLeft.nodeType == NTVariable and node.infixRight.nodeType == NTBool:
            # compare `NTVariable == NTBool`
            if node.infixLeft.dataStorage:
                jsonData = c.getJsonData(node.infixLeft.varIdent)
                if jsonData.hasKey(node.infixLeft.varIdent):
                    return isEqualBool(jsonData[node.infixLeft.varIdent].getBool, node.infixRight.bVal)
            else:
                if c.memtable.hasKey(node.infixLeft.varSymbol):
                    let jn = c.getJsonValue(node.infixLeft, c.memtable[node.infixLeft.varSymbol])
                    if jn != nil:
                        return isEqualBool(jn.getBool, node.infixRight.bVal)
        elif node.infixLeft.nodeType == NTBool and node.infixRight.nodeType == NTVariable:
            # compare `NTBool == NTVariable`
            if node.infixRight.dataStorage:
                jsonData = c.getJsonData(node.infixRight.varIdent)
                if jsonData.hasKey(node.infixRight.varIdent):
                    return isEqualBool(jsonData[node.infixRight.varIdent].getBool, node.infixLeft.bVal)
            else:
                if c.memtable.hasKey(node.infixRight.varSymbol):
                    let jn = c.getJsonValue(node.infixRight, c.memtable[node.infixRight.varSymbol])
                    if jn != nil:
                        return isEqualBool(jn.getBool, node.infixLeft.bVal)
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