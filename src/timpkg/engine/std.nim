# A super fast stylesheet language for cool kids
#
# (c) 2024 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/bro

import std/[macros, macrocache, enumutils,
  critbits, os, math, fenv, strutils,
  sequtils, random, unicode, json, tables, base64]

import pkg/[jsony, nyml]

import ./ast, ./meta

type
  Arg* = tuple[name: string, value: Node]
  NimCallableHandle* = proc(args: openarray[Arg], returnType: NodeType = ntLitVoid): Node

  Module = CritBitTree[NimCallableHandle]
  SourceCode* = distinct string
  Stdlib = CritBitTree[(Module, SourceCode)]

  StringsModule* = object of CatchableError
  ArraysModule* = object of CatchableError
  OSModule* = object of CatchableError
  ColorsModule* = object of CatchableError
  SystemModule* = object of CatchableError
  ObjectsModule* = object of CatchableError

var
  stdlib*: Stdlib
  strutilsModule {.threadvar.},
    sequtilsModule {.threadvar.},
    osModule {.threadvar.},
    critbitsModule {.threadvar.},
    systemModule {.threadvar.},
    mathModule {.threadvar.},
    objectsModule {.threadvar.},
    localModule* {.threadvar.}: Module

proc toNimSeq*(node: Node): seq[string] =
  for item in node.arrayItems:
    result.add(item.sVal)

macro initStandardLibrary() =
  type
    Forward = object
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
      src: string

  proc addFunction(id: string,
      args: openarray[(NodeType, string)], nt: NodeType): string =
    var p = args.map do:
              proc(x: (NodeType, string)): string =
                "$1: $2" % [x[1], $(x[0])]
    result = "fn $1*($2): $3\n" % [id, p.join(", "), $nt]

  proc fwd(id: string, returns: NodeType, args: openarray[(NodeType, string)] = [],
      alias = "", wrapper: NimNode = nil, src = ""): Forward =
    Forward(id: id, returns: returns, args: args.toSeq,
        alias: alias, wrapper: wrapper, hasWrapper: wrapper != nil,
        src: src)

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

  template parseCode: untyped =
    var xast: Node = ast.newNode(ntRuntimeCode)
    xast.runtimeCode = args[0].value.sVal
    xast

  let
    fnSystem = @[
      # fwd("json", ntStream, [(ntLitString, "path")], wrapper = getAst(systemStreamFunction())),
      # fwd("yaml", ntStream, [(ntLitString, "path")], wrapper = getAst(systemStreamFunction())),
      fwd("rand", ntLitInt, [(ntLitInt, "max")], "random", wrapper = getAst(systemRandomize())),
      fwd("len", ntLitInt, [(ntLitString, "x")]),
      # fwd("len", ntLitInt, [(ntLitArray, "x")]),
      fwd("encode", ntLitString, [(ntLitString, "x")], src = "base64"),
      fwd("decode", ntLitString, [(ntLitString, "x")], src = "base64"),
      fwd("toString", ntLitString, [(ntLitInt, "x")], wrapper = getAst(convertToString())),
      fwd("timl", ntLitString, [(ntLitString, "x")], wrapper = getAst(parseCode())),
      fwd("inc", ntLitVoid, [(ntLitInt, "x")], wrapper = getAst(systemInc())),
      fwd("dec", ntLitVoid, [(ntLitInt, "x")]),
    ]

  let
    # std/math
    # implements basic math functions
    fnMath = @[
      fwd("ceil", ntLitFloat, [(ntLitFloat, "x")]),
      fwd("floor", ntLitFloat, [(ntLitFloat, "x")]),
      fwd("max", ntLitInt, [(ntLitInt, "x"), (ntLitInt, "y")], src = "system"),
      fwd("min", ntLitInt, [(ntLitInt, "x"), (ntLitInt, "y")], src = "system"),
      fwd("round", ntLitFloat, [(ntLitFloat, "x")]),
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
      fwd("parseFloat", ntLitFloat, [(ntLitString, "s")]),
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
      delete(args[0].value.arrayItems,
        args[0].value.arrayItems.high)
    except IndexDefect as e:
      raise newException(ArraysModule, e.msg)

  template arraysShuffle: untyped =
    randomize()
    shuffle(args[0].value.arrayItems)

  template arraysJoin: untyped =
    ast.newString(strutils.join(
      toNimSeq(args[0].value), args[1].value.sVal))
  
  template arraysDelete: untyped =
    delete(args[0].value.arrayItems, args[1].value.iVal)

  template arraysFind: untyped =
    for i in 0..args[0].value.arrayItems.high:
      if args[0].value.arrayItems[i].sVal == args[1].value.sVal:
        return ast.newInteger(i)
  let
    fnArrays = @[
      fwd("contains", ntLitBool, [(ntLitArray, "x"), (ntLitString, "item")], wrapper = getAst arraysContains()),
      fwd("add", ntLitVoid, [(ntLitArray, "x"), (ntLitString, "item")], wrapper = getAst arraysAdd()),
      fwd("shift", ntLitVoid, [(ntLitArray, "x")], wrapper = getAst arraysShift()),
      fwd("pop", ntLitVoid, [(ntLitArray, "x")], wrapper = getAst arraysPop()),
      fwd("shuffle", ntLitVoid, [(ntLitArray, "x")], wrapper = getAst arraysShuffle()),
      fwd("join", ntLitString, [(ntLitArray, "x"), (ntLitString, "sep")], wrapper = getAst arraysJoin()),
      fwd("delete", ntLitVoid, [(ntLitArray, "x"), (ntLitInt, "pos")], wrapper = getAst arraysDelete()),
      fwd("find", ntLitInt, [(ntLitArray, "x"), (ntLitString, "item")], wrapper = getAst arraysFind()),
    ]

  template objectHasKey: untyped =
    ast.newBool(args[0].value.objectItems.hasKey(args[1].value.sVal))

  template objectAddValue: untyped =
    args[0].value.objectItems[args[1].value.sVal] = args[2].value

  template objectDeleteValue: untyped =
    if args[0].value.objectItems.hasKey(args[1].value.sVal):
      args[0].value.objectItems.del(args[1].value.sVal)

  template objectClearValues: untyped =
    args[0].value.objectItems.clear()

  template objectLength: untyped =
    ast.newInteger(args[0].value.objectItems.len)

  template objectGetOrDefault: untyped =
    getOrDefault(args[0].value.objectItems, args[1].value.sVal)

  proc convertObjectCss(node: Node, isNested = false): string =
    var x: seq[string]
    for k, v in node.objectItems:
      case v.nt:
      of ntLitInt:
        add x, k & ":"
        add x[^1], $(v.iVal)
      of ntLitFloat:
        add x, k & ":"
        add x[^1], $(v.fVal)
      of ntLitString:
        add x, k & ":"
        add x[^1], v.sVal
      of ntLitObject: 
        if isNested:
          raise newException(ObjectsModule, "Cannot converted nested objects to CSS")
        add x, k & "{"
        add x[^1], convertObjectCss(v, true)
        add x[^1], "}"
      else: discard
    result = x.join(";")

  template objectInlineCss: untyped =
    ast.newString(convertObjectCss(args[0].value))

  let 
    fnObjects = @[
      fwd("hasKey", ntLitBool, [(ntLitObject, "x"), (ntLitString, "key")], wrapper = getAst(objectHasKey())),
      fwd("add", ntLitVoid, [(ntLitObject, "x"), (ntLitString, "key"), (ntLitString, "value")], wrapper = getAst(objectAddValue())),
      fwd("add", ntLitVoid, [(ntLitObject, "x"), (ntLitString, "key"), (ntLitInt, "value")], wrapper = getAst(objectAddValue())),
      fwd("add", ntLitVoid, [(ntLitObject, "x"), (ntLitString, "key"), (ntLitFloat, "value")], wrapper = getAst(objectAddValue())),
      fwd("add", ntLitVoid, [(ntLitObject, "x"), (ntLitString, "key"), (ntLitBool, "value")], wrapper = getAst(objectAddValue())),
      fwd("del", ntLitVoid, [(ntLitObject, "x"), (ntLitString, "key")], wrapper = getAst(objectDeleteValue())),
      fwd("len", ntLitInt, [(ntLitObject, "x")], wrapper = getAst(objectLength())),
      fwd("clear", ntLitVoid, [(ntLitObject, "x")], wrapper = getAst(objectClearValues())),
      fwd("toCSS", ntLitString, [(ntLitObject, "x")], wrapper = getAst(objectInlineCss())),
    ]

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
      fwd("readFile", ntLitString, [(ntLitString, "path")], src="system"),
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
    ("objects", fnObjects, "objects"),
    ("os", fnOs, "os")
  ]
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
        else: "getVoidNode"
      var i = 0
      var fnIdent =
        if fn.alias.len != 0: fn.alias
        else: fn.id

      add sourceCode, addFunction(fnIdent, fn.args, fn.returns)
      var callNode: NimNode
      if not fn.hasWrapper:
        var callableNode =
          if lib[0] != "system":
            if fn.src.len == 0:
              newCall(newDotExpr(ident(lib[0]), ident(fn.id)))
            else:
              newCall(newDotExpr(ident(fn.src), ident(fn.id)))
          else:
            if fn.src.len == 0:
              newCall(newDotExpr(ident("system"), ident(fn.id)))
            else:
              newCall(newDotExpr(ident(fn.src), ident(fn.id)))
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
                  nnkBracketExpr.newTree(ident("args"), newLit(i)),
                  ident("value")
                ),
                ident(fieldName)
              )
            )
          else:
            callableNode.add(
              newDotExpr(
                nnkBracketExpr.newTree(ident"args", newLit(i)),
                ident("value")
              ),
            )
          inc i
        if fn.returns != ntLitVoid:
          callNode = newCall(ident(valNode), callableNode)
        else:
          callNode = nnkStmtList.newTree(callableNode, newCall(ident("getVoidNode")))
      else:
        if fn.returns != ntLitVoid:
          callNode = fn.wrapper
        else:
          callNode = nnkStmtList.newTree(fn.wrapper, newCall(ident"getVoidNode"))
      lambda.add(newStmtList(callNode))
      let fnName = fnIdent[0] & fnIdent[1..^1].toLowerAscii
      add result,
        newAssignment(
          nnkBracketExpr.newTree(
            ident(lib[0] & "Module"),
            newLit(fnName)
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
    # when not defined release:
    # echo result.repr
    # echo "std/" & lib[2]
    # echo sourceCode

proc initModuleSystem* =
  {.gcsafe.}:
    initStandardLibrary()

proc exists*(lib: string): bool =
  ## Checks if `lib` exists in `stdlib` 
  result = stdlib.hasKey(lib)

proc std*(lib: string): (Module, SourceCode) {.raises: KeyError.} =
  ## Retrieves a module from `stdlib`
  result = stdlib[lib]

proc call*(lib, fnName: string, args: seq[Arg]): Node =
  ## Retrieves a Nim proc from `module`
  let key = fnName[0] & fnName[1..^1].toLowerAscii
  result = stdlib[lib][0][key](args)
