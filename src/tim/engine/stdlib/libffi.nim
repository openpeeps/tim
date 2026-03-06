# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[os, options, sequtils, tables, strutils, dynlib]
import pkg/voodoo/language/[chunk, ast, sym, value]

import ./inliner
import ../parser

type
  FFILoadError = object of CatchableError
  HelloWorldProc* = proc (name: cstring): cstring {.gcsafe, nimcall.}
  GreetingProc* = proc(): cstring {.gcsafe, nimcall.}

proc loadFFI*(script: Script, systemModule: Module): Module =
  # foreign stuff
  result = newModule("ffi", some"ffi.timl")
  result.load(systemModule)

  script.addProc(result, "loadLibrary", @[paramDef("s", ttyString)], ttyPointer,
    proc (args: StackView): Value =
      let path =
        if args[0].stringVal[].isAbsolute: args[0].stringVal[]
        else: normalizedPath(getCurrentDir() / args[0].stringVal[])
      var lib: LibHandle = nil
      if fileExists(path):
        lib = loadLib(path)
        if lib == nil:
          raise newException(FFILoadError, "Could not load library at: " & path)
        else:
          # echo "Loaded library at: ", path
          script.libs[path] = lib
          # let handle = cast[HelloWorldProc](symAddr(lib, "helloWorld"))
          # assert handle != nil
          # echo $(handle(" from FFI"))

          # let greeting = cast[GreetingProc](symAddr(lib, "getGreeting"))
          # assert greeting != nil
          # echo "Greeting from library: ", $greeting()
      else:
        raise newException(FFILoadError, "Library does not exist at: " & path)
      result = initvalue(lib, path)
  )