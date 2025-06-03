# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://tim-engine.com

import std/[strutils, json]
import pkg/jsony

const
  ValueSize* = max([
    sizeof(bool),
    sizeof(float),
    sizeof(string)
  ])

const
  tyNil* = 0
  tyBool* = 1
  tyInt* = 2
  tyFloat* = 3
  tyString* = 4
  tyFirstObject* = 10
  tyJsonStorage* = 11
  tyArrayObject* = 12
  tyHtmlObject* = 13

type
  TypeId* = range[0..32766]  # max amount of case object branches

  Object* = ref object
    ## A hayago object.
    case isForeign: bool
      of true: data*: pointer
      of false: fields*: seq[Value]
  
  HtmlObject* = object

  Value* = ref object
    case typeId*: TypeId  ## the type ID, used for dynamic dispatch
    of tyBool:
      boolVal*: bool
    of tyInt:
      intVal*: int64
    of tyFloat:
      floatVal*: float64
    of tyString:
      stringVal*: ref string
    of tyJsonStorage:
      jsonVal*: JsonNode
    of tyHtmlObject:
      htmlObject*: HtmlObject
    else:
      objectVal*: Object

  ValuePtr* = Value
    ## A pointer to a value.

  Stack* = seq[Value]
    ## A runtime stack of values, used in the VM.

  StackView* = ptr UncheckedArray[Value]
    ## An unsafe view into a Stack.

  ForeignProc* = proc (args: StackView): Value
    ## A foreign proc.

proc `$`*(value: Value): string =
  ## Returns a value's string representation.
  case value.typeId
  of tyNil: result = "nil"
  of tyBool: result = $value.boolVal
  of tyInt: result = $value.intVal
  of tyFloat: result = $value.floatVal
  of tyString: result = escape($value.stringVal[])
  of tyJsonStorage:
    result = toJson(value.jsonVal)
  of tyArrayObject:
    let len = value.objectVal.fields.len
    result.add("[")
    for i in 0 ..< len:
      result.add($value.objectVal.fields[i])
      if i < len - 1:
        result.add(", ")
    result.add("]")
  else: result = "<object>"

proc initValue*(v: bool): Value =
  ## Initializes a bool value.
  result = Value(typeId: tyBool, boolVal: v)

proc initValue*(v: int64): Value =
  ## Initializes a float value.
  result = Value(typeId: tyInt, intVal: v)

proc initValue*(v: float64): Value =
  ## Initializes a float value.
  result = Value(typeId: tyFloat, floatVal: v)

proc initValue*(v: string): Value =
  ## Initializes a string value.
  result = Value(typeId: tyString)
  new(result.stringVal)
  result.stringVal[] = v

proc initValue*(v: JsonNode): Value =
  ## Initializes a JSON value.
  result = Value(typeId: tyJsonStorage)
  result.jsonVal = v

proc initValue*[T: tuple | object | ref](id: TypeId, value: T): Value =
  ## Safely initializes a foreign object value.
  ## This copies the value onto the heap for ordinary objects and tuples,
  ## and GC_refs the value for refs. The finalizer for objectVal deallocates or
  ## GC_unrefs the foreign data to maintain memory safety.
  result = Value(typeId: id)
  when T is tuple | object:
    new(result.objectVal) do (obj: Object):
      dealloc(obj.data)
    result.objectVal.isForeign = true
    let data = cast[ptr T](alloc(sizeof(T)))
    data[] = value
    result.objectVal.data = data
  elif T is ref:
    new(result.objectVal) do (obj: Object):
      GC_unref(cast[ref T](obj.data))
    result.objectVal.isForeign = true
    GC_ref(value)
    result.objectVal.data = cast[pointer](value)

proc foreign*(value: var Value, T: typedesc): T =
  result = cast[var T](value.objectVal.data)

proc foreign*(value: Value, T: typedesc): T =
  ## Get an object value. This is a *mostly* safe operation, but attempting to
  ## get a foreign type different from the value's is undefined behavior.
  result = cast[ptr T](value.objectVal.data)[]

const nilObject* = -1 ## The field count used for initializing a nil object.

proc initObject*(id: TypeId, fieldCount: int): Value =
  ## Initializes a native object value, with ``fieldCount`` fields.
  result = Value(typeId: id)
  if fieldCount == nilObject:
    result.objectVal = nil
  else:
    result.objectVal =
      Object(isForeign: false, fields: newSeq[Value](fieldCount))

proc initArray*(length: int): Value =
  ## Initializes an array value.
  result = initObject(tyArrayObject, 0)
  result.objectVal =
    Object(isForeign: false, fields: newSeq[Value](length))