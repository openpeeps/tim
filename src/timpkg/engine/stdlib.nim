# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[macros, macrocache, enumutils, hashes,
  os, math, strutils, re, sequtils, critbits,
  random, unicode, json, tables, base64,
  httpclient, oids]

import pkg/[jsony, nyml, urlly]
import pkg/checksums/md5
import ./ast

type
  Arg* = tuple[name: string, value: Node]
  NimCallableHandle* = proc(args: openarray[Arg], returnType: NodeType = ntLitVoid): Node

  Module = OrderedTable[Hash, NimCallableHandle]
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
    urlModule {.threadvar.},
    localModule* {.threadvar.}: Module

const NimblePkgVersion {.strdefine.} = "Unknown"
const version = NimblePkgVersion

proc toNimSeq*(node: Node): seq[string] =
  for item in node.arrayItems:
    result.add(item.sVal)

proc getHashedIdent*(key: string): Hash =
  if key.len > 1:
    hash(key[0] & key[1..^1].toLowerAscii)
  else:
    hash(key)

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

  proc registerFunction(id: string, args: openarray[(NodeType, string)], nt: NodeType): string =
    var p = args.map do:
              proc(x: (NodeType, string)): string =
                "$1: $2" % [x[1], $(x[0])]
    result = "fn $1*($2): $3\n" % [id, p.join(", "), $nt]

  # proc registerVariable(id: string, dataType: DataType, varValue: Node) {.compileTime.} =
  #   # discard

  proc fwd(id: string, returns: NodeType, args: openarray[(NodeType, string)] = [],
      alias = "", wrapper: NimNode = nil, src = ""): Forward =
    Forward(
      id: id,
      returns: returns,
      args: args.toSeq,
      alias: alias,
      wrapper: wrapper,
      hasWrapper: wrapper != nil,
      src: src
    )

  proc argToSeq[T](arg: Arg): T =
    toNimSeq(arg.value)

  template formatWrapper: untyped =
    try:
      ast.newString(format(args[0].value.sVal, argToSeq[seq[string]](args[1])))
    except ValueError as e:
      raise newException(StringsModule, e.msg)

  template systemStreamFunction: untyped =
    try:
      let src =
        if not isAbsolute(args[0].value.sVal):
          absolutePath(args[0].value.sVal)
        else: args[0].value.sVal
      let str = readFile(src)
      let ext = src.splitFile.ext
      if ext == ".json":
        return ast.newStream(jsony.fromJson(str, JsonNode))
      elif ext in [".yml", ".yaml"]:
        return ast.newStream(yaml(str).toJson.get)
      else:
        echo "error"
    except IOError as e:
      raise newException(SystemModule, e.msg)
    except JsonParsingError as e:
      raise newException(SystemModule, e.msg)

  template systemStreamString: untyped =
    var res: Node
    if args[0].value.nt == ntLitString:
      res = ast.newStream(jsony.fromJson(args[0].value.sVal, JsonNode))
    elif args[0].value.nt == ntStream:
      if args[0].value.streamContent.kind == JString:
        res = ast.newStream(jsony.fromJson(args[0].value.streamContent.str, JsonNode))
      else: discard # todo conversion error
    res

  template systemJsonUrlStream =
    # retrieve JSON content from remote source
    # parse and return it as a Stream node
    var httpClient: HttpClient =
      if args.len == 1:
        newHttpClient(userAgent = "Tim Engine v" & version)
      else:
        let httpHeaders = newHttpHeaders()
        for k, v in args[1].value.objectItems:
          httpHeaders[k] = v.toString()
        newHttpClient(userAgent = "Tim Engine v" & version, headers = httpHeaders)
    let streamNode: Node = ast.newNode(ntStream)
    try:      
      let contents = httpClient.getContent(args[0].value.sVal)
      streamNode.streamContent = fromJson(contents)
      streamNode
    finally:
      httpClient.close()

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
      of ntLitBool:
        str = ast.newString($(val.bVal))
      of ntStream:
        if likely(val.streamContent != nil):
          case val.streamContent.kind:
            of JString:
              str = ast.newString($(val.streamContent.str))
            of JBool:
              str = ast.newString($(val.streamContent.bval))
            of JInt:
              str = ast.newString($(val.streamContent.num))
            of JFloat:
              str = ast.newString($(val.streamContent.fnum))
            of JNull:
              str = ast.newString("null")
            else: discard # should dump Object/Array too?
      else: discard
    str

  template parseCode: untyped =
    var xast: Node = ast.newNode(ntRuntimeCode)
    xast.runtimeCode = args[0].value.sVal
    xast

  template systemArrayLen =
    let x = ast.newNode(ntLitInt)
    x.iVal = args[0].value.arrayItems.len
    x

  template systemStreamLen =
    let x = ast.newNode(ntLitInt)
    x.iVal =
      case args[0].value.streamContent.kind
      of JString:
        len(args[0].value.streamContent.getStr)
      else: 0 # todo error
    x
  
  template generateId =
    ast.newString($genOid())

  template generateUuid4 = 
    ast.newString("todo")

  template genBase64 = 
    let base64Obj = ast.newObject(ObjectStorage())
    # let encodeFn = ast.newFunction(returnType = ntLitString)
    base64Obj.objectItems["encode"] =
      createFunction:
        returnType = typeString
        params = [("str", typeString, nil)]
    base64Obj

  let
    fnSystem = @[
      fwd("json", ntStream, [(ntLitString, "path")], wrapper = getAst(systemStreamFunction())),
      fwd("parseJsonString", ntStream, [(ntLitString, "path")], wrapper = getAst(systemStreamString())),
      fwd("parseJsonString", ntStream, [(ntStream, "path")], wrapper = getAst(systemStreamString())),
      fwd("remoteJson", ntStream, [(ntLitString, "path")], wrapper = getAst(systemJsonUrlStream())),
      fwd("remoteJson", ntStream, [(ntLitString, "path"), (ntLitObject, "headers")], wrapper = getAst(systemJsonUrlStream())),
      fwd("yaml", ntStream, [(ntLitString, "path")], wrapper = getAst(systemStreamFunction())),
      fwd("rand", ntLitInt, [(ntLitInt, "max")], "random", wrapper = getAst(systemRandomize())),
      fwd("len", ntLitInt, [(ntLitString, "x")]),
      fwd("len", ntLitInt, [(ntLitArray, "x")], wrapper = getAst(systemArrayLen())),
      fwd("len", ntLitInt, [(ntStream, "x")], wrapper = getAst(systemStreamLen())),
      fwd("encode", ntLitString, [(ntLitString, "x")], src = "base64"),
      fwd("decode", ntLitString, [(ntLitString, "x")], src = "base64"),
      fwd("toString", ntLitString, [(ntLitInt, "x")], wrapper = getAst(convertToString())),
      fwd("toString", ntLitString, [(ntLitBool, "x")], wrapper = getAst(convertToString())),
      fwd("toString", ntLitString, [(ntStream, "x")], wrapper = getAst(convertToString())),
      fwd("timl", ntLitString, [(ntLitString, "x")], wrapper = getAst(parseCode())),
      fwd("inc", ntLitVoid, [(ntLitInt, "x")], wrapper = getAst(systemInc())),
      fwd("dec", ntLitVoid, [(ntLitInt, "x")]),
      fwd("genid", ntLitString, wrapper = getAst(generateId())),
      fwd("uuid4", ntLitString, wrapper = getAst(generateUuid4())),
      fwd("base64", ntLitObject, wrapper = getAst(genBase64()))
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

  template strRegexFind =
    let arrayNode = ast.newNode(ntLitArray)
    for res in re.findAll(args[0].value.sVal, re(args[1].value.sVal)):
      let strNode = ast.newNode(ntLitString)
      strNode.sVal = res
      add arrayNode.arrayItems, strNode
    arrayNode

  template strRegexMatch =
    let boolNode = ast.newNode(ntLitBool)
    boolNode.bVal = re.match(args[0].value.sVal, re(args[1].value.sVal))
    boolNode

  template strStartsWithStream = 
    let boolNode = ast.newNode(ntLitBool)
    if args[1].value.streamContent.kind == JString:
      boolNode.bVal = strutils.startsWith(args[0].value.sVal, args[1].value.streamContent.str)
    boolNode

  template strStreamStartsWith = 
    let boolNode = ast.newNode(ntLitBool)
    if args[0].value.streamContent.kind == JString:
      boolNode.bVal = strutils.startsWith(args[0].value.streamContent.str, args[1].value.sVal)
    boolNode

  let
    fnStrings = @[
      fwd("endsWith", ntLitBool, [(ntLitString, "s"), (ntLitString, "suffix")]),
      fwd("startsWith", ntLitBool, [(ntLitString, "s"), (ntLitString, "prefix")]),
      fwd("startsWith", ntLitBool, [(ntLitString, "s"), (ntStream, "prefix")], wrapper = getAst(strStartsWithStream())),
      fwd("startsWith", ntLitBool, [(ntStream, "s"), (ntLitString, "prefix")], wrapper = getAst(strStreamStartsWith())),
      fwd("capitalizeAscii", ntLitString, [(ntLitString, "s")], "capitalize"),
      fwd("replace", ntLitString, [(ntLitString, "s"), (ntLitString, "sub"), (ntLitString, "by")]),
      fwd("toLowerAscii", ntLitString, [(ntLitString, "s")], "toLower"),
      fwd("toUpperAscii", ntLitString, [(ntLitString, "s")], "toUpper"),
      fwd("contains", ntLitBool, [(ntLitString, "s"), (ntLitString, "sub")]),
      fwd("parseBool", ntLitBool, [(ntLitString, "s")]),
      fwd("parseInt", ntLitInt, [(ntLitString, "s")]),
      fwd("parseFloat", ntLitFloat, [(ntLitString, "s")]),
      fwd("format", ntLitString, [(ntLitString, "s"), (ntLitArray, "a")], wrapper = getAst(formatWrapper())),
      fwd("find", ntLitArray, [(ntLitString, "s"), (ntLitString, "pattern")], wrapper = getAst(strRegexFind())),
      fwd("match", ntLitBool, [(ntLitString, "s"), (ntLitString, "pattern")], wrapper = getAst(strRegexMatch()))
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

  template arraysShuffle =
    randomize()
    shuffle(args[0].value.arrayItems)

  template arraysJoin =
    if args.len == 2:
      ast.newString(strutils.join(
        toNimSeq(args[0].value), args[1].value.sVal))
    else:
      ast.newString(strutils.join(toNimSeq(args[0].value)))
  
  template arraysDelete =
    delete(args[0].value.arrayItems, args[1].value.iVal)

  template arraysFind =
    for i in 0..args[0].value.arrayItems.high:
      if args[0].value.arrayItems[i].sVal == args[1].value.sVal:
        return ast.newInteger(i)

  template arrayHigh =
    ast.newInteger(args[0].value.arrayItems.high)

  template arraySplit =
    let arr = ast.newArray()
    for x in strutils.split(args[0].value.sVal, args[1].value.sVal):
      add arr.arrayItems, ast.newString(x)
    arr

  template arrayCountdown = 
    let arr = ast.newArray()
    for i in countdown(args[0].value.arrayItems.high, 0):
      add arr.arrayItems, args[0].value.arrayItems[i]
    arr

  let
    fnArrays = @[
      fwd("contains", ntLitBool, [(ntLitArray, "x"), (ntLitString, "item")], wrapper = getAst arraysContains()),
      fwd("add", ntLitVoid, [(ntLitArray, "x"), (ntLitString, "item")], wrapper = getAst arraysAdd()),
      fwd("add", ntLitVoid, [(ntLitArray, "x"), (ntLitInt, "item")], wrapper = getAst arraysAdd()),
      fwd("add", ntLitVoid, [(ntLitArray, "x"), (ntLitBool, "item")], wrapper = getAst arraysAdd()),
      fwd("shift", ntLitVoid, [(ntLitArray, "x")], wrapper = getAst arraysShift()),
      fwd("pop", ntLitVoid, [(ntLitArray, "x")], wrapper = getAst arraysPop()),
      fwd("shuffle", ntLitVoid, [(ntLitArray, "x")], wrapper = getAst arraysShuffle()),
      fwd("join", ntLitString, [(ntLitArray, "x"), (ntLitString, "sep")], wrapper = getAst arraysJoin()),
      fwd("join", ntLitString, [(ntLitArray, "x")], wrapper = getAst arraysJoin()),
      fwd("delete", ntLitVoid, [(ntLitArray, "x"), (ntLitInt, "pos")], wrapper = getAst arraysDelete()),
      fwd("find", ntLitInt, [(ntLitArray, "x"), (ntLitString, "item")], wrapper = getAst arraysFind()),
      fwd("high", ntLitInt, [(ntLitArray, "x")], wrapper = getAst(arrayHigh())),
      fwd("split", ntLitArray, [(ntLitString, "s"), (ntLitString, "sep")], wrapper = getAst(arraySplit())),
      fwd("countdown", ntLitArray, [(ntLitArray, "x")], wrapper = getAst(arrayCountdown())),
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
  # implements some basic read-only operating system functions
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
  
  #
  # std/url
  # https://treeform.github.io/urlly/urlly.html
  template urlParse =
    let address =
      if args[0].value.nt == ntLitString:
        args[0].value.sVal
      else:
        ast.toString(args[0].value.streamContent)
    let someUrl: Url = parseUrl(address)
    let paths = ast.newArray()
    for somePath in someUrl.paths:
      add paths.arrayItems, ast.newString(somePath)
    let objectResult = ast.newObject(newOrderedTable({
      "scheme": ast.newString(someUrl.scheme),
      "username": ast.newString(someUrl.username),
      "password": ast.newString(someUrl.password),
      "hostname": ast.newString(someUrl.hostname),
      "port": ast.newString(someUrl.port),
      "fragment": ast.newString(someUrl.fragment),
      "paths": paths,
      "secured": ast.newBool(someUrl.scheme in ["https", "ftps"])
    }))

    let queryTable = ast.newObject(ObjectStorage())
    for query in someUrl.query:
      queryTable.objectItems[query[0]] = ast.newString(query[1])
    objectResult.objectItems["query"] = queryTable
    objectResult

  let
    fnUrl = @[
      fwd("parseUrl", ntLitObject, [(ntLitString, "s")], wrapper = getAst(urlParse())),
      fwd("parseUrl", ntLitObject, [(ntStream, "s")], wrapper = getAst(urlParse())),
    ]

  #
  # Times
  #
  # template timesParseDate =
  #   let obj = ast.newNode(ntLitObject)
  #   # obj.objectItems[""]

  # let
  #   fnTimes = @[
  #     fwd("parseDate", ntLitObject, [(ntLitString, "input"), (ntLitString, "format")], wrapper = getAst(timesParseDate())])
  #   ]

  result = newStmtList()
  let libs = [
    ("system", fnSystem, "system"),
    ("math", fnMath, "math"),
    ("strutils", fnStrings, "strings"),
    ("sequtils", fnArrays, "arrays"),
    ("objects", fnObjects, "objects"),
    ("os", fnOs, "os"),
    ("url", fnUrl, "url"),
    # ("times", fnTimes, "times"),
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
      add sourceCode,
        registerFunction(fnIdent, fn.args, fn.returns)
      var callNode: NimNode
      var hashKey = getHashedIdent(fnIdent)
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
          hashKey = hashKey !& hashIdentity(arg[0].getDataType())
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
                nnkBracketExpr.newTree(ident"args", newLit(i)),
                ident"value"
              ),
            )
          inc i
        if fn.returns != ntLitVoid:
          callNode = newCall(ident(valNode), callableNode)
        else:
          callNode =
            nnkStmtList.newTree(
              callableNode,
              newCall(ident"getVoidNode")
            )
      else:
        for arg in fn.args:
          hashKey = hashKey !& hashIdentity(arg[0].getDataType())
        if fn.returns != ntLitVoid:
          callNode = fn.wrapper
        else:
          callNode =
            nnkStmtList.newTree(
              fn.wrapper,
              newCall(ident"getVoidNode")
            )
      lambda.add(newStmtList(callNode))
      # let fnName = fnIdent[0] & fnIdent[1..^1].toLowerAscii
      add result,
        newAssignment(
          nnkBracketExpr.newTree(
            ident(lib[0] & "Module"),
            newLit hashKey
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

proc call*(lib: string, hashKey: Hash, args: seq[Arg]): Node =
  ## Retrieves a Nim proc from `module`
  # let key = fnName[0] & fnName[1..^1].toLowerAscii
  result = stdlib[lib][0][hashKey](args)
