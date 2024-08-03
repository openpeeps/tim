# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim
import std/oids
import pkg/toktok

handlers:
  proc handleDocBlock(lex: var Lexer, kind: TokenKind) =
    while true:
      case lex.buf[lex.bufpos]
      of '*':
        add lex
        if lex.current == '/':
          add lex
          break
      of NewLines:
        inc lex.lineNumber
        add lex
      of EndOfFile: break
      else: add lex
    lex.kind = kind

  proc handleInlineComment(lex: var Lexer, kind: TokenKind) =
    inc lex.bufpos
    while true:
      case lex.buf[lex.bufpos]:
        of NewLines, EndOfFile: break
        else:
          inc lex.bufpos
    lex.kind = kind

  proc handleVar(lex: var Lexer, kind: TokenKind) =
    lexReady lex
    inc lex.bufpos
    var isSafe: bool
    if lex.current == '$':
      isSafe = true
      inc lex.bufpos
    case lex.buf[lex.bufpos]
    of IdentStartChars:
      add lex
      while true:
        case lex.buf[lex.bufpos]
        of IdentChars:
          add lex
        of Whitespace, EndOfFile:
          break
        else:
          break
    else: discard
    if not isSafe:
      lex.kind = kind
    else:
      lex.kind = tkIdentVarSafe
    if lex.token.len > 255:
      lex.setError("Identifier name is longer than 255 characters")

  proc handleMagics(lex: var Lexer, kind: TokenKind) =
    template collectSnippet(tkind: TokenKind) =
      while true:
        try:
          case lex.buf[lex.bufpos]
          of EndOfFile:
            lex.setError("EOF reached before closing @end")
            return
          of '@':
            if lex.next("end"):
              lex.kind = tkind
              lex.token = lex.token.unindent(pos + 2)
              inc lex.bufpos, 4
              break
            else:
              add lex
          of NewLines:
            add lex.token, "\n"
            lex.handleNewLine()
          else:
            if lex.buf[lex.bufpos] == '%' and lex.next("*"):
              case lex.buf[lex.bufpos + 2]
              of IdentStartChars:
                inc lex.bufpos, 2
                var attr = $(genOid()) & "_"
                add attr, lex.buf[lex.bufpos]
                inc lex.bufpos
                while true:
                  case lex.buf[lex.bufpos]
                  of IdentChars:
                    add attr, lex.buf[lex.bufpos]
                    inc lex.bufpos
                  else:
                    add lex.attr, attr
                    add lex.token, "%*" & attr
                    break
              else: discard
            else: add lex
        except:
          lex.bufpos = lex.handleRefillChar(lex.bufpos)
    lexReady lex
    if lex.next("json"):
      let pos = lex.getColNumber(lex.bufpos)
      inc lex.bufpos, 5
      collectSnippet(tkSnippetJson)
    elif lex.next("js"):
      let pos = lex.getColNumber(lex.bufpos)
      inc lex.bufpos, 3
      collectSnippet(tkSnippetJs)
    elif lex.next("do"):
      let pos = lex.getColNumber(lex.bufpos)
      inc lex.bufpos, 3
      collectSnippet(tkDo)
    elif lex.next("yaml"):
      let pos = lex.getColNumber(lex.bufpos)
      inc lex.bufpos, 5
      collectSnippet(tkSnippetYaml)
    elif lex.next("placeholder"):
      let pos = lex.getColNumber(lex.bufpos)
      inc lex.bufpos, 12
      lex.kind = tkPlaceholder
      lex.token = "@placeholder"
    elif lex.next("include"):
      lex.setToken tkInclude, 8
    elif lex.next("import"):
      lex.setToken tkImport, 7
    elif lex.next("view"):
      lex.setToken tkViewLoader, 5
    elif lex.next("client"):
      lex.setToken tkClient, 7
    elif lex.next("end"):
      lex.setToken tkEnd, 4
    else:
      lex.setToken tkAt, 1

  proc handleBackticks(lex: var Lexer, kind: TokenKind) =
    lex.startPos = lex.getColNumber(lex.bufpos)
    setLen(lex.token, 0)
    let lineno = lex.lineNumber
    inc lex.bufpos
    while true:
      case lex.buf[lex.bufpos]
      of '\\':
        lex.handleSpecial()
        if lex.hasError(): return
      of '`':
        lex.kind = kind
        inc lex.bufpos
        break
      of NewLines:
        if lex.multiLineStr:
          inc lex.bufpos
        else:
          lex.setError("EOL reached before end of string")
          return
      of EndOfFile:
        lex.setError("EOF reached before end of string")
        return
      else:
        add lex.token, lex.buf[lex.bufpos]
        inc lex.bufpos
    if lex.multiLineStr:
      lex.lineNumber = lineno

const toktokSettings =
  toktok.Settings(
    tkPrefix: "tk",
    lexerName: "Lexer",
    lexerTuple: "TokenTuple",
    lexerTokenKind: "TokenKind",
    tkModifier: defaultTokenModifier,      
    useDefaultIdent: true,
    keepUnknown: true,
    keepChar: true,
  )

registerTokens toktokSettings:
  plus = '+'
  minus = '-'
  asterisk = '*'
  divide = '/':
    doc = tokenize(handleDocBlock, '*')
    comment = tokenize(handleInlineComment, '/')
  `mod` = '%'
  caret = '^'
  lc = '{'
  rc = '}'
  lp = '('
  rp = ')'
  lb   = '['
  rb   = ']'
  dot  = '.'
  id   = '#'
  ternary = '?'
  exc = '!':
    ne = '=' 
  assign = '=':
    eq   = '='
  colon  = ':'
  comma  = ','
  gt     = '>':
    gte  = '='
  lt     = '<':
    lte  = '='
  amp    = '&':
    andAnd = '&'
  pipe = '|':
    orOr = '|'
  backtick = tokenize(handleBackticks, '`')
  `case` = "case"
  `of`   = "of"
  `if`   = "if"
  `elif` = "elif"
  `else` = "else"
  `and`  = "and"
  `for`  = "for"
  `while` = "while"
  `in`   = "in"
  `or`   = "or"
  `bool` = ["true", "false"]

  # literals
  litBool = "bool"
  litInt = "int"
  litString = "string"
  litFloat = "float"
  litObject = "object"
  litArray = "array"
  litFunction = "function"
  litVoid = "void"
  
  # magics
  at = tokenize(handleMagics, '@')
  `import`
  snippetJs
  snippetYaml
  snippetJson
  placeholder
  viewLoader
  client
  `end`
  `include`
  `do` = "do"
  fn = "fn"
  `func` = "func" # alias `fn`
  `block` = "block"
  component = "component"
  `var` = "var"
  `const` = "const"
  returnCmd = "return"
  echoCmd = "echo"
  discardCmd = "discard"
  breakCmd = "break"
  identVar = tokenize(handleVar, '$')
  identVarSafe