# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://tim-engine.com

import std/[strutils, options, os, json]
import pkg/jsony

import ../[chunk, codegen, ast, parser, sym, value]

proc compileCode*(script: Script, module: Module, filename, code: string) =
  ## Compile some hayago code to the given script and module.
  ## Any generated toplevel code is discarded. This should only be used for
  ## declarations of hayago-side things, eg. iterators.
  var astProgram: Ast
  parser.parseScript(astProgram, code)
  var
    codeChunk = newChunk()
    gen = initCodeGen(script, module, codeChunk)
  gen.genScript(astProgram)

const
  InlineCode* = """
iterator `..`*(min: int, max: int): int {
  var i = min
  while $i <= max {
    yield($i)
    $i = $i + 1
  }
}
  """

proc initSystemOps(script: Script, module: Module) =
  ## Add builtin operations into the module.
  ## This should only ever be called when creating the ``system`` module.

  # bool operators
  script.addProc(module, "not", @[paramDef("x", tyBool)], tyBool)
  script.addProc(module, "==", @[paramDef("a", tyBool), paramDef("b", tyBool)], tyBool)
  script.addProc(module, "!=", @[paramDef("a", tyBool), paramDef("b", tyBool)], tyBool)

  # number type operators

  for T in [(tyInt, tyFloat), (tyFloat, tyInt)]:
    script.addProc(module, "+", @[paramDef("a", T[0])], T[0])
    script.addProc(module, "-", @[paramDef("a", T[0])], T[0])
    
    script.addProc(module, "+", @[paramDef("a", T[0]), paramDef("b", T[1])], tyFloat)
    script.addProc(module, "-", @[paramDef("a", T[0]), paramDef("b", T[1])], tyFloat)
    script.addProc(module, "*", @[paramDef("X", T[0]), paramDef("b", T[1])], tyFloat)
    script.addProc(module, "/", @[paramDef("a", T[0]), paramDef("b", T[1])], tyFloat)
  
    script.addProc(module, "==", @[paramDef("a", T[0]), paramDef("b", T[1])], tyBool)
    script.addProc(module, "!=", @[paramDef("a", T[0]), paramDef("b", T[1])], tyBool)
    script.addProc(module, "<", @[paramDef("a", T[0]), paramDef("b", T[1])], tyBool)
    script.addProc(module, "<=", @[paramDef("a", T[0]), paramDef("b", T[1])], tyBool)
    script.addProc(module, ">", @[paramDef("a", T[0]), paramDef("b", T[1])], tyBool)
    script.addProc(module, ">=", @[paramDef("a", T[0]), paramDef("b", T[1])], tyBool)

  for T in [(tyInt, tyInt), (tyFloat, tyFloat)]:
    script.addProc(module, "+=", @[paramDef("a", T[0], mut = true), paramDef("b", T[1])], tyVoid)
    script.addProc(module, "-=", @[paramDef("a", T[0], mut = true), paramDef("b", T[1])], tyVoid)
    script.addProc(module, "*=", @[paramDef("a", T[0], mut = true), paramDef("b", T[1])], tyVoid)
    script.addProc(module, "/=", @[paramDef("a", T[0], mut = true), paramDef("b", T[1])], tyVoid)
  
  script.addProc(module, "==", @[paramDef("a", tyBool), paramDef("b", tyBool)], tyBool)
  script.addProc(module, "!=", @[paramDef("a", tyBool), paramDef("b", tyBool)], tyBool)

proc modSystem*(script: Script): Module =
  ## Create and initialize the ``system`` module.

  # foreign stuff
  result = newModule("system", some"system.timl")
  result.initSystemTypes()
  script.initSystemOps(result)

  # string operators
  script.addProc(result, "==", @[paramDef("a", tyString), paramDef("b", tyString)], tyBool,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] == args[1].stringVal[]))

  script.addProc(result, "!=", @[paramDef("a", tyString), paramDef("b", tyString)], tyBool,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] != args[1].stringVal[]))

  script.addProc(result, "is", @[paramDef("a", tyString), paramDef("b", tyString)], tyBool,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] == args[1].stringVal[]))
  
  script.addProc(result, "isnot", @[paramDef("a", tyString), paramDef("b", tyString)], tyBool,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] != args[1].stringVal[]))

  script.addProc(result, "is", @[paramDef("a", tyBool), paramDef("b", tyBool)], tyBool,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] == args[1].stringVal[]))
  
  script.addProc(result, "isnot", @[paramDef("a", tyBool), paramDef("b", tyBool)], tyBool,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] != args[1].stringVal[]))
  
  script.addProc(result, "type", @[paramDef("x", tyAny)], tyString,
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
        else: "object"
      result = initValue(valueType))

  # logical operators
  # script.addProc(result, "and", @[paramDef("x", tyBool), paramDef("y", tyBool)], tyBool,
  #   proc (args: StackView): Value =
  #     debugEcho args[0]
  #     debugEcho args[1]
  #     result = initValue(args[0].boolVal and args[1].boolVal))

  # converters
  script.addProc(result, "toInt", @[paramDef("f", tyFloat)], tyInt,
    proc (args: StackView): Value =
      result = initValue(toInt(args[0].floatVal)))

  script.addProc(result, "parseInt", @[paramDef("i", tyString)], tyInt,
    proc (args: StackView): Value =
      ## Convert a string to an int.
      result = initValue(parseInt(args[0].stringVal[])))

  script.addProc(result, "toFloat", @[paramDef("i", tyInt)], tyFloat,
    proc (args: StackView): Value =
      ## Convert an int to a float
      result = initValue(toFloat(args[0].intVal)))

  #
  # String conversion
  #
  script.addProc(result, "toString", @[paramDef("x", tyInt)], tyString,
    proc (args: StackView): Value =
      ## Convert an int to a string
      result = initValue($(args[0].intVal))
    )

  script.addProc(result, "toString", @[paramDef("x", tyFloat)], tyString,
    proc (args: StackView): Value =
      ## Convert a float to a string
      result = initValue($(args[0].floatVal))
    )

  script.addProc(result, "toString", @[paramDef("x", tyBool)], tyString,
    proc (args: StackView): Value =
      ## Convert bool to string
      result = initValue($(args[0].boolVal))
    )

  script.addProc(result, "echo", @[paramDef("x", tyString)], tyVoid,
    proc (args: StackView): Value =
      echo args[0].stringVal[])

  script.addProc(result, "echo", @[paramDef("x", tyInt)], tyVoid,
    proc (args: StackView): Value =
      echo args[0].intVal)

  script.addProc(result, "echo", @[paramDef("x", tyFloat)], tyVoid,
    proc (args: StackView): Value =
      echo args[0].floatVal)

  script.addProc(result, "echo", @[paramDef("x", tyBool)], tyVoid,
    proc (args: StackView): Value =
      echo args[0].boolVal)

  script.addProc(result, "echo", @[paramDef("x", tyJson)], tyVoid,
    proc (args: StackView): Value =
      case args[0].jsonVal.kind
      of JInt, JFloat, JBool:
        echo $(args[0].jsonVal)
      of JString:
        echo args[0].jsonVal.getStr()
      else:
        echo jsony.toJson(args[0].jsonVal)
    )

  script.addProc(result, "echo", @[paramDef("x", tyNil)], tyVoid,
    proc (args: StackView): Value =
      echo "nil")

  # script.addProc(result, "echo", @[paramDef("x", tyHtmlElement, kindStr = "div")], tyVoid,
  #   proc (args: StackView): Value =
  #     debugecho args[0].objectVal.fields
  #     # echo "<div>"
  #   )

  script.addProc(result, "echo", @[paramDef("x", tyArray)], tyVoid,
    proc (args: StackView): Value =
      debugEcho args[0]
    )

  script.addProc(result, "len", @[paramDef("x", tyArray)], tyInt,
    proc (args: StackView): Value =
      result = initValue(len(args[0].objectVal.fields)))

  # script.addProc(result, "len", @[paramDef("x", tyObject)], tyInt,
  #   proc (args: StackView): Value =
  #     result = initValue(len(args[0].objectVal.fields)))

  #
  # Mutable number operations
  #
  script.addProc(result, "inc", @[paramDef("i", tyInt, mut = true)], tyVoid,
    proc (args: StackView): Value =
      inc(args[0].intVal))

  script.addProc(result, "dec", @[paramDef("i", tyInt, mut = true)], tyVoid,
    proc (args: StackView): Value =
      dec(args[0].intVal))

  #
  # String concatenation
  #
  script.addProc(result, "&", @[paramDef("x", tyString), paramDef("y", tyString)], tyString,
    proc (args: StackView): Value =
      result = initValue(args[0].stringVal[] & args[1].stringVal[]))

  #
  # Echo `$` operator
  #
  # script.addProc(result, "$", @[paramDef("x", tyBool)], tyString,
  #   proc (args: StackView): Value =
  #     result = initValue($args[0].boolVal))

  # script.addProc(result, "$", @[paramDef("x", tyInt)], tyString,
  #   proc (args: StackView): Value =
  #     result = initValue($args[0].intVal))

  # script.addProc(result, "$", @[paramDef("x", tyFloat)], tyString,
  #   proc (args: StackView): Value =
  #     result = initValue($args[0].floatVal))

  # script.addProc(result, "$", @[paramDef("x", tyString)], tyString,
  #   proc (args: StackView): Value =
  #     result = initValue(args[0].stringVal[]))

  # script.addProc(result, "$", @[paramDef("x", tyJson)], tyString,
  #   proc (args: StackView): Value =
  #     result = initValue(jsony.toJson(args[0].jsonVal)))

  #
  # Content Length
  #
  script.addProc(result, "len", @[paramDef("x", tyString)], tyInt,
    proc (args: StackView): Value =
      result = initValue(len(args[0].stringVal[])))

  #
  # Built-in OS Operations
  # std/os
  #
  script.addProc(result, "readFile", @[paramDef("filename", tyString)], tyString,
    proc (args: StackView): Value =
      initValue(readFile(args[0].stringVal[])))

  script.addProc(result, "writeFile",
    @[paramDef("filename", tyString), paramDef("content", tyString)], tyVoid,
    proc (args: StackView): Value =
      writeFile(args[0].stringVal[], args[0].stringVal[]))

  script.addProc(result, "sleep", @[paramDef("ms", tyInt)], tyVoid,
    proc (args: StackView): Value =
      sleep(args[0].intVal))

  #
  # Builtin JSON/YAML support
  #
  script.addProc(result, "parseJSON", @[paramDef("content", tyString)], tyJson,
    proc (args: StackView): Value =
      result = initValue(jsony.fromJson(args[0].stringVal[]))
    )

  script.addProc(result, "loadJSON", @[paramDef("path", tyString)], tyJson,
    proc (args: StackView): Value =
      let jsonContent = readFile(args[0].stringVal[])
      result = initValue(jsony.fromJson(jsonContent))
    )

  script.addProc(result, "==", @[paramDef("a", tyJson), paramDef("b", tyJson)], tyBool,
    proc (args: StackView): Value =
      result = initValue(args[0].jsonVal == args[1].jsonVal))

  script.addProc(result, "!=", @[paramDef("a", tyJson), paramDef("b", tyJson)], tyBool,
    proc (args: StackView): Value =
      result = initValue(false == (args[0].jsonVal == args[1].jsonVal)))

  script.compileCode(result, "system", InlineCode)