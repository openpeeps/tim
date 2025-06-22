# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, monotimes, times, strutils, options, ropes]

import pkg/[flatty, jsony]
import pkg/kapsis/[cli, runtime]

import ../engine/[ast, parser, codegen, chunk, vm, sym]
import ../engine/stdlib/[libsystem, libtimes, libstrings]

import ../engine/transpilers/javascript/jscodegen

proc srcCommand*(v: Values) =
  ## Transpiles `timl` code to a target source
  # parse the script
  let
    srcPath = getCurrentDir() / $(v.get("timl").getPath)
    ext = v.get("-t").getStr
    pretty = v.has("--pretty")
    flagNoCache = v.has("--nocache")
    flagRecache = v.has("--recache")
    hasDataFlag = v.has("--data")
    hasJsonFlag = v.has("--json-errors")
    outputPath = if v.has("-o"): v.get("-o").getStr else: ""
    withBenchtime = v.has("--bench")
    # enableWatcher = v.has("w")

  let
    timlCode = readFile(srcPath)
    t = getMonotime()
  
  var program: Ast # the AST representation of the script
  try:
    parser.parseScript(program, timlCode)
  except TimParserError as e:
    echo e.msg
    quit(1)
    
  # writeFile("test.ast", toFlatty(program))

  var
    mainChunk = newChunk()
    script = newScript(mainChunk)
    module = newModule(srcPath.extractFilename, some(srcPath))

  # load standard library modules
  let systemModule = modSystem(script)
  module.load(systemModule)

  # let stringsLib = initStrings(script, systemModule)
  # module.load(stringsLib)

  script.stdpos = script.procs.high

  # let timesModule = script.initTimes(systemModule)
  # module.load(timesModule)

  if ext == "html":
    try:
      var compiler = codegen.initCodeGen(script, module, mainChunk)
      compiler.genScript(program, none(string), isMainScript = true)
      let vmInstance = newVm()
      let output = vmInstance.interpret(script, mainChunk)
      
      # if the output path is specified, write the output to the file
      # todo

      # otherwise, print the output to the console
      echo output
      
      # display the time taken for compilation
      if withBenchtime:
        displayInfo("Done in " & $(getMonotime() - t))    
    except TimCompileError as e:
      echo e.msg
      quit(1)
  elif ext == "js":
    var jst = jscodegen.initCodeGen(script, module, mainChunk)
    echo jst.genScript(program, none(string), isMainScript = true)

#
# AST 
#
proc astCommand*(v: Values) =
  ## Generate the AST representation of a `timl` script
  let
    srcPath = getCurrentDir() / $(v.get("timl").getPath)
    timlCode = readFile(srcPath)
  
  var program: Ast # the AST representation of the script
  parser.parseScript(program, timlCode)
  writeFile(srcPath & ".ast", toFlatty(program))