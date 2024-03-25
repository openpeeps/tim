# A super fast stylesheet language for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/bro

import std/[macros, enumutils, critbits]
import ./ast

# std lib dependencies
import pkg/[jsony, nyml]
import std/[os, math, fenv, strutils, sequtils,
  random, unicode, json, base64]

# import ./css

type
  Arg* = tuple[name: string, value: Node]
  NimCall* = proc(args: openarray[Arg], returnType: NodeType = ntUnknown): Node

  Module = CritBitTree[NimCall]
  SourceCode* = distinct string

  Stdlib* = CritBitTree[(Module, SourceCode)]

  StringsModule* = object of CatchableError
  ArraysModule* = object of CatchableError
  OSModule* = object of CatchableError
  ColorsModule* = object of CatchableError
  SystemModule* = object of CatchableError

var
  stdlib*: Stdlib
  strutilsModule {.threadvar.},
    sequtilsModule {.threadvar.},
    osModule {.threadvar.},
    critbitsModule {.threadvar.},
    systemModule {.threadvar.},
    mathModule {.threadvar.},
    chromaModule {.threadvar.}: Module

proc toNimSeq*(node: Node): seq[string] =
  for item in node.arrayItems:
    result.add(item.sVal)

macro initStandardLibrary() =
  type
    Wrapper = proc(args: seq[Node]): Node {.nimcall.}
    
    FwdType = enum
      fwdProc
      fwdIterator

    Forward = object
      fwdType: FwdType
      id: string
        # function identifier (nim side)
      alias: string
        # if not provided, it will use the `id`
        # for the bass function name
      returns: NodeType
        # the return type, one of: `ntLitString`, `ntLitInt`,
        # `ntLitBool`, `ntLitFloat`, `ntLitArray`, `ntLitObject`
      args: seq[(NodeType, string)]
        # a seq of NodeType for type matching
      wrapper: NimNode
        # wraps nim function
      hasWrapper: bool
      loadFrom: string

  proc addFunction(id: string, args: openarray[(NodeType, string)], nt: NodeType): string =
    var p = args.map do:
              proc(x: (NodeType, string)): string =
                "$1: $2" % [x[1], $(x[0])]
    result = "fn $1*($2): $3\n" % [id, p.join(", "), $nt]

  proc fwd(id: string, returns: NodeType, args: openarray[(NodeType, string)] = [],
      alias = "", wrapper: NimNode = nil, loadFrom = ""): Forward =
    Forward(id: id, returns: returns, args: args.toSeq,
        alias: alias, wrapper: wrapper, hasWrapper: wrapper != nil,
        loadFrom: loadFrom)

  # proc `*`(nt: NodeType, count: int): seq[NodeType] =
  #   for i in countup(1, count):
  #     result.add(nt)

  proc argToSeq[T](arg: Arg): T =
    toNimSeq(arg.value)

  template formatWrapper: untyped =
    try:
      ast.newString(format(args[0].value.sVal, argToSeq[seq[string]](args[1])))
    except ValueError as e:
      raise newException(StringsModule, e.msg)

  template systemStreamFunction: untyped =
    try:
      let filepath =
        if not isAbsolute(args[0].value.sVal):
          absolutePath(args[0].value.sVal)
        else: args[0].value.sVal
      let str = readFile(filepath)
      let ext = filepath.splitFile.ext
      if ext == ".json":
        return ast.newStream(str.fromJson(JsonNode))
      elif ext in [".yml", ".yaml"]:
        return ast.newStream(yaml(str).toJson.get)
      else:
        echo "error"
    except IOError as e:
      raise newException(SystemModule, e.msg)
    except JsonParsingError as e:
      raise newException(SystemModule, e.msg)

  template systemRandomize: untyped =
    randomize()
    ast.newInteger(rand(args[0].value.iVal))

  template systemInc: untyped =
    inc args[0].value.iVal
    echo args[0].value
    args[0].value

  template convertToString: untyped =
    var str: ast.Node
    var val = args[0].value
    case val.nt:
      of ntLitInt:
        str = ast.newString($(val.iVal))
      of ntLitFloat:
        str = ast.newString($(val.fVal))
      else: discard
    str

  let
    fnSystem = @[
      # fwd("json", ntStream, [(ntLitString, "path")], wrapper = getAst(systemStreamFunction())),
      # fwd("yaml", ntStream, [(ntLitString, "path")], wrapper = getAst(systemStreamFunction())),
      fwd("rand", ntLitInt, [(ntLitInt, "max")], "random", wrapper = getAst(systemRandomize())),
      fwd("len", ntLitInt, [(ntLitString, "x")]),
      # fwd("len", ntLitInt, [(ntLitArray, "x")]),
      fwd("encode", ntLitString, [(ntLitString, "x")], loadFrom = "base64"),
      fwd("decode", ntLitString, [(ntLitString, "x")], loadFrom = "base64"),
      fwd("toString", ntLitString, [(ntLitInt, "x")], wrapper = getAst(convertToString()))
      # fwd("int", ntInt, [(ntLitInt, "x")], "increment", wrapper = getAst(systemInc())),
    ]

  let
    fnMath = @[
      fwd("ceil", ntLitFloat, [(ntLitFloat, "x")]),
      # fwd("clamp") need to add support for ranges
      fwd("floor", ntLitFloat, [(ntLitFloat, "x")]),
      fwd("max", ntLitInt, [(ntLitInt, "x"), (ntLitInt, "y")], loadFrom = "system"),
      fwd("min", ntLitInt, [(ntLitInt, "x"), (ntLitInt, "y")], loadFrom = "system"),
      fwd("round", ntLitFloat, [(ntLitFloat, "x")]),
      # fwd("abs", ntLitInt, [(ntLitInt, "x")]),
      fwd("hypot", ntLitFloat, [(ntLitFloat, "x"), (ntLitFloat, "y")]),
      fwd("log", ntLitFloat, [(ntLitFloat, "x"), (ntLitFloat, "base")]),
      fwd("pow", ntLitFloat, [(ntLitFloat, "x"), (ntLitFloat, "y")]),
      fwd("sqrt", ntLitFloat, [(ntLitFloat, "x")]),
      fwd("cos", ntLitFloat, [(ntLitFloat, "x")]),
      fwd("sin", ntLitFloat, [(ntLitFloat, "x")]),
      fwd("tan", ntLitFloat, [(ntLitFloat, "x")]),
      fwd("arccos", ntLitFloat, [(ntLitFloat, "x")], "acos"),
      fwd("arcsin", ntLitFloat, [(ntLitFloat, "x")], "asin"),
      fwd("radToDeg", ntLitFloat, [(ntLitFloat, "d")], "rad2deg"),
      fwd("degToRad", ntLitFloat, [(ntLitFloat, "d")], "deg2rad"),
      fwd("arctan", ntLitFloat, [(ntLitFloat, "x")], "atan"),
      fwd("arctan2", ntLitFloat, [(ntLitFloat, "x"), (ntLitFloat, "y")], "atan2"),
      fwd("trunc", ntLitFloat, [(ntLitFloat, "x")]),
    ]
    # std/strings
    # implements common functions for working with strings
    # https://nim-lang.github.io/Nim/strutils.html
  let
    fnStrings = @[
      fwd("endsWith", ntLitBool, [(ntLitString, "s"), (ntLitString, "suffix")]),
      fwd("startsWith", ntLitBool, [(ntLitString, "s"), (ntLitString, "prefix")]),
      fwd("capitalizeAscii", ntLitString, [(ntLitString, "s")], "capitalize"),
      fwd("replace", ntLitString, [(ntLitString, "s"), (ntLitString, "sub"), (ntLitString, "by")]),
      fwd("toLowerAscii", ntLitString, [(ntLitString, "s")], "toLower"),
      fwd("contains", ntLitBool, [(ntLitString, "s"), (ntLitString, "sub")]),
      fwd("parseBool", ntLitBool, [(ntLitString, "s")]),
      fwd("parseInt", ntLitInt, [(ntLitString, "s")]),
      fwd("parseFloat", ntLitFloat, [(ntLitString, "s")], "toFloat"),
      fwd("format", ntLitString, [(ntLitString, "s"), (ntLitArray, "a")], wrapper = getAst(formatWrapper()))
    ]

  # std/arrays
  # implements common functions for working with arrays (sequences)
  # https://nim-lang.github.io/Nim/sequtils.html
  
  template arraysContains: untyped =
    ast.newBool(system.contains(toNimSeq(args[0].value), args[1].value.sVal))

  template arraysAdd: untyped =
    add(args[0].value.arrayItems, args[1].value)

  template arraysShift: untyped =
    try:
      delete(args[0].value.arrayItems, 0)
    except IndexDefect as e:
      raise newException(ArraysModule, e.msg)

  template arraysPop: untyped =
    try:
      delete(args[0].value.arrayItems, args[0].value.arrayItems.high)
    except IndexDefect as e:
      raise newException(ArraysModule, e.msg)

  template arraysShuffle: untyped =
    randomize()
    shuffle(args[0].value.arrayItems)

  template arraysJoin: untyped =
    ast.newString(strutils.join(toNimSeq(args[0].value), args[1].value.sVal))
  
  template arraysDelete: untyped =
    delete(args[0].value.arrayItems, args[1].value.iVal)

  template arraysFind: untyped =
    for i in 0..args[0].value.arrayItems.high:
      if args[0].value.arrayItems[i].sVal == args[1].value.sVal:
        return ast.newInteger(i)

  let
    fnArrays = @[
      fwd("contains", ntLitBool, [(ntLitArray, "x"), (ntLitString, "item")], wrapper = getAst arraysContains()),
      fwd("add", ntUnknown, [(ntLitArray, "x"), (ntLitString, "item")], wrapper = getAst arraysAdd()),
      fwd("shift", ntUnknown, [(ntLitArray, "x")], wrapper = getAst arraysShift()),
      fwd("pop", ntUnknown, [(ntLitArray, "x")], wrapper = getAst arraysPop()),
      fwd("shuffle", ntUnknown, [(ntLitArray, "x")], wrapper = getAst arraysShuffle()),
      fwd("join", ntLitString, [(ntLitArray, "x"), (ntLitString, "sep")], wrapper = getAst arraysJoin()),
      fwd("delete", ntUnknown, [(ntLitArray, "x"), (ntLitInt, "pos")], wrapper = getAst arraysDelete()),
      fwd("find", ntLitInt, [(ntLitArray, "x"), (ntLitString, "item")], wrapper = getAst arraysFind()),
    ]
    # fnObjects = @[
    #   fwd("hasKey", ntLitBool, [ntLitObject, ntLitString]),
    #   # fwd("keys", ntLitArray, [ntLitObject])
    # ]


  # std/os
  # implements some read-only basic operating system functions
  # https://nim-lang.org/docs/os.html 
  template osWalkFiles: untyped =
    let x = toSeq(walkPattern(args[0].value.sVal))
    var a = ast.newArray()
    a.arrayType = ntLitString
    a.arrayItems =
      x.map do:
        proc(xpath: string): Node = ast.newString(xpath)
    a
  let
    fnOs = @[
      fwd("absolutePath", ntLitString, [(ntLitString, "path")]),
      fwd("dirExists", ntLitBool, [(ntLitString, "path")]),
      fwd("fileExists", ntLitBool, [(ntLitString, "path")]),
      fwd("normalizedPath", ntLitString, [(ntLitString, "path")], "normalize"),
      # fwd("splitFile", ntTuple, [ntLitString]),
      fwd("extractFilename", ntLitString, [(ntLitString, "path")], "getFilename"),
      fwd("isAbsolute", ntLitBool, [(ntLitString, "path")]),
      fwd("readFile", ntLitString, [(ntLitString, "path")], loadFrom="system"),
      fwd("isRelativeTo", ntLitBool, [(ntLitString, "path"), (ntLitString, "base")], "isRelative"),
      fwd("getCurrentDir", ntLitString),
      fwd("joinPath", ntLitString, [(ntLitString, "head"), (ntLitString, "tail")], "join"),
      fwd("parentDir", ntLitString, [(ntLitString, "path")]),
      fwd("walkFiles", ntLitArray, [(ntLitString, "path")], wrapper = getAst osWalkFiles()),
    ]

  result = newStmtList()
  let libs = [
    ("system", fnSystem, "system"),
    ("math", fnMath, "math"),
    ("strutils", fnStrings, "strings"),
    ("sequtils", fnArrays, "arrays"),
    ("os", fnOs, "os")
  ]
  echo "Generate Standard Library"
  for lib in libs:
    var sourceCode: string
    for fn in lib[1]:
      var
        lambda = nnkLambda.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode())
        params = newNimNode(nnkFormalParams)
      params.add(
        ident("Node"),
        nnkIdentDefs.newTree(
          ident("args"),
          nnkBracketExpr.newTree(
            ident("openarray"),
            ident("Arg")
          ),
          newEmptyNode()
        ),
        nnkIdentDefs.newTree(
          ident("returnType"),
          ident("NodeType"),
          ident(symbolName(fn.returns))
        )
      )
      lambda.add(params)
      lambda.add(newEmptyNode())
      lambda.add(newEmptyNode())
      var valNode = 
        case fn.returns:
        of ntLitBool: "newBool"
        of ntLitString: "newString"
        of ntLitInt: "newInteger"
        of ntLitFloat: "newFloat"
        of ntLitArray: "newArray" # todo implement toArray
        of ntLitObject: "newObject" # todo implement toObject
        else: ""
      var i = 0
      var fnIdent = if fn.alias.len != 0: fn.alias else: fn.id
      add sourceCode, addFunction(fnIdent, fn.args, fn.returns)
      var callNode: NimNode
      if not fn.hasWrapper:
        var callableNode =
          if lib[0] != "system":
            if fn.loadFrom.len == 0:
              newCall(newDotExpr(ident(lib[0]), ident(fn.id)))
            else:
              newCall(newDotExpr(ident(fn.loadFrom), ident(fn.id)))
          else:
            if fn.loadFrom.len == 0:
              newCall(newDotExpr(ident("system"), ident(fn.id)))
            else:
              newCall(newDotExpr(ident(fn.loadFrom), ident(fn.id)))
        for arg in fn.args:
          let fieldName =
            case arg[0]
            of ntLitBool: "bVal"
            of ntLitString: "sVal"
            of ntLitInt: "iVal"
            of ntLitFloat: "fVal"
            of ntLitArray: "arrayItems"
            of ntLitObject: "pairsVal"
            else: "None"
          if fieldName.len != 0:
            callableNode.add(
              newDotExpr(
                newDotExpr(
                  nnkBracketExpr.newTree(
                    ident("args"),
                    newLit(i)
                  ),
                  ident("value")
                ),
                ident(fieldName)
              )
            )
          else:
            callableNode.add(
              newDotExpr(
                nnkBracketExpr.newTree(
                  ident("args"),
                  newLit(i)
                ),
                ident("value")
              ),
            )
          inc i
        callNode = newCall(ident(valNode), callableNode)
      else:
        callNode = fn.wrapper
      lambda.add(newStmtList(callNode))
      add result,
        newAssignment(
          nnkBracketExpr.newTree(
            ident(lib[0] & "Module"),
            newLit(fnIdent)
          ),
          lambda
        )
    add result,
      newAssignment(
        nnkBracketExpr.newTree(
          ident("stdlib"),
          newLit("std/" & lib[2])
        ),
        nnkTupleConstr.newTree(
          ident(lib[0] & "Module"),
          newCall(ident("SourceCode"), newLit(sourceCode))
        )
      )
    when not defined release:
      echo "std/" & lib[2]
      echo sourceCode

proc initstdlib*() =
  {.gcsafe.}:
    initStandardLibrary()

proc exists*(lib: string): bool =
  ## Checks if if `lib` exists in `Stdlib` 
  result = stdlib.hasKey(lib)

proc std*(lib: string): (Module, SourceCode) {.raises: KeyError.} =
  ## Retrieves a module from `Stdlib`
  result = stdlib[lib]

proc call*(lib, fnName: string, args: seq[Arg]): Node =
  ## Retrieves a Nim proc from `module`
  result = stdlib[lib][0][fnName](args)
