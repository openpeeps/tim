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
                if c.data.hasKey(node.infixLeft.varIdent):
                    return isEqualString(c.data[node.infixLeft.varIdent].getStr, node.infixRight.sVal)
            else:
                if c.memtable.hasKey(node.infixLeft.varSymbol):
                    return isEqualString(c.memtable[node.infixLeft.varSymbol].getStr, node.infixRight.sVal)
        elif node.infixLeft.nodeType == NTString and node.infixRight.nodeType == NTVariable:
            # compare `NTString == NTVariable`
            if node.infixRight.dataStorage:
                if c.data.hasKey(node.infixRight.varIdent):
                    return isEqualString(node.infixLeft.sVal, c.data[node.infixRight.varIdent].getStr)

        elif node.infixLeft.nodeType == NTVariable and node.infixRight.nodeType == NTBool:
            # compare `NTVariable == NTBool`
            if node.infixLeft.dataStorage:
                if c.data.hasKey(node.infixLeft.varIdent):
                    return isEqualBool(c.data[node.infixLeft.varIdent].getBool, node.infixRight.bVal)
        elif node.infixLeft.nodeType == NTBool and node.infixRight.nodeType == NTVariable:
            # compare `NTBool == NTVariable`
            if node.infixLeft.dataStorage:
                if c.data.hasKey(node.infixLeft.varIdent):
                    return isEqualBool(c.data[node.infixLeft.varIdent].getBool, node.infixRight.bVal)
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