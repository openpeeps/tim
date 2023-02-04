template typeSafety(params: varargs[tuple[pKind, pExpectKind: JsonNodeKind]]) =
  for p in params:
    if p.pKind != p.pExpectKind:
      c.logs.add("Type mismatch, got $1 but expected $2" % [$p.pKind, $p.pExpectKind])
      return

proc callStdStartsWith(c: var Compiler, params: seq[Node]): bool =
  var strParam, prefixParam: JsonNode
  if params[0].nodeType == NTVariable:
    strParam = c.tryGetFromMemtable(params[0])
    if strParam == nil:
      strParam = c.getJsonData(params[0].varIdent)
  if params[1].nodeType == NTVariable:
    prefixParam = c.tryGetFromMemtable(params[1])
    if prefixParam == nil:
      prefixParam = c.getJsonData(params[1].varIdent)
  typeSafety((strParam.kind, JString), (prefixParam.kind, JString))
  result = strutils.startsWith(strParam.getStr, prefixParam.getStr)

proc callStdEndsWith(c: var Compiler, params: seq[Node]): bool =
  var strParam, prefixParam: JsonNode
  if params[0].nodeType == NTVariable:
    strParam = c.tryGetFromMemtable(params[0])
    if strParam == nil:
      strParam = c.getJsonData(params[0].varIdent)
  if params[1].nodeType == NTVariable:
    prefixParam = c.tryGetFromMemtable(params[1])
    if prefixParam == nil:
      prefixParam = c.getJsonData(params[1].varIdent)
  typeSafety((strParam.kind, JString), (prefixParam.kind, JString))
  result = strutils.endsWith(strParam.getStr, prefixParam.getStr)