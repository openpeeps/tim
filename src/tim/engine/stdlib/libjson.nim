# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[options, json]
import pkg/voodoo/language/[chunk, ast, sym, value]

import ./inliner

proc initJSON*(script: Script, systemModule: Module): Module =
  # foreign stuff
  result = newModule("json", some"json.timl")
  result.load(systemModule)

  script.addProc(result, "join", @[paramDef("s", ttyJson), paramDef("sep", ttyString, initValue(", "))], ttyString,
    proc (args: StackView, argc: int): Value =
      # joins an array of strings with ", "
      result = initvalue("")
      let sep = args[1].stringVal[]
      for i, v in args[0].jsonVal.elems:
        case v.kind
        of JString:
          result.stringVal[] = result.stringVal[] & v.getStr()
        of JInt, JFloat, JBool:
          result.stringVal[] = result.stringVal[] & $v.getInt()
        else: discard
        if i < args[0].jsonVal.elems.len - 1:
          result.stringVal[] = result.stringVal[] & sep
  )
