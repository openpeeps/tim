import std/[macros, tables, jsonutils]

from std/strutils import spaces
from std/json import `$`

{.experimental: "dynamicBindSym".}

type
  TValue* = enum
    tValNil
    tValBool
    tValFloat
    tValString
    tValInt
    tValArray
    tValObject
  
  DataTable = TableRef[string, Value]

  Value = ref object
    case vtype: TValue:
    of tValBool:
      bVal: bool
    of tValFloat:
      fVal: float
    of tValString:
      sVal: string
    of tValInt:
      iVal: int
    of tValArray:
      arrayValues: seq[Value]
    of tValObject:
      objectValues: DataTable
    else: discard

  Global {.acyclic.} = ref object 
    data: DataTable

  Scope {.acyclic.} = ref object 
    data: DataTable

  Local {.acyclic.} = ref object 
    data: DataTable

proc assign(value: var NimNode, key, v: NimNode) {.compileTime.} =
  case v.kind
    of nnkStrLit:
      value.add(
        newColonExpr(ident "vtype", ident "tValString"),
        newColonExpr(ident "sVal", v)
      )
    of nnkIntLit:
      value.add(
        newColonExpr(ident "vtype", ident "tValInt"),
        newColonExpr(ident "iVal", v)
      )
    of nnkIdent:
      if v.strVal in ["true", "false"]:
        value.add(
          newColonExpr(ident "vtype", ident "tValBool"),
          newColonExpr(ident "bVal", v)
        )
      else:
        let varImpl = v.bindSym.getImpl
        expectKind varImpl, nnkIdentDefs
        value.assign(key, varImpl[^1])
    of nnkBracket, nnkPrefix:
      var list: NimNode
      if v.kind == nnkPrefix:
        if not eqIdent(v[0], "@"):
          error("Expected a sequence or array")
        else: list = v[1]
      else:
        list = v
      var items = nnkBracket.newTree()
      for l in list:
        var arrItem = nnkObjConstr.newTree(ident "Value")
        arrItem.assign(key, l)
        items.add arrItem
      value.add(
        newColonExpr(ident "vtype", ident "tValArray"),
        newColonExpr(
          ident "arrayValues",
          nnkPrefix.newTree(
            ident "@",
            items
          )
        )
      )
      echo value.repr
    of nnkTableConstr:
      echo "X"
    else: error("Invalid type for fast object instantiation")

macro `%*`(fields: untyped): untyped =
  expectKind fields, nnkTableConstr
  var dataTable = nnkVarSection.newTree(
    nnkIdentDefs.newTree(
      ident "dataTable",
      newEmptyNode(),
      newCall(
        ident("DataTable")
      )
    )
  )
  var dataConstr = nnkObjConstr.newTree(
    ident "Global",
    newColonExpr(
      ident "data",
      ident "dataTable"
    )
  )
  result = newStmtList()
  var dataTableFields = newStmtList()
  for f in fields:
    expectKind f, nnkExprColonExpr  
    var value = nnkObjConstr.newTree(ident "Value")
    value.assign(f[0], f[1])
    dataTableFields.add(
      newAssignment(
        nnkBracketExpr.newTree(
          ident "dataTable",
          f[0]
        ),
        value
      )
    )
  result.add(dataTable)
  result.add(dataTableFields)
  result.add(dataConstr)

#
# Runtime API
#
iterator items*(v: Value): Value =
  if v.vtype == tValArray:
    for k, i in v.arrayValues:
      yield i

proc `$`*(v: Value): string =
  ## Returns string representation of Value
  case v.vtype:
    of tValString:
      result = v.sVal
    of tValInt:
      result = $v.iVal
    of tValBool:
      result = $v.bVal
    of tValFloat:
      result = $v.fVal
    of tValArray:
      add result, "["
      var i = 1
      var arrlen = v.arrayValues.len
      for item in v.arrayValues:
        add result, "\"" & $(item) & "\""
        if i != arrlen:
          add result, "," & spaces(1)
        inc i
      add result, "]"
    of tValObject:
      add result, "{" 
      for o in v.objectValues.pairs():
        add result, $(o)
      # $(toJson(v.objectValues))
      add result, "}"
    of tValNil:
      result = "null" 

var x = "yey"
var t = %*{
  "test": "ok",
  "asa": 123,
  "asdsa": x,
  "exists": true,
  "fruits": @["apple", "pineapple"],
  "ya": {
    "hey": "aaa"
  }
}

# test
echo t.data.len
echo t.data["test"].sVal
echo t.data["asa"].iVal
echo t.data["asdsa"].sVal

echo t.data["fruits"]
for item in t.data["fruits"].items():
  echo item.sVal