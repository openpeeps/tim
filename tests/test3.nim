import unittest
import std/[os, monotimes, times, osproc,
        strutils, json, options, ropes]

import pkg/[flatty, jsony]

import ../src/tim/engine/transformers

import pkg/voodoo/language/[ast, codegen, chunk, sym, vm]
import pkg/voodoo/packagemanager/packager

import ../src/tim/engine/parser
import ../src/tim/engine/stdlib/[libsystem, libarrays, libffi]
import ../src/tim/engine/transpilers/[jsgen, pygen, rbgen, phpgen, luagen, nimgen]

proc parserCallback(astProgram: var Ast, path: string) =
  parser.parseScript(astProgram, readFile(path), path)

template initPackageManager() {.dirty.} =
  let pkgr = packager.initPackageRemote()
  pkgr.loadPackages()

template initParser(code: string, srcPath = "HelloWorld") {.dirty.} =
  var program: Ast
  try:
    parser.parseScript(program, code, srcPath)
  except TimParserError as e:
    doAssert false, "Parsing failed with error: " & e.msg

  var
    mainChunk = newChunk(srcPath)
    script = newScript(mainChunk)
    module = newModule(srcPath.extractFilename, some(srcPath))

template initLibrary() {.dirty.} =
  let
    data = newJObject()
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
  let systemModule = libsystem.loadLibrary(script, globalData, localData)
  module.load(systemModule)

proc rubyWrapper(x: Rope, className: string): string =
  result = $x
  result.add("\n")
  result.add(className & ".render")

proc pythonWrapper(x: Rope, className: string): string =
  result = $x
  result.add("\n")
  result.add("print(" & className & ".render())")

const
  sample1 = """
var hello = "Tim Engine is Awesome!"
echo $hello
"""

test "s2s ruby":
  initPackageManager()
  initParser(sample1)
  initLibrary()

  var rbt = rbgen.initCodeGen(script, module, mainChunk)
  let output = rbt.genScript(program, none(string), isMainScript = true)
  echo "Generated Ruby code:\n" & output
  let s2sPath = getCurrentDir() / "tests" / "s2s"
  
  discard existsOrCreateDir(s2sPath)
  writeFile(s2sPath / "sample1.rb", rubyWrapper(output, "HelloWorld"))
  let stsOutput = execCmdEx("ruby " & s2sPath / "sample1.rb")
  assert stsOutput.exitCode == 0
  assert stsOutput.output.strip() == "Tim Engine is Awesome!"
  echo stsOutput.output

test "s2s python":
  initPackageManager()
  initParser(sample1)
  initLibrary()

  var pyt = pygen.initCodeGen(script, module, mainChunk)
  let output = pyt.genScript(program, none(string), isMainScript = true)
  echo "Generated Python code:\n" & output
  let s2sPath = getCurrentDir() / "tests" / "s2s"
  
  discard existsOrCreateDir(s2sPath)
  writeFile(s2sPath / "sample1.py", pythonWrapper(output, "HelloWorld"))
  
  let stsOutput = execCmdEx("python " & s2sPath / "sample1.py")
  assert stsOutput.exitCode == 0
  assert stsOutput.output.strip() == "Tim Engine is Awesome!"
  echo stsOutput.output