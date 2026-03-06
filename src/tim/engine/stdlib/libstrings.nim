# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[strutils, options, base64]
import pkg/voodoo/language/[chunk, ast, sym, value]

import ./inliner

proc initStrings*(script: Script, systemModule: Module): Module =
  # foreign stuff
  result = newModule("strings", some"strings.timl")
  result.load(systemModule)

  script.addProc(result, "contains", @[paramDef("s", ttyString), paramDef("sub", ttyString)], ttyBool,
    proc (args: StackView): Value =
      initValue(strutils.contains(args[0].stringVal[], args[1].stringVal[])))

  script.addProc(result, "startsWith", @[paramDef("s", ttyString), paramDef("prefix", ttyString)], ttyBool,
    proc (args: StackView): Value =
      initValue(strutils.startsWith(args[0].stringVal[], args[1].stringVal[])))

  script.addProc(result, "endsWith", @[paramDef("s", ttyString), paramDef("suffix", ttyString)], ttyBool,
    proc (args: StackView): Value =
      initValue(strutils.endsWith(args[0].stringVal[], args[1].stringVal[])))

  script.addProc(result, "toUpper", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView): Value =
      initValue(strutils.toUpperAscii(args[0].stringVal[])))

  # script.addProc(result, "isUpper", @[paramDef("s", ttyString)], ttyBool,
  #   proc (args: StackView): Value =
  #     # todo handle utf8
  #     initValue(strutils.isUpperAscii(args[0].stringVal[])))

  script.addProc(result, "toLower", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView): Value =
      initValue(strutils.toLowerAscii(args[0].stringVal[])))

  # script.addProc(result, "isLower", @[paramDef("s", ttyString)], ttyBool,
  #   proc (args: StackView): Value =
  #     # todo handle utf8
  #     initValue(strutils.isLowerAscii(args[0].stringVal[])))

  #
  # Base64 encoding/decoding
  #
  script.addProc(result, "encode", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView): Value =
      initValue(base64.encode(args[0].stringVal[])))

  script.addProc(result, "decode", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView): Value =
      initValue(base64.decode(args[0].stringVal[])))
