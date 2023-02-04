# A high-performance compiled template engine inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

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
  else:
    result = newJNull()

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
  else:
    result = newJNull()

proc getStringValue(c: var Compiler, node: Node): string =
  let jsonValue = c.getValue(node)
  if jsonValue == nil: return
  case jsonValue.kind:
  of JString:     add result, jsonValue.getStr
  of JInt:        add result, $(jsonValue.getInt)
  of JFloat:      add result, $(jsonValue.getFloat)
  of JBool:       add result, $(jsonValue.getBool)
  of JObject, JArray, JNull:
    c.logs.add(InvalidConversion % [$jsonValue.kind, node.varIdent])
  c.fixTail = true

proc storeValue(c: var Compiler, symbol: string, item: JsonNode) =
  c.memtable[symbol] = item

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
      add c.html, c.getStringValue(node.infixLeft)
    elif node.infixLeft.nodeType == NTString:
      c.writeStrValue(node.infixLeft)
    elif node.infixLeft.nodeType == NTInfixStmt:
      c.handleInfixStmt(node.infixLeft)

    if node.infixRight.nodeType == NTVariable:
      add c.html, c.getStringValue(node.infixRight)
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
    if jd.kind != JNull:
      if jd.kind in {JArray, JObject}:
        jd = c.getJsonValue(leftNode, jd)
      continueCompare = true
  else:
    if c.memtable.hasKey(leftNode.varSymbol):
      jd = c.getJsonValue(leftNode, c.memtable[leftNode.varSymbol])
      if jd.kind != JNull:
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

proc compVarNil(c: var Compiler, node: Node): bool =
  # Evaluate NTVariable if returning value is anything but null
  # Example: `if $myvar:` 
  if c.memtable.hasKey(node.varSymbol):
    # Check if is available in memtable
    let jsonNode = c.getJsonValue(node, c.memtable[node.varSymbol])
    if jsonNode != nil:
      result = jsonNode.len != 0
  else: discard # TODO handle 

proc tryGetFromMemtable(c: var Compiler, node: Node): JsonNode =
  if c.memtable.hasKey(node.varSymbol):
    return c.getJsonValue(node, c.memtable[node.varSymbol])
  result = nil

include ./stdcalls

proc compInfixNode(c: var Compiler, node: Node): bool =
  if node.nodeType == NTVariable:
    result = c.compVarNil(node)
  elif node.nodeType == NTInfixStmt:
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
          var lNode = c.getJsonData(node.infixLeft.varIdent)
          var rNode = c.getJsonData(node.infixRight.varIdent)
          if lNode != nil and rNode != nil:
            result = lNode == rNode:
          elif lNode != nil and rNode == nil:
            if c.memtable.hasKey(node.infixRight.varSymbol):
              rNode = c.getJsonValue(node.infixRight, c.memtable[node.infixRight.varSymbol])
              result = lNode == rNode
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
    of AND:
      if node.infixLeft.nodeType == NTVariable and node.infixRight.nodeType == NTInfixStmt:
        result = c.compVarNil(node.infixLeft)
        if result:
          result = c.compInfixNode(node.infixRight)
      elif node.infixLeft.nodeType == NTInfixStmt and node.infixRight.nodeType == NTVariable:
        result = c.compVarNil(node.infixRight)
        if result:
          result = c.compInfixNode(node.infixLeft)
      elif node.infixLeft.nodeType == NTVariable and node.infixRight.nodeType == NTCall:
        result = c.compVarNil(node.infixLeft)
        if result:
          let callIdent = node.infixRight.callIdent
          if callIdent == "startsWith":
            result = c.callStdStartsWith(node.infixRight.callParams)
          elif callIdent == "endsWith":
            result = c.callStdEndsWith(node.infixRight.callParams)
    else: discard
  elif node.nodeType == NTCall:
    if node.callIdent == "startsWith":
      result = c.callStdStartsWith(node.callParams)
    elif node.callIdent == "endsWith":
      result = c.callStdEndsWith(node.callParams)
    elif node.callIdent == "contains":
      result = c.callStdContains(node.callParams)

proc handleConditionStmt(c: var Compiler, node: Node) =
  if c.compInfixNode(node.ifCond):
    c.writeNewLine(node.ifBody)
  elif node.elifBranch.len != 0:
    var skipElse: bool
    for elifNode in node.elifBranch:
      if c.compInfixNode(elifNode.cond):
        c.writeNewLine(elifNode.body)
        skipElse = true
        break
    if not skipElse and node.elseBody.len != 0:
      c.writeNewLine(node.elseBody)
  else:
    if node.elseBody.len != 0:
      c.writeNewLine(node.elseBody)

proc handleForStmt(c: var Compiler, forNode: Node) =
  let jsonItems = c.getValue(forNode.forItems)
  case jsonItems.kind:
  of JArray:
    for item in jsonItems:
      c.storeValue(forNode.forItem.varSymbol, item)
      c.writeNewLine(forNode.forBody)
      c.memtable.del(forNode.forItem.varSymbol)
  of JObject:
    for k, v in pairs(jsonItems):
      var kvObject = newJObject()
      kvObject[k] = v
      c.storeValue(forNode.forItem.varSymbol, kvObject)
      c.writeNewLine(forNode.forBody)
      c.memtable.del(forNode.forItem.varSymbol)
  else: discard