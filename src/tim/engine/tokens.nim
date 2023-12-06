# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

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
        of NewLines:
          lex.handleNewLine()
          break
        of EndOfFile: break
        else:
          inc lex.bufpos
    lex.kind = kind

  proc handleVar(lex: var Lexer, kind: TokenKind) =
    lexReady lex
    inc lex.bufpos
    case lex.buf[lex.bufpos]
    of IdentStartChars:
      add lex
      while true:
        case lex.buf[lex.bufpos]
        of IdentChars:
          add lex
        of Whitespace, EndOfFile:
          lex.handleNewLine()
          break
        else:
          break
    else: discard
    lex.kind = kind
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
            add lex
        except:
          lex.bufpos = lex.handleRefillChar(lex.bufpos)
    lexReady lex
    if lex.next("js"):
      let pos = lex.getColNumber(lex.bufpos)
      inc lex.bufpos, 3
      collectSnippet(tkSnippetJS)
    elif lex.next("include"):
      lex.setToken tkInclude, 8
    elif lex.next("view"):
      lex.setToken tkViewLoader, 5
    else: discard


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
  multiply = '*'
  divide = '/':
    doc = tokenize(handleDocBlock, '*')
    comment = tokenize(handleInlineComment, '/')
  `mod` = '%'
  lc = '{'
  rc = '}'
  lp = '('
  rp = ')'
  lb   = '['
  rb   = ']'
  dot  = '.'
  id   = '#'
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
  `if`   = "if"
  `elif` = "elif"
  `else` = "else"
  `and`  = "and"
  `for`  = "for"
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

  # magics
  at = tokenize(handleMagics, '@')
  snippetjs
  viewLoader
  `include`

  fn = "fn"
  `var` = "var"
  `const` = "const"
  returnCmd = "return"
  echoCmd = "echo"
  identVar = tokenize(handleVar, '$')