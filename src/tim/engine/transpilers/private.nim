# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim
import std/[macros, strutils, ropes, tables, sequtils, options]
import pkg/vancode/interpreter/[ast, chunk, errors, sym]

type
  GenKind = enum
    gkToplevel
    gkProc
    gkBlockProc
    gkIterator
  
  CodeGen* {.acyclic.} = object
    ## a code generator for a module or proc.
    script: Script              # the script all procs go into
    module: Module              # the global scope
    chunk: Chunk                # the chunk of code we're generating
    case kind: GenKind          # what this generator generates
    of gkToplevel: discard
    of gkProc, gkBlockProc:
      procReturnTy: Sym         # the proc's return type
    of gkIterator:
      iter: Sym                 # the symbol representing the iterator
      iterForBody: Node         # the for loop's body
      iterForVar: Node          # the for loop variable's name
      iterForCtx: Context       # the for loop's context
    counter: uint16

# const
#   utilsJS = staticRead(currentSourcePath().parentDir / "tim.js")
# TODO a mini library that will make it easy for Tim to render
# timl code via javascript at client-side. something like jquery but
# super lightweight and with 2026 flavor

proc initCodeGen*(script: Script, module: Module, chunk: Chunk,
        kind = gkToplevel): CodeGen =
  result = CodeGen(script: script, module: module,
                    chunk: chunk, kind: kind)

template genGuard(body) =
  ## Wraps ``body`` in a "guard" used for code generation. The guard sets the
  ## line information in the target chunk. This is a helper used by {.codegen.}.
  when declared(node):
    let
      oldFile = gen.chunk.file
      oldLn = gen.chunk.ln
      oldCol = gen.chunk.col
    # gen.chunk.file = node.file
    gen.chunk.ln = node.ln
    gen.chunk.col = node.col
  body
  when declared(node):
    gen.chunk.file = oldFile
    gen.chunk.ln = oldLn
    gen.chunk.col = oldCol

macro codegen(theProc: untyped): untyped =
  ## Wrap ``theProc``'s body in a call to ``genGuard``.
  theProc[3][0] = ident"Rope"
  theProc.params.insert(1,
    newIdentDefs(ident"gen", nnkVarTy.newTree(ident"CodeGen")))
  if theProc[^1].kind != nnkEmpty:
    let body = nnkStmtList.newTree(
      newAssignment( ident"result", newCall(ident"rope")),
      theProc[^1]
    )
    theProc[^1] = newCall("genGuard", body)
  result = theProc


proc isIdentChar(c: char): bool =
  c.isAlphaAscii or c.isDigit or c == '_' or c == '$'

proc canStartRegex(prevSig: char, lastWord: string): bool =
  if prevSig == '\0': return true
  if prevSig in {'(', '[', '{', ':', ';', ',', '=', '!', '?', '&', '|', '+', '-', '*', '%', '^', '~', '<', '>'}:
    return true
  if lastWord in ["return", "throw", "case", "delete", "void", "typeof", "instanceof", "in", "new", "else", "do"]:
    return true
  false

proc needsSpace(a, b: char): bool =
  (isIdentChar(a) and isIdentChar(b)) or
  (a == '+' and b == '+') or
  (a == '-' and b == '-')

proc shouldInsertSemi(prevSig, next: char, lastWord: string): bool =
  # Newline after these keywords is ASI-sensitive
  if lastWord in ["return", "throw", "break", "continue", "yield", "await"]:
    return true

  # A token that can end a statement, followed by one that can start another
  let prevCanEnd =
    isIdentChar(prevSig) or prevSig in {'"', '\'', '`', ')', ']', '}'}
  let nextCanStart =
    isIdentChar(next) or next in {'"', '\'', '`', '(', '[', '{'}

  prevCanEnd and nextCanStart

proc minifyInlineJs*(js: string): string =
  type JsState = enum
    jsNormal, jsSQuote, jsDQuote, jsTemplate, jsRegex, jsLineComment, jsBlockComment

  var
    st = jsNormal
    i = 0
    pendingWs = false
    pendingNl = false
    prevSig: char = '\0'
    lastWord = ""
    currWord = ""
    escape = false

  result = newStringOfCap(js.len)

  template emit(ch: char) =
    result.add(ch)
    if not ch.isSpaceAscii:
      prevSig = ch
      if isIdentChar(ch):
        currWord.add(ch)
      else:
        if currWord.len > 0:
          lastWord = currWord
          currWord.setLen(0)

  while i < js.len:
    let c = js[i]
    let n = if i + 1 < js.len: js[i + 1] else: '\0'

    case st
    of jsNormal:
      if c == '/' and n == '/':
        st = jsLineComment
        i += 2
        continue
      elif c == '/' and n == '*':
        st = jsBlockComment
        i += 2
        continue
      elif c.isSpaceAscii:
        if c == '\n' or c == '\r':
          pendingNl = true
          pendingWs = false
        else:
          pendingWs = true
      else:
        if pendingNl:
          if shouldInsertSemi(prevSig, c, lastWord):
            emit(';')
          elif needsSpace(prevSig, c):
            emit(' ')
          pendingNl = false
          pendingWs = false
        elif pendingWs and needsSpace(prevSig, c):
          emit(' ')
          pendingWs = false
        else:
          pendingWs = false

        if c == '\'':
          emit(c); st = jsSQuote
        elif c == '"':
          emit(c); st = jsDQuote
        elif c == '`':
          emit(c); st = jsTemplate
        elif c == '/' and canStartRegex(prevSig, lastWord):
          emit(c); st = jsRegex
        else:
          emit(c)

    of jsLineComment:
      if c == '\n' or c == '\r':
        st = jsNormal
        pendingNl = true

    of jsBlockComment:
      if c == '*' and n == '/':
        st = jsNormal
        pendingWs = true
        i += 1

    of jsSQuote:
      emit(c)
      if escape: escape = false
      elif c == '\\': escape = true
      elif c == '\'': st = jsNormal

    of jsDQuote:
      emit(c)
      if escape: escape = false
      elif c == '\\': escape = true
      elif c == '"': st = jsNormal

    of jsTemplate:
      emit(c)
      if escape: escape = false
      elif c == '\\': escape = true
      elif c == '`': st = jsNormal

    of jsRegex:
      emit(c)
      if escape: escape = false
      elif c == '\\': escape = true
      elif c == '/':
        st = jsNormal
        var j = i + 1
        while j < js.len and js[j].isAlphaAscii:
          emit(js[j])
          j += 1
        i = j - 1

    i += 1
  if currWord.len > 0:
    lastWord = currWord
