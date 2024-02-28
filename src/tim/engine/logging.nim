# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

from ./tokens import TokenTuple
from ./ast import Meta

import std/[sequtils, strutils]

when compileOption("app", "console"):
  import pkg/kapsis/cli

type
  Message* = enum
    invalidIndentation = "Invalid indentation"
    unexpectedToken = "Unexpected token $"
    undeclaredVariable = "Undeclared variable $"
    invalidAccessorStorage = "Invalid accessor storage $ for $"
    varRedefine = "Attempt to redefine variable $"
    varImmutable = "Attempt to reassign value to immutable constant $"
    fnRedefine = "Attempt to redefine function $"
    fnUndeclared = "Undeclared function $"
    fnExtraArg = "Extra arguments given. Got $ expected $"
    badIndentation = "Nestable statement requires indentation"    
    invalidContext = "Invalid $ in this context"
    invalidViewLoader = "Invalid use of `@view` in this context. Use a layout instead"
    duplicateViewLoader = "Duplicate `@view` loader"
    typeMismatch = "Type mismatch. Got $ expected $"
    duplicateAttribute = "Duplicate HTML attribute $"
    duplicateField = "Duplicate field $"
    undeclaredField = "Undeclared field $"
    invalidIterator = "Invalid iterator"
    indexDefect = "Index $ not in $"
    importNotFound = "Cannot open file: $"
    importCircularError = "Circular import detected: $"
    internalError = "$"

  Level* = enum
    lvlInfo
    lvlNotice
    lvlWarn
    lvlError

  Log* = ref object
    msg: Message
    extraLabel: string
    line, col: int
    useFmt: bool
    args, extraLines: seq[string]

  Logger* = ref object
    filePath*: string
    infoLogs*, noticeLogs*, warnLogs*, errorLogs*: seq[Log]

proc add(logger: Logger, lvl: Level, msg: Message, line, col: int,
        useFmt: bool, args: varargs[string]) =
  let log = Log(msg: msg, args: args.toSeq(),
                line: line, col: col, useFmt: useFmt)
  case lvl
  of lvlInfo:
    logger.infoLogs.add(log)
  of lvlNotice:
    logger.noticeLogs.add(log)
  of lvlWarn:
    logger.warnLogs.add(log)
  of lvlError:
    logger.errorLogs.add(log)

proc add(logger: Logger, lvl: Level, msg: Message, line, col: int, useFmt: bool,
        extraLines: seq[string], extraLabel: string, args: varargs[string]) =
  let log = Log(
    msg: msg,
    args: args.toSeq(),
    line: line,
    col: col + 1,
    useFmt: useFmt,
    extraLines: extraLines,
    extraLabel: extraLabel
  )
  case lvl:
    of lvlInfo:
      logger.infoLogs.add(log)
    of lvlNotice:
      logger.noticeLogs.add(log)
    of lvlWarn:
      logger.warnLogs.add(log)
    of lvlError:
      logger.errorLogs.add(log)

proc getMessage*(log: Log): Message = 
  result = log.msg

proc newInfo*(logger: Logger, msg: Message, line, col: int,
        useFmt: bool, args:varargs[string]) =
  logger.add(lvlInfo, msg, line, col, useFmt, args)

proc newNotice*(logger: Logger, msg: Message, line, col: int,
        useFmt: bool, args:varargs[string]) =
  logger.add(lvlNotice, msg, line, col, useFmt, args)

proc newWarn*(logger: Logger, msg: Message, line, col: int,
        useFmt: bool, args:varargs[string]) =
  logger.add(lvlWarn, msg, line, col, useFmt, args)

proc newError*(logger: Logger, msg: Message, line, col: int, useFmt: bool, args:varargs[string]) =
  logger.add(lvlError, msg, line, col, useFmt, args)

proc newErrorMultiLines*(logger: Logger, msg: Message, line, col: int, 
        useFmt: bool, extraLines: seq[string], extraLabel: string, args:varargs[string]) =
  logger.add(lvlError, msg, line, col, useFmt, extraLines, extraLabel, args)

proc newWarningMultiLines*(logger: Logger, msg: Message, line, col: int,
        useFmt: bool, extraLines: seq[string], extraLabel: string, args:varargs[string]) =
  logger.add(lvlWarn, msg, line, col, useFmt, extraLines, extraLabel, args)

template warn*(msg: Message, tk: TokenTuple, args: varargs[string]) =
  p.logger.newWarn(msg, tk.line, tk.pos, false, args)

template warn*(msg: Message, tk: TokenTuple, strFmt: bool, args: varargs[string]) =
  p.logger.newWarn(msg, tk.line, tk.pos, true, args)  

proc warn*(logger: Logger, msg: Message, line, col: int, args: varargs[string]) =
  logger.add(lvlWarn, msg, line, col, false, args)

proc warn*(logger: Logger, msg: Message, line, col: int, strFmt: bool, args: varargs[string]) =
  logger.add(lvlWarn, msg, line, col, true, args)

template warnWithArgs*(msg: Message, tk: TokenTuple, args: openarray[string]) =
  if not p.hasErrors:
    p.logger.newWarn(msg, tk.line, tk.pos, true, args)

template error*(msg: Message, tk: TokenTuple) =
  if not p.hasErrors:
    p.logger.newError(msg, tk.line, tk.pos, false)
    p.hasErrors = true
  return # block code execution

template error*(msg: Message, tk: TokenTuple, args: openarray[string]) =
  if not p.hasErrors:
    p.logger.newError(msg, tk.line, tk.pos, false, args)
    p.hasErrors = true
  return # block code execution

template error*(msg: Message, tk: TokenTuple, strFmt: bool,
            extraLines: seq[string], extraLabel: string, args: varargs[string]) =
  if not p.hasErrors:
    newErrorMultiLines(p.logger, msg, tk.line, tk.pos, strFmt, extraLines, extraLabel, args)
    p.hasErrors = true
  return # block code execution

template error*(msg: Message, meta: Meta, args: varargs[string]) =
  if not p.hasErrors:
    p.logger.newError(msg, meta[0], meta[2], true, args)
    p.hasErrors = true
  return # block code execution

template errorWithArgs*(msg: Message, tk: TokenTuple, args: openarray[string]) =
  if not p.hasErrors:
    p.logger.newError(msg, tk.line, tk.pos, true, args)
    p.hasErrors = true
  return # block code execution

template compileErrorWithArgs*(msg: Message, args: openarray[string]) =
  c.logger.newError(msg, node.meta[0], node.meta[1], true, args)
  c.hasErrors = true
  return

template compileErrorWithArgs*(msg: Message, args: openarray[string], meta: Meta) =
  c.logger.newError(msg, meta[0], meta[1], true, args)
  c.hasErrors = true
  return

template compileErrorWithArgs*(msg: Message) =
  c.logger.newError(msg, node.meta[0], node.meta[1], true, [])
  c.hasErrors = true
  return

template compileErrorWithArgs*(msg: Message, meta: Meta, args: openarray[string]) =
  c.logger.newError(msg, meta[0], meta[1], true, args)
  c.hasErrors = true
  return

proc error*(logger: Logger, msg: Message, line, col: int, args: openarray[string]) =
  logger.add(lvlError, msg, line, col, false, args)

when defined napiOrWasm:
  proc runIterator(i: Log, label = ""): string =
    if label.len != 0:
      add result, label
    add result, "(" & $i.line & ":" & $i.col & ")" & spaces(1)
    if i.useFmt:
      var x: int
      var str = split($i.msg, "$")
      let length = count($i.msg, "$") - 1
      for s in str:
        add result, s.strip()
        if length >= x:
          add result, indent(i.args[x], 1)
        inc x
    else:
      add result, $i.msg
      for a in i.args:
        add result, a

  proc `$`*(i: Log): string =
    runIterator(i)

  iterator warnings*(logger: Logger): string =
    for i in logger.warnLogs:
      yield runIterator(i, "Warning")

  iterator errors*(logger: Logger): string =
    for i in logger.errorLogs:
      yield runIterator(i)
      if i.extraLines.len != 0:
        if i.extraLabel.len != 0:
          var extraLabel = "\n"
          add extraLabel, indent(i.extraLabel, 6)
          yield extraLabel
        for extraLine in i.extraLines:
          var extra = "\n"
          add extra, indent(extraLine, 12)
          yield extra

elif compileOption("app", "console"):
  proc runIterator(i: Log, label: string, fgColor: ForegroundColor): Row =
    add result, span(label, fgColor, indentSize = 0)
    add result, span("(" & $i.line & ":" & $i.col & ")")
    if i.useFmt:
      var x: int
      var str = split($i.msg, "$")
      let length = count($i.msg, "$") - 1
      for s in str:
        add result, span(s.strip())
        if length >= x:
          add result, span(i.args[x], fgBlue)
        inc x
    else:
      add result, span($i.msg)
      for a in i.args:
        add result, span(a, fgBlue)

  iterator warnings*(logger: Logger): Row =
    for i in logger.warnLogs:
      yield runIterator(i, "Warning", fgYellow)

  iterator errors*(logger: Logger): Row =
    for i in logger.errorLogs:
      yield runIterator(i, "Error", fgRed)
      if i.extraLines.len != 0:
        if i.extraLabel.len != 0:
          var extraLabel: Row
          extraLabel.add(span(i.extraLabel, indentSize = 6))
          yield extraLabel
        for extraLine in i.extraLines:
          var extra: Row
          extra.add(span(extraLine, indentSize = 12))
          yield extra