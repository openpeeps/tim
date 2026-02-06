# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, monotimes, times, strutils, json, options, ropes]

import pkg/[flatty, jsony]
import pkg/kapsis/[cli, runtime]

import pkg/voodoo/language/[ast, codegen, chunk, sym, vm]
import pkg/voodoo/packagemanager/packager

import ../engine/parser
import ../engine/stdlib/[libsystem, libarrays, libffi]
import ../engine/transpilers/[jsgen, pygen, rbgen, phpgen, luagen, nimgen]

proc parserCallback(astProgram: var Ast, path: string) =
  parser.parseScript(astProgram, readFile(path), path)

proc srcCommand*(v: Values) =
  ## Transpiles `timl` code to a target source
  # parse the script
  var srcPath = $(v.get("timl").getPath)
  
  # init the package manager and load the local packages
  let pkgr = packager.initPackageRemote()
  pkgr.loadPackages()

  let 
    ext = v.get("--ext").getStr
    flagPrettyPrint = v.has("--pretty")
    flagNoCache = v.has("--nocache")
    flagRecache = v.has("--recache")
    hasJsonFlag = v.has("--json-errors")
    outputPath = if v.has("-o"): v.get("-o").getStr else: ""
    flagBencmarks = v.has("--bench")
    # enableWatcher = v.has("w")
  
  if not srcPath.isAbsolute:
    srcPath = getCurrentDir() / srcPath

  let
    timlCode = readFile(srcPath)
    t = getMonotime()
    data =
      if v.has("--data"):
        v.get("--data").getJson
      else:
        newJObject()
    globalData =
      if data != nil:
        if data.hasKey"app":
          data["app"]
        else: newJObject()
      else: newJObject()
    localData =
      if data != nil:
        if data.hasKey"this":
          data["this"]
        else: newJObject()
      else: newJObject()

  var program: Ast # the AST representation of the script
  try:
    parser.parseScript(program, timlCode, srcPath)
  except TimParserError as e:
    echo e.msg
    quit(1)

  var
    mainChunk = newChunk(srcPath)
    script = newScript(mainChunk)
    module = newModule(srcPath.extractFilename, some(srcPath))

  # load standard library modules
  let systemModule = libsystem.loadLibrary(script, globalData, localData)
  module.load(systemModule)

  # let stringsLib = initStrings(script, systemModule)
  # module.load(stringsLib)

  # let ffiLib = initFFI(script, systemModule)
  # module.load(ffiLib)

  # let arraysLib = initArrays(script, systemModule)
  # module.load(arraysLib)

  script.stdpos = script.procs.high

  # let timesModule = script.initTimes(systemModule)
  # module.load(timesModule)
  if ext == "html":
    try:
      var compiler = codegen.initCodeGen(script, module, mainChunk, pkgr = pkgr,
                                    parserCallback = parserCallback)
      compiler.genScript(program, none(string))

      let vmInstance = newVm()
      let output = vmInstance.interpret(script, mainChunk)
      echo output
    except CodeGenError as e:
      echo e.msg
      quit(1)
  elif ext == "js":
    var jst = jsgen.initCodeGen(script, module, mainChunk)
    echo jst.genScript(program, none(string), isMainScript = true)
  elif ext == "py":
    var pyt = pygen.initCodeGen(script, module, mainChunk)
    echo pyt.genScript(program, none(string), isMainScript = true)
  elif ext == "rb":
    var rbt = rbgen.initCodeGen(script, module, mainChunk)
    echo rbt.genScript(program, none(string), isMainScript = true)
  elif ext == "php":
    var phpt = phpgen.initCodeGen(script, module, mainChunk)
    echo phpt.genScript(program, none(string), isMainScript = true)
  elif ext == "lua":
    var lut = luagen.initCodeGen(script, module, mainChunk)
    echo lut.genScript(program, none(string), isMainScript = true)
  elif ext == "nim":
    var nimt = nimgen.initCodeGen(script, module, mainChunk)
    echo nimt.genScript(program, none(string), isMainScript = true)
  else:
    displayError("Unsupported target source extension: " & ext)
    quit(1)

  # display the time taken for compilation
  if flagBencmarks:
    displayInfo("Done in " & $(getMonotime() - t))

#
# AST 
#
proc astCommand*(v: Values) =
  ## Generate the AST representation of a `timl` script
  let
    srcPath = getCurrentDir() / $(v.get("timl").getPath)
    timlCode = readFile(srcPath)
  
  var program: Ast # the AST representation of the script
  parser.parseScript(program, timlCode, srcPath)
  writeFile(srcPath & ".ast", toFlatty(program))