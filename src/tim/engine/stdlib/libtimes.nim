# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://tim-engine.com

import std/times
import ../[chunk, codegen, parser, sym, value]

proc initTimes*(script: Script, systemModule: Module): Module =
  # foreign stuff
  result = newModule("times")
  result.load(systemModule)

  script.addProc(result, "now", @[], tyString,
    proc (args: StackView): Value =
      initValue($(now())))