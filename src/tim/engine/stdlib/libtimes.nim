# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[times, options]
import pkg/voodoo/language/[chunk, sym, value]
import ./inliner

proc loadTimes*(script: Script, systemModule: Module): Module =
  # foreign stuff
  result = newModule("times", some"times.timl")
  result.load(systemModule)

  script.addProc(result, "now", @[], tyString,
    proc (args: StackView): Value =
      initValue($(now())))

  script.addProc(result, "getCurrentYear", @[], tyInt,
    proc (args: StackView): Value =
      result = initValue(now().year)
    )