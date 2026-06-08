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

type JsState = enum
  jsNormal, jsSQuote, jsDQuote, jsTemplate, jsRegex,
  jsLineComment, jsBlockComment

proc minifyInlineJs*(js: sink string): owned string =
  ## Minify a chunk of JavaScript code by removing comments and unnecessary
  ## whitespace, while preserving string literals, template literals, and regexes.
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

const rawTags = ["pre", "code", "textarea", "script", "style"]

proc minifyRawHtml*(code: sink string, res: var string) =
  ## Minify raw HTML by collapsing whitespace and removing comments,
  ## while preserving content inside certain "raw" tags like <pre>, <code>, <textarea>, <script>, and <style>.
  var
    i = 0
    pendingWs = false
    prevSig: char = '\0'
    rawTag = ""
    inRaw = false

  template emit(ch: char) =
    res.add(ch)
    if not ch.isSpaceAscii:
      prevSig = ch

  template emitStr(s: string) =
    if s.len == 0: return
    res.add(s)
    var last = s[^1]
    if not last.isSpaceAscii:
      prevSig = last
  
  # parse a tag name from code starting at pos, returns lowercased name and new pos
  proc parseTagName(pos: int): (string, int) =
    var j = pos
    var name = ""
    while j < code.len and isIdentChar(code[j]):
      name.add(code[j].toLowerAscii)
      j += 1
    (name, j)
    
  while i < code.len:
    let c = code[i]
    let n = if i + 1 < code.len: code[i + 1] else: '\0'

    if inRaw:
      # look for closing tag </rawTag>
      if c == '<' and i + 1 < code.len and code[i+1] == '/':
        var j = i + 2
        var name = ""
        while j < code.len and isIdentChar(code[j]):
          name.add(code[j].toLowerAscii)
          j += 1
        if name == rawTag:
          # emit closing tag start and fall into tag parsing to emit full closing tag
          emitStr("</")
          emitStr(name)
          # skip any whitespace until '>'
          while j < code.len and code[j].isSpaceAscii:
            j.inc()
          # copy until '>'
          while j < code.len and code[j] != '>':
            emit(code[j]); j.inc()
          if j < code.len and code[j] == '>':
            emit('>')
            j.inc()
          i = j
          inRaw = false
          rawTag = ""
          pendingWs = false
          continue
        else:
          # not the closing tag, emit '<' and continue
          emit(c); i.inc()
          continue
      else:
        res.add(c)
        i.inc()
        continue

    # not in raw content
    if c == '<':
      # comment?
      if i + 3 < code.len and code[i+1] == '!' and code[i+2] == '-' and code[i+3] == '-':
        # check for conditional or important comments (e.g. <!--[if ...]) preserve them
        let condPos = i + 4
        var preserve = condPos < code.len and code[condPos] == '['
        if preserve:
          # copy whole comment as-is
          var j = i
          while j + 2 < code.len and not (code[j] == '-' and code[j+1] == '-' and code[j+2] == '>'):
            res.add(code[j]); j.inc()
          if j + 2 < code.len:
            res.add('-'); res.add('-'); res.add('>')
            j += 3
          i = j
          prevSig = '>'
          continue
        else:
          # skip comment entirely
          var j = i + 4
          while j + 2 < code.len and not (code[j] == '-' and code[j+1] == '-' and code[j+2] == '>'):
            j.inc()
          if j + 2 < code.len:
            j += 3
          i = j
          pendingWs = false
          continue
      # normal tag start: parse tag name to detect raw tags
      emit('<')
      i.inc()
      # optional leading slash (closing tag) already handled by inRaw branch; here just copy if present
      var closing = false
      if i < code.len and code[i] == '/':
        emit('/') ; closing = true ; i.inc()

      # skip whitespace before tag name
      while i < code.len and code[i].isSpaceAscii:
        i.inc()

      let (tname, after) = parseTagName(i)
      if tname.len > 0:
        emitStr(tname)
        i = after
      # emit rest of opening tag up to '>' taking care of quoted attributes
      var inS = false
      var inD = false
      while i < code.len and code[i] != '>':
        let ch = code[i]
        if ch == '\'' and not inD:
          emit(ch); inS = not inS
        elif ch == '"' and not inS:
          emit(ch); inD = not inD
        else:
          # collapse whitespace inside tag to single space
          if ch.isSpaceAscii:
            # skip all contiguous whitespace and emit single space if appropriate
            var j = i
            while j < code.len and code[j].isSpaceAscii:
              j.inc()
            # don't emit leading space immediately after '<' or '/'
            if res.len > 0 and res[^1] != '<' and res[^1] != '/' and res[^1] != ' ':
              emit(' ')
            i = j - 1
          else:
            emit(ch)
        i.inc()
      if i < code.len and code[i] == '>':
        emit('>')
        i.inc()
      # if this is an opening tag for a raw tag, enter raw mode (but only for non-closing tags)
      if not closing and tname in rawTags:
        rawTag = tname
        inRaw = true
        # for script/style try to minify inner JS/CSS
        if rawTag == "script" or rawTag == "style":
          # collect content until matching closing tag
          var j = i
          var content = ""
          while j < code.len:
            if code[j] == '<' and j + 1 < code.len and code[j+1] == '/':
              var k = j + 2
              var cname = ""
              while k < code.len and isIdentChar(code[k]):
                cname.add(code[k].toLowerAscii); k.inc()
              if cname == rawTag:
                break
            content.add(code[j]); j.inc()
          # minify script content if script
          if content.len > 0:
            if rawTag == "script":
              let min = minifyInlineJs(content)
              res.add(min)
            else:
              # for style just collapse leading/trailing whitespace
              var s = content.strip()
              res.add(s)
          i = j
          # now loop will handle the closing tag in inRaw branch
        continue

    elif c.isSpaceAscii:
      pendingWs = true
      i.inc()
      continue

    else:
      if pendingWs:
        # decide if a space is needed between prevSig and current char
        if needsSpace(prevSig, c):
          emit(' ')
        pendingWs = false
      emit(c)
      i.inc()

proc minifyInlineCSS*(css: sink string): owned string =
  ## Minify a chunk of CSS: strip /* comments */, collapse whitespace,
  ## remove unnecessary spaces around punctuation and drop the last
  ## semicolon before a closing brace.
  type CssState = enum
    cssNormal, cssSQuote, cssDQuote, cssComment, cssUrl, cssUrlSQuote, cssUrlDQuote

  var
    i = 0
    pendingWs = false
    prevSig: char = '\0'
    escape = false
    state = cssNormal

  result = newStringOfCap(css.len)

  template emit(ch: char) =
    result.add(ch)
    if not ch.isSpaceAscii:
      prevSig = ch

  while i < css.len:
    let c = css[i]
    let n = if i + 1 < css.len: css[i + 1] else: '\0'

    case state
    of cssNormal:
      # comments
      if c == '/' and n == '*':
        state = cssComment
        i.inc(2)
        continue
      # strings
      elif c == '\'':
        if pendingWs:
          if needsSpace(prevSig, c): emit(' ')
          pendingWs = false
        emit(c); state = cssSQuote; escape = false; i.inc(); continue
      elif c == '"':
        if pendingWs:
          if needsSpace(prevSig, c): emit(' ')
          pendingWs = false
        emit(c); state = cssDQuote; escape = false; i.inc(); continue

      # detect url( case (case-insensitive)
      elif c.toLowerAscii == 'u' and i + 3 < css.len and
           css[i+1].toLowerAscii == 'r' and css[i+2].toLowerAscii == 'l':
        # emit 'url' and then expect '(' possibly after spaces
        if pendingWs:
          pendingWs = false
        emit('u'); emit('r'); emit('l')
        var j = i + 3
        # skip spaces between url and '('
        while j < css.len and css[j].isSpaceAscii:
          j.inc()
        if j < css.len and css[j] == '(':
          emit('(')
          i = j + 1
          state = cssUrl
          continue
        else:
          i = j
          continue

      # whitespace handling
      elif c.isSpaceAscii:
        pendingWs = true
        i.inc()
        continue

      else:
        # punctuation where we usually remove surrounding spaces
        if c in {':', ';', '{', '}', '(', ')', ',', '>', '+', '~', '='}:
          # drop any emitted trailing space before punctuation
          if result.len > 0 and result[^1].isSpaceAscii:
            result.setLen(result.len - 1)
          # emit punctuation
          emit(c)
          pendingWs = false
          # if closing brace, drop trailing semicolon if present
          if c == '}' and result.len > 0 and result[^2] == ';':
            # remove that semicolon (result[^1] is '}', so check ^2)
            result.setLen(result.len - 2)
            result.add('}')
            prevSig = '}'
          i.inc()
          continue
        else:
          if pendingWs:
            if needsSpace(prevSig, c):
              emit(' ')
            pendingWs = false
          emit(c)
          i.inc()
          continue

    of cssComment:
      # skip until */
      if c == '*' and n == '/':
        state = cssNormal
        i.inc(2)
      else:
        i.inc()

    of cssSQuote:
      emit(c)
      if escape:
        escape = false
      elif c == '\\':
        escape = true
      elif c == '\'':
        state = cssNormal
      i.inc()

    of cssDQuote:
      emit(c)
      if escape:
        escape = false
      elif c == '\\':
        escape = true
      elif c == '"':
        state = cssNormal
      i.inc()

    of cssUrl:
      # inside url(...) copies until matching ')' while honoring quotes
      if c == '\'':
        emit(c); state = cssUrlSQuote; escape = false; i.inc(); continue
      elif c == '"':
        emit(c); state = cssUrlDQuote; escape = false; i.inc(); continue
      elif c == ')':
        # trim trailing whitespace inside url(...) (common minifier behavior)
        while result.len > 0 and result[^1].isSpaceAscii:
          result.setLen(result.len - 1)
        emit(')')
        state = cssNormal
        i.inc()
        continue
      else:
        # emit verbatim (including spaces inside url)
        emit(c)
        i.inc()
        continue

    of cssUrlSQuote:
      emit(c)
      if escape:
        escape = false
      elif c == '\\':
        escape = true
      elif c == '\'':
        state = cssUrl
      i.inc()

    of cssUrlDQuote:
      emit(c)
      if escape:
        escape = false
      elif c == '\\':
        escape = true
      elif c == '"':
        state = cssUrl
      i.inc()

  # final cleanup: remove leading/trailing whitespace
  result = result.strip()