# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

from ./tokens import TokenTuple
from ./ast import Meta

import std/[sequtils, json, strutils]

when compileOption("app", "console"):
  import pkg/kapsis/cli

type
  Message* = enum
    invalidIndentation = "Invalid indentation [InvalidIndentation]"
    unexpectedToken = "Unexpected token $ [UnexpectedToken]"
    undeclaredIdentifier = "Undeclared identifier $ [UndeclaredIdentifier]"
    invalidAccessorStorage = "Invalid accessor storage $ for $ [InvalidAccessorStorage]"
    identRedefine = "Attempt to redefine variable $ [IdentRedefine]"
    varImmutable = "Attempt to reassign value to immutable constant $ [VarImmutable]"
    typeMismatchMutable = "Type mismatch. Got $ expected a mutable $  [TypeMismatchMutable]"
    fnUndeclared = "Undeclared function $ [UndeclaredFunction]"
    fnReturnMissingCommand = "Expression $ is of type $ and has to be used or discarded [UseOrDiscard]"
    fnReturnVoid = "Function $ has no return type [VoidFunction]"
    fnExtraArg = "Extra arguments given. Got $ expected $ [ExtraArgs]"
    unimplementedForwardDeclaration = "Unimplemented forward declaration $ [UnimplementedForwardDeclaration]"
    badIndentation = "Nestable statement requires indentation [BadIndentation]"
    invalidContext = "Invalid $ in this context [InvalidContext]"
    invalidViewLoader = "Invalid use of `@view` in this context. Use a layout instead [InvalidViewLoader]"
    duplicateViewLoader = "Duplicate `@view` loader [DuplicateViewLoaded]"
    typeMismatch = "Type mismatch. Got $ expected $ [TypeMismatch]"
    typeMismatchObject = "Type mismatch. Expected an instance of $ [TypeMismatch]"
    duplicateAttribute = "Duplicate HTML attribute $ [DuplicateAttribute]"
    duplicateField = "Duplicate field $ [DuplicateField]"
    undeclaredField = "Undeclared field $ [UndeclaredField]"
    invalidIterator = "Invalid iterator [InvalidIterator]"
    indexDefect = "Index $ not in $ [IndexDefect]"
    importError = "Cannot open file: $ [ImportError]"
    importCircularError = "Circular import detected: $ [CircularImport]"
    invalidComponentName = "Invalid component name $ [InvalidComponentName]"
    assertionFailed = "Assertion failed"
    eof = "EOF reached before closing $ [EOF]"
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

else:
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

  proc runIteratorStr(i: Log, label = ""): JsonNode =
    result = newJObject()
    result["line"] = newJInt(i.line)
    result["col"] = newJInt(i.col)
    result["code"] = newJInt(i.msg.ord)
    if i.useFmt:
      var x: int
      var str = split($i.msg, "$")
      let length = count($i.msg, "$") - 1
      var msg: string
      for s in str:
        add msg, s
        if length >= x:
          add msg, i.args[x]
        inc x
      result["msg"] = newJString(msg)
    else:
      var str = $i.msg
      for a in i.args:
        add str, a
      result["msg"] = newJString(str)

  # iterator warningsStr*(logger: Logger): string =
  #   for i in logger.warnLogs:
  #     yield runIteratorStr(i, "Warning")

  iterator errorsStr*(logger: Logger): JsonNode =
    for i in logger.errorLogs:
      yield runIteratorStr(i)
      # if i.extraLines.len != 0:
      #   if i.extraLabel.len != 0:
      #     var extraLabel = "\n"
      #     add extraLabel, indent(i.extraLabel, 6)
      #     yield extraLabel
      #   for extraLine in i.extraLines:
      #     var extra = "\n"
      #     add extra, indent(extraLine, 12)
      #     yield extra