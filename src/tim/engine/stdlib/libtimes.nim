# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[times, options]
import pkg/vancode/interpreter/[chunk, sym, value]
import ./inliner

proc loadTimes*(script: Script, systemModule: Module): Module =
  # foreign stuff
  result = newModule("times", some"times.timl")
  result.load(systemModule)

  script.addProc(result, "now", @[], ttyString,
    proc (args: StackView, argc: int): Value =
      initValue($(now())))

  script.addProc(result, "getCurrentYear", @[], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(now().year))

  script.addProc(result, "getCurrentMonth", @[], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(int(now().month)))

  script.addProc(result, "getCurrentDay", @[], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(now().monthday))

  script.addProc(result, "getCurrentHour", @[], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(now().hour))

  script.addProc(result, "getCurrentMinute", @[], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(now().minute))

  script.addProc(result, "getCurrentSecond", @[], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(now().second))

  script.addProc(result, "unix", @[], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(toUnix(now().toTime)))

  script.addProc(result, "dayOfWeek", @[], ttyString,
    proc (args: StackView, argc: int): Value =
      initValue($(now().weekDay)))

  script.addProc(result, "isLeapYear", @[paramDef("year", ttyInt)], ttyBool,
    proc (args: StackView, argc: int): Value =
      initValue(isLeapYear(args[0].intVal)))

  script.addProc(result, "format", @[paramDef("fmt", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      initValue(now().format(args[0].stringVal[])))