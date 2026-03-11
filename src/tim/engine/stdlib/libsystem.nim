# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[strutils, options, os, sequtils,
        httpclient, httpcore, json, tables,
        algorithm, random]

import pkg/jsony
import pkg/voodoo/language/[chunk, ast, sym, value]

import ../parser
import ./inliner

# import pkg/voodoo/parsers/voojson

type TimRuntime* = object of CatchableError

proc convertObjectToJson(arg: Value): string =
  case arg.objectVal.isForeign
  of false:
    result = "{"
    let obj = arg.objectVal
    for i in 0..<obj.keys.len:
      result.add("\"" & obj.keys[i] & "\": ")
      case obj.fields[i].typeId
      of 4: # string
        result.add("\"" & obj.fields[i].stringVal[] & "\"")
      of 15: # object
        result.add("[Object]")
      else: # other types
        result.add($obj.fields[i])
      if i < obj.keys.len - 1:
        result.add(", ")
    result.add("}")
  else:
    result = "{...}"

proc initSystemOps(script: Script, module: Module) =
  ## Add builtin operations into the module.
  ## This should only ever be called when creating the ``system`` module.

  # bool operators
  script.addProc(module, "not", @[paramDef("x", ttyBool)], ttyBool)
  script.addProc(module, "==", @[paramDef("a", ttyBool), paramDef("b", ttyBool)], ttyBool)
  script.addProc(module, "!=", @[paramDef("a", ttyBool), paramDef("b", ttyBool)], ttyBool)

  # number type operators

  for T in [(ttyInt, ttyFloat), (ttyFloat, ttyInt)]:
    script.addProc(module, "+", @[paramDef("a", T[0])], T[0])
    script.addProc(module, "-", @[paramDef("a", T[0])], T[0])
    
    script.addProc(module, "+", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyFloat)
    script.addProc(module, "-", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyFloat)
    script.addProc(module, "*", @[paramDef("X", T[0]), paramDef("b", T[1])], ttyFloat)
    script.addProc(module, "/", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyFloat)
  
    script.addProc(module, "==", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, "!=", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, "<", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, "<=", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, ">", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, ">=", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)

  for T in [(ttyInt, ttyInt), (ttyFloat, ttyFloat)]:
    script.addProc(module, "+=", @[paramDef("a", T[0], mut = true), paramDef("b", T[1])], ttyVoid)
    script.addProc(module, "-=", @[paramDef("a", T[0], mut = true), paramDef("b", T[1])], ttyVoid)
    script.addProc(module, "*=", @[paramDef("a", T[0], mut = true), paramDef("b", T[1])], ttyVoid)
    script.addProc(module, "/=", @[paramDef("a", T[0], mut = true), paramDef("b", T[1])], ttyVoid)

    script.addProc(module, ">=", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, "<=", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, ">",  @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, "<",  @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
  
  script.addProc(module, "==", @[paramDef("a", ttyBool), paramDef("b", ttyBool)], ttyBool)
  script.addProc(module, "!=", @[paramDef("a", ttyBool), paramDef("b", ttyBool)], ttyBool)

proc loadLibrary*(script: Script, globalData, localData: JsonNode): Module =
  ## Create and initialize the ``system`` module.

  # foreign stuff
  result = newModule("system", some"system.timl")
  result.initSystemTypes()
  script.initSystemOps(result)

  # string operators
  script.addProc(result, "==", @[paramDef("a", ttyString), paramDef("b", ttyString)], ttyBool,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] == args[1].stringVal[]))

  script.addProc(result, "!=", @[paramDef("a", ttyString), paramDef("b", ttyString)], ttyBool,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] != args[1].stringVal[]))

  script.addProc(result, "is", @[paramDef("a", ttyString), paramDef("b", ttyString)], ttyBool,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] == args[1].stringVal[]))
  
  script.addProc(result, "isnot", @[paramDef("a", ttyString), paramDef("b", ttyString)], ttyBool,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] != args[1].stringVal[]))

  script.addProc(result, "is", @[paramDef("a", ttyBool), paramDef("b", ttyBool)], ttyBool,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] == args[1].stringVal[]))
  
  script.addProc(result, "isnot", @[paramDef("a", ttyBool), paramDef("b", ttyBool)], ttyBool,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] != args[1].stringVal[]))

  #
  # JSON operators between JSON and other types
  #
  script.addProc(result, "==", @[paramDef("a", ttyJson), paramDef("b", ttyBool)], ttyBool,
    proc (args: StackView): Value =
      assert args[0].jsonVal.kind == JBool
      result = initValue(args[0].jsonVal.getBool == args[1].boolVal))

  script.addProc(result, "==", @[paramDef("a", ttyJson), paramDef("b", ttyString)], ttyBool,
    proc (args: StackView): Value =
      assert args[0].jsonVal.kind == JString
      result = initValue(args[0].jsonVal.getStr() == args[1].stringVal[]))

  script.addProc(result, "==", @[paramDef("a", ttyJson), paramDef("b", ttyInt)], ttyBool,
    proc (args: StackView): Value =
      assert args[0].jsonVal.kind == JInt
      result = initValue(args[0].jsonVal.getInt() == args[1].intVal))

  script.addProc(result, "==", @[paramDef("a", ttyJson), paramDef("b", ttyFloat)], ttyBool,
    proc (args: StackView): Value =
      assert args[0].jsonVal.kind == JFloat
      result = initValue(args[0].jsonVal.getFloat() == args[1].floatVal))

  script.addProc(result, "type", @[paramDef("x", ttyAny)], ttyString,
    proc (args: StackView): Value =
      let valueType =
        case args[0].typeId:
        of tyBool: "bool"
        of tyInt: "int"
        of tyFloat: "float"
        of tyString: "string"
        of tyJsonStorage: "json"
        of tyArrayObject: "array"
        of tyHtmlObject: "html"
        # of ttyPointer: "pointer"
        else: "object"
      result = initValue(valueType))

  script.addProc(result, "jsonType", @[paramDef("x", ttyJson)], ttyString,
    proc (args: StackView): Value =
      let valueType =
        case args[0].jsonVal.kind:
        of JBool: "bool"
        of JInt: "int"
        of JFloat: "float"
        of JString: "string"
        of JArray: "array"
        of JObject: "object"
        else: "nil"
      result = initValue(valueType))

  # converters
  script.addProc(result, "toInt", @[paramDef("f", ttyFloat)], ttyInt,
    proc (args: StackView): Value =
      result = initValue(toInt(args[0].floatVal)))

  script.addProc(result, "parseInt", @[paramDef("i", ttyString)], ttyInt,
    proc (args: StackView): Value =
      ## Convert a string to an int.
      result = initValue(parseInt(args[0].stringVal[])))

  script.addProc(result, "toFloat", @[paramDef("i", ttyInt)], ttyFloat,
    proc (args: StackView): Value =
      ## Convert an int to a float
      result = initValue(toFloat(args[0].intVal)))

  script.addProc(result, "assert", @[paramDef("condition", ttyBool)], ttyVoid,
    proc (args: StackView): Value =
      ## Assert that the given condition is true.
      if not args[0].boolVal:
        raise newException(TimRuntime, "Assertion failed: " & $args[0].boolVal))

  #
  # String conversion
  #
  script.addProc(result, "toString", @[paramDef("x", ttyInt)], ttyString,
    proc (args: StackView): Value =
      ## Convert an int to a string
      result = initValue($(args[0].intVal))
    )

  script.addProc(result, "toString", @[paramDef("x", ttyFloat)], ttyString,
    proc (args: StackView): Value =
      ## Convert a float to a string
      result = initValue($(args[0].floatVal))
    )

  script.addProc(result, "toString", @[paramDef("x", ttyBool)], ttyString,
    proc (args: StackView): Value =
      ## Convert bool to string
      result = initValue($(args[0].boolVal))
    )

  script.addProc(result, "toString", @[paramDef("x", ttyJson)], ttyString,
    proc (args: StackView): Value =
      ## Convert JSON to string
      case args[0].jsonVal.kind
      of JObject, JArray:
        return initValue(toJson(args[0].jsonVal))
      of JInt:
        return initValue($(args[0].jsonVal.getInt()))
      of JFloat:
        return initValue($(args[0].jsonVal.getFloat()))
      of JBool:
        return initValue($(args[0].jsonVal.getBool()))
      of JString:
        return initValue(args[0].jsonVal.getStr())
      else: discard # todo handle nil
  )

  script.addProc(result, "toString", @[paramDef("x", ttyObject)], ttyString,
    proc (args: StackView): Value =
      ## Convert Object to JSON string
      result = initValue(convertObjectToJson(args[0]))
    )

  script.addProc(result, "toKeys", @[paramDef("obj", ttyJson)], ttyJson,
    proc (args: StackView): Value =
      ## Get the keys of a JSON object as an array.
      result = initValue(%*(args[0].jsonVal.keys().toSeq()))
    )

  script.addProc(result, "echo", @[paramDef("x", ttyString)], ttyVoid,
    proc (args: StackView): Value =
      echo args[0].stringVal[])

  script.addProc(result, "echo", @[paramDef("x", ttyInt)], ttyVoid,
    proc (args: StackView): Value =
      echo args[0].intVal)

  script.addProc(result, "echo", @[paramDef("x", ttyFloat)], ttyVoid,
    proc (args: StackView): Value =
      echo args[0].floatVal)

  script.addProc(result, "echo", @[paramDef("x", ttyBool)], ttyVoid,
    proc (args: StackView): Value =
      echo args[0].boolVal)

  script.addProc(result, "echo", @[paramDef("x", ttyJson)], ttyVoid,
    proc (args: StackView): Value =
      case args[0].jsonVal.kind
      of JInt, JFloat, JBool:
        echo $(args[0].jsonVal)
      of JString:
        echo args[0].jsonVal.getStr()
      else:
        echo toJson(args[0].jsonVal)
    )

  script.addProc(result, "echo", @[paramDef("x", ttyNil)], ttyVoid,
    proc (args: StackView): Value =
      echo "nil")

  script.addProc(result, "echo", @[paramDef("x", ttyObject)], ttyVoid,
    proc (args: StackView): Value =
      echo convertObjectToJson(args[0])
    )

  script.addProc(result, "echo", @[paramDef("x", ttyArray)], ttyVoid,
    proc (args: StackView): Value =
      debugEcho args[0]
    )

  script.addProc(result, "echo", @[paramDef("x", ttyPointer)], ttyVoid,
    proc (args: StackView): Value =
      if args[0].objectVal == nil or args[0].objectVal.data == nil:
        echo "pointer(nil)"
      else:
        echo "pointer(", $(cast[int64](args[0].objectVal.data)), ")"
    )

  let genT = ast.newIdent("T")
  let genArrayType = newSym(skGenericParam, genT, impl = genT)
  genArrayType.constraint = result.sym"any"

  # script.addProc(result, "len", @[paramDef("x", ttyArray, sym = genArrayType)], ttyInt,
  #   proc (args: StackView): Value =
  #     result = initValue(len(args[0].objectVal.fields)))

  # script.addProc(result, "high", @[paramDef("x", ttyArray, sym = genArrayType)], ttyInt,
  #   proc (args: StackView): Value =
  #     result = initValue(high(args[0].objectVal.fields)))

  script.addProc(result, "high", @[paramDef("x", ttyJson)], ttyInt,
    proc (args: StackView): Value =
      let len =
        if args[0].jsonVal.len > 0:
          len(args[0].jsonVal) - 1
        else: 0
      result = initValue(len)
    )

  script.addProc(result, "high", @[paramDef("x", ttyArray)], ttyInt,
    proc (args: StackView): Value =
      let len =
        if args[0].objectVal.fields.len > 0:
          len(args[0].objectVal.fields) - 1
        else: 0
      result = initValue(len)
    )

  # script.addProc(result, "len", @[paramDef("x", ttyObject)], ttyInt,
  #   proc (args: StackView): Value =
  #     result = initValue(len(args[0].objectVal.fields)))

  #
  # Mutable number operations
  #
  script.addProc(result, "inc", @[paramDef("i", ttyInt, mut = true)], ttyVoid,
    proc (args: StackView): Value =
      inc(args[0].intVal))

  script.addProc(result, "dec", @[paramDef("i", ttyInt, mut = true)], ttyVoid,
    proc (args: StackView): Value =
      dec(args[0].intVal))

  #
  # String concatenation
  #
  script.addProc(result, "&", @[paramDef("x", ttyString), paramDef("y", ttyString)], ttyString,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] & args[1].stringVal[]))

  script.addProc(result, "&", @[paramDef("x", ttyString), paramDef("y", ttyInt)], ttyString,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] & $(args[1].intVal)))

  script.addProc(result, "&", @[paramDef("x", ttyInt), paramDef("y", ttyString)], ttyString,
    proc (args: StackView): Value =
      result = initValue($(args[0].intVal) & args[1].stringVal[]))

  script.addProc(result, "&", @[paramDef("x", ttyString), paramDef("y", ttyFloat)], ttyString,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] & $(args[1].floatVal)))

  script.addProc(result, "&", @[paramDef("x", ttyFloat), paramDef("y", ttyString)], ttyString,
    proc (args: StackView): Value =
      result = initValue($(args[1].floatVal) & args[0].stringVal[]))

  script.addProc(result, "&", @[paramDef("x", ttyString), paramDef("y", ttyBool)], ttyString,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] & $(args[1].boolVal)))

  script.addProc(result, "&", @[paramDef("x", ttyBool), paramDef("y", ttyString)], ttyString,
    proc (args: StackView): Value =
      result = initValue($(args[0].boolVal) & args[1].stringVal[]))

  #
  # String concatenation with JSON
  #
  script.addProc(result, "&", @[paramDef("x", ttyJson), paramDef("y", ttyString)], ttyString,
    proc (args: StackView): Value =
      case args[0].jsonVal.kind
      of JString:
        result = initValue(args[0].jsonVal.getStr() & args[1].stringVal[])
      of JInt:
        result = initValue($(args[0].jsonVal.getInt()) & args[1].stringVal[])
      else: discard # todo error?
    )

  script.addProc(result, "&", @[paramDef("x", ttyString), paramDef("y", ttyJson)], ttyString,
    proc (args: StackView): Value =
      case args[1].jsonVal.kind
      of JString:
        result = initValue(args[0].stringVal[] & args[1].jsonVal.getStr())
      else: discard # todo error?
    )

  script.addProc(result, "hasKey", @[paramDef("obj", ttyJson), paramDef("key", ttyString)], ttyBool,
    proc (args: StackView): Value =
      result = initvalue(false)
      if args[0].jsonVal.hasKey(args[1].stringVal[]):
        result.boolVal = true
    )

  #
  # Random Utils
  #
  randomize()
  script.addProc(result, "shuffle", @[paramDef("arr", ttyArray)], ttyArray,
    proc (args: StackView): Value =
      var arr = initArray(args[0].objectVal.fields.len)
      for i in 0..<args[0].objectVal.fields.len:
        arr.objectVal.fields[i] = args[0].objectVal.fields[i]
      arr.objectVal.fields.shuffle()
      result = arr
    )

  #
  # Echo `$` operator
  #
  # script.addProc(result, "$", @[paramDef("x", ttyBool)], ttyString,
  #   proc (args: StackView): Value =
  #     result = initValue($args[0].boolVal))

  # script.addProc(result, "$", @[paramDef("x", ttyInt)], ttyString,
  #   proc (args: StackView): Value =
  #     result = initValue($args[0].intVal))

  # script.addProc(result, "$", @[paramDef("x", ttyFloat)], ttyString,
  #   proc (args: StackView): Value =
  #     result = initValue($args[0].floatVal))

  # script.addProc(result, "$", @[paramDef("x", ttyString)], ttyString,
  #   proc (args: StackView): Value =
  #     result = initValue(args[0].stringVal[]))

  # script.addProc(result, "$", @[paramDef("x", ttyJson)], ttyString,
  #   proc (args: StackView): Value =
  #     result = initValue(toJson(args[0].jsonVal)))

  #
  # Content Length
  #
  script.addProc(result, "len", @[paramDef("x", ttyString)], ttyInt,
    proc (args: StackView): Value =
      result = initValue(len(args[0].stringVal[])))

  script.addProc(result, "len", @[paramDef("x", ttyJson)], ttyInt,
    proc (args: StackView): Value =
      result = initValue(len(args[0].jsonVal)))

  script.addProc(result, "len", @[paramDef("x", ttyArray)], ttyInt,
    proc (args: StackView): Value =
      result = initValue(len(args[0].objectVal.fields)))


  #
  # Built-in OS Operations
  # std/os
  #
  script.addProc(result, "readFile", @[paramDef("path", ttyString)], ttyString,
    proc (args: StackView): Value =
      initValue(readFile(args[0].stringVal[])))

  script.addProc(result, "writeFile",
    @[paramDef("path", ttyString), paramDef("content", ttyString)], ttyVoid,
    proc (args: StackView): Value =
      writeFile(args[0].stringVal[], args[0].stringVal[]))

  script.addProc(result, "sleep", @[paramDef("ms", ttyInt)], ttyVoid,
    proc (args: StackView): Value =
      sleep(args[0].intVal))

  #
  # Builtin JSON/YAML support
  #
  script.addProc(result, "parseJSON", @[paramDef("content", ttyString)], ttyJson,
    proc (args: StackView): Value =
      result = initValue(fromJson(args[0].stringVal[]))
    )

  script.addProc(result, "loadJSON", @[paramDef("path", ttyString)], ttyJson,
    proc (args: StackView): Value =
      let jsonContent = readFile(args[0].stringVal[])
      result = initValue(fromJson(jsonContent))
    )
  
  script.addProc(result, "remoteJSON", @[paramDef("url", ttyString)], ttyJson,
    proc (args: StackView): Value =
      ## Fetch a remote JSON file from the given URL.
      var client = newHttpClient()
      try:
        let res = client.get(args[0].stringVal[])
        var resp = %*{
          "status": res.status,
          "headers": toJson(res.headers.table).fromJson(),
          "content": fromJson(res.body)
        }
        result = initValue(resp)
      except:
        let err = getCurrentExceptionMsg()
        var resp = %*{
          "status": 0,
          "headers": %*{},
          "content": %*{"error": err}
        }
        result = initValue(resp)
      finally:
        client.close()
    )

  for someTy in [ttyBool, ttyInt, ttyFloat, ttyString, ttyJson, ttyNil]:
    script.addProc(result, "==", @[paramDef("a", ttyJson), paramDef("b", someTy)], ttyBool,
      proc (args: StackView): Value =
        case args[1].typeId
        of tyBool:
          result = initValue(args[0].jsonVal.getBool() == args[1].boolVal)
        of tyInt:
          result = initValue(args[0].jsonVal.getInt() == args[1].intVal)
        of tyFloat:
          result = initValue(args[0].jsonVal.getFloat() == args[1].floatVal)
        of tyString:
          result = initValue(args[0].jsonVal.getStr() == args[1].stringVal[])
        of tyJsonStorage:
          result = initValue(args[0].jsonVal == args[1].jsonVal)
        of tyNil:
          result = initValue(args[0].jsonVal.kind == JNull)
        else:
          raise newException(TimRuntime, "Invalid type for comparison with JSON.")
      )

    script.addProc(result, "==", @[paramDef("a", someTy), paramDef("b", ttyJson)], ttyBool,
      proc (args: StackView): Value =
        case args[0].typeId
        of tyBool:
          result = initValue(args[0].boolVal == args[1].jsonVal.getBool())
        of tyInt:
          result = initValue(args[0].intVal == args[1].jsonVal.getInt())
        of tyFloat:
          result = initValue(args[0].floatVal == args[1].jsonVal.getFloat())
        of tyString:
          result = initValue(args[0].stringVal[] == args[1].jsonVal.getStr())
        of tyJsonStorage:
          result = initValue(args[0].jsonVal == args[1].jsonVal)
        of tyNil:
          result = initValue(args[1].jsonVal.kind == JNull)
        else:
          raise newException(TimRuntime, "Invalid type for comparison with JSON.")
      )

    script.addProc(result, "!=", @[paramDef("a", ttyJson), paramDef("b", someTy)], ttyBool,
      proc (args: StackView): Value =
        case args[1].typeId
        of tyBool:
          result = initValue(args[0].jsonVal.getBool() != args[1].boolVal)
        of tyInt:
          result = initValue(args[0].jsonVal.getInt() != args[1].intVal)
        of tyFloat:
          result = initValue(args[0].jsonVal.getFloat() != args[1].floatVal)
        of tyString:
          result = initValue(args[0].jsonVal.getStr() != args[1].stringVal[])
        of tyJsonStorage:
          result = initValue(args[0].jsonVal != args[1].jsonVal)
        of tyNil:
          result = initValue(args[0].jsonVal.kind != JNull)
        else:
          raise newException(TimRuntime, "Invalid type for comparison with JSON.")
    )

    script.addProc(result, "!=", @[paramDef("a", someTy), paramDef("b", ttyJson)], ttyBool,
      proc (args: StackView): Value =
        case args[0].typeId
        of tyBool:
          result = initValue(args[0].boolVal != args[1].jsonVal.getBool())
        of tyInt:
          result = initValue(args[0].intVal != args[1].jsonVal.getInt())
        of tyFloat:
          result = initValue(args[0].floatVal != args[1].jsonVal.getFloat())
        of tyString:
          result = initValue(args[0].stringVal[] != args[1].jsonVal.getStr())
        of tyJsonStorage:
          result = initValue(args[0].jsonVal != args[1].jsonVal)
        of tyNil:
          result = initValue(args[0].jsonVal.kind != JNull)
        else:
          raise newException(TimRuntime, "Invalid type for comparison with JSON.")
    )

  var inlineCode = Globals % ["globalData", toJson(globalData), "localData", toJson(localData)]
  inlineCode.add(InlineCode)
  script.compileCode(result, "system", inlineCode)