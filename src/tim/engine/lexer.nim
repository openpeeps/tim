# 
# High-performance, compiled template engine inspired by Emmet syntax.
# 
# Tim Engine can be used as a Nim library via Nimble,
# or as a binary application for integrating Tim Engine with
# other apps and programming languages.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim

import os, lexbase, streams, json, re
from strutils import Whitespace, `%`, replace, indent, startsWith
import ./tokens

type
    Lexer* = object of BaseLexer
        kind*: TokenKind
        token*, error*: string
        startPos*: int
        whitespaces: int
    TokenTuple* = tuple[kind: TokenKind, value: string, wsno, col, line: int]

const NUMBERS = {'0'..'9'}
const AZaz = {'a'..'z', 'A'..'Z', '_', '-'}

template setError(l: var Lexer; err: string): untyped =
    l.kind = TK_INVALID
    if l.error.len == 0:
        l.error = err
 
proc hasError[T: Lexer](self: T): bool =
    result = self.error.len > 0

proc existsInBuffer[T: Lexer](lex: var T, pos: int, chars:set[char]): bool = 
    lex.buf[pos] in chars

proc hasLetters[T: Lexer](lex: var T, pos: int): bool =
    lex.existsInBuffer(pos, AZaz)

proc hasNumbers[T: Lexer](lex: var T, pos: int): bool =
    lex.existsInBuffer(pos, NUMBERS)

proc init*[T: typedesc[Lexer]](lex: T; fileContents: string): Lexer =
    ## Initialize a new BaseLexer instance with given Stream
    var lex = Lexer()
    lexbase.open(lex, newStringStream(fileContents))
    lex.startPos = 0
    lex.kind = TK_INVALID
    lex.token = ""
    lex.error = ""
    return lex

proc handleNewLine[T: Lexer](lex: var T) =
    ## Handle new lines
    case lex.buf[lex.bufpos]
    of '\c':
        lex.bufpos = lex.handleCR(lex.bufpos)
    of '\n':
        lex.bufpos = lex.handleLF(lex.bufpos)
    else: discard

proc skipToEOL[T: Lexer](lex: var T): int =
    # Get entire buffer starting from given position to the end of line
    while true:
        if lex.buf[lex.bufpos] in NewLines:
            return
        inc lex.bufpos
    return lex.bufpos

proc skip[T: Lexer](lex: var T) =
    ## Procedure for skipping/offset between columns/positions 
    var wsno: int
    while true:
        case lex.buf[lex.bufpos]
        of Whitespace:
            if lex.buf[lex.bufpos] notin NewLines:
                inc lex.bufpos
                inc wsno
            else: lex.handleNewLine()
        else:
            lex.whitespaces = wsno
            break

proc setToken*[T: Lexer](lex: var T, tokenKind: TokenKind, offset = 1) =
    ## Set meta data for current token
    lex.kind = tokenKind
    lex.startPos = lex.getColNumber(lex.bufpos)
    inc(lex.bufpos, offset)

proc setTokenMulti[T: Lexer](lex: var T, tokenKind: TokenKind, offset = 0, multichars = 0) =
    # Set meta data of the current token and jump to the next one
    skip lex
    lex.startPos = lex.getColNumber(lex.bufpos)
    var items = 0
    if multichars != 0:
        while items < multichars:
            add lex.token, lex.buf[lex.bufpos]
            inc lex.bufpos
            inc items
    else:
        add lex.token, lex.buf[lex.bufpos]
        inc lex.bufpos, offset
    lex.kind = tokenKind

proc nextToEOL[T: Lexer](lex: var T): tuple[pos: int, token: string] =
    # Get entire buffer starting from given position to the end of line
    while true:
        case lex.buf[lex.bufpos]:
        of NewLines: return
        of EndOfFile: return
        else: 
            add lex.token, lex.buf[lex.bufpos]
            inc lex.bufpos
    return (pos: lex.bufpos, token: lex.token)

proc next*[T: Lexer](lex: var T, tkChar: char, offset = 1): bool =
    # Determine if the next character is as expected,
    # without modifying the current buffer position
    skip lex
    return lex.buf[lex.bufpos + offset] in {tkChar}

proc next*[T: Lexer](lex: var T, chars:string): bool =
    ## Determine the next characters based on given chars string,
    ## without modifying the current buffer position
    var i = 1
    var status = false
    for c in chars.toSeq():
        status = lex.next(c, i)
        inc i
    return status
 
proc handleSpecial[T: Lexer](lex: var T): char =
    ## Procedure for for handling special escaping tokens
    assert lex.buf[lex.bufpos] == '\\'
    inc lex.bufpos
    case lex.buf[lex.bufpos]
    of 'n':
        lex.token.add "\\n"
        result = '\n'
        inc lex.bufpos
    of '\\':
        lex.token.add "\\\\"
        result = '\\'
        inc lex.bufpos
    else:
        lex.setError("Unknown escape sequence: '\\" & lex.buf[lex.bufpos] & "'")
        result = '\0'
 
proc handleChar[T: Lexer](lex: var T) =
    assert lex.buf[lex.bufpos] == '\''
    lex.startPos = lex.getColNumber(lex.bufpos)
    lex.kind = TK_INVALID
    inc lex.bufpos
    if lex.buf[lex.bufpos] == '\\':
        lex.token = $ord(lex.handleSpecial())
        if lex.hasError(): return
    elif lex.buf[lex.bufpos] == '\'':
        lex.setError("Empty character constant")
        return
    else:
        lex.token = $ord(lex.buf[lex.bufpos])
        inc lex.bufpos
    if lex.buf[lex.bufpos] == '\'':
        lex.kind = TK_INTEGER
        inc lex.bufpos
    else:
        lex.setError("Multi-character constant")
 
proc handleString[T: Lexer](lex: var T) =
    ## Handle string values wrapped in single or double quotes
    lex.startPos = lex.getColNumber(lex.bufpos)
    lex.token = ""
    inc lex.bufpos
    while true:
        case lex.buf[lex.bufpos]
        of '\\':
            discard lex.handleSpecial()
            if lex.hasError(): return
        of '"':
            lex.kind = TK_STRING
            inc lex.bufpos
            break
        of NewLines:
            lex.setError("EOL reached before end of string")
            return
        of EndOfFile:
            lex.setError("EOF reached before end of string")
            return
        else:
            add lex.token, lex.buf[lex.bufpos]
            inc lex.bufpos

proc handleSequence[T: Lexer](lex: var T) =
    lex.startPos = lex.getColNumber(lex.bufpos)
    lex.token = "["
    inc lex.bufpos
    var errorMessage = "$1 reached before closing the array"
    while true:
        case lex.buf[lex.bufpos]
        of '\\':
            discard lex.handleSpecial()
            if lex.hasError(): return
        of NewLines:
            lex.setError(errorMessage % ["EOL"])
            return
        of EndOfFile:
            lex.setError(errorMessage % ["EOF"])
            return
        else:
            add lex.token, lex.buf[lex.bufpos]
            inc lex.bufpos

proc handleNumber[T: Lexer](lex: var T) =
    lex.startPos = lex.getColNumber(lex.bufpos)
    lex.token = "0"
    while lex.buf[lex.bufpos] == '0':
        inc lex.bufpos
    while true:
        case lex.buf[lex.bufpos]
        of '0'..'9':
            if lex.token == "0":
                setLen(lex.token, 0)
            add lex.token, lex.buf[lex.bufpos]
            inc lex.bufpos
        of 'a'..'z', 'A'..'Z', '_':
            lex.setError("Invalid number")
            return
        else:
            lex.setToken(TK_INTEGER)
            break

proc handleVariableIdent[T: Lexer](lex: var T) =
    lex.startPos = lex.getColNumber(lex.bufpos)
    setLen(lex.token, 0)
    inc lex.bufpos
    while true:
        if lex.hasLetters(lex.bufpos):
            add lex.token, lex.buf[lex.bufpos]
            inc lex.bufpos
        elif lex.hasNumbers(lex.bufpos):
            add lex.token, lex.buf[lex.bufpos]
            inc lex.bufpos
        else: break
    lex.setToken(TK_VARIABLE)

proc handleIdent[T: Lexer](lex: var T) =
    lex.startPos = lex.getColNumber(lex.bufpos)
    setLen(lex.token, 0)
    while true:
        if lex.hasLetters(lex.bufpos):
            add lex.token, lex.buf[lex.bufpos]
            inc lex.bufpos
        elif lex.hasNumbers(lex.bufpos):
            add lex.token, lex.buf[lex.bufpos]
            inc lex.bufpos
        else: break
    # skip lex
    if lex.buf[lex.bufpos] == '=':
        lex.kind = TK_IDENTIFIER
    else:
        lex.kind = case lex.token
            of "a": TK_A
            of "abbr": TK_ABBR
            of "acronym": TK_ACRONYM
            of "address": TK_ADDRESS
            of "applet": TK_APPLET
            of "area": TK_AREA
            of "article": TK_ARTICLE
            of "aside": TK_ASIDE
            of "b": TK_B
            of "base": TK_BASE
            of "basefont": TK_BASEFONT
            of "bdi": TK_BDI
            of "bdo": TK_BDO
            of "big": TK_BIG
            of "blockquote": TK_BLOCKQUOTE
            of "body": TK_BODY
            of "br": TK_BR
            of "button": TK_BUTTON
            of "canvas": TK_CANVAS
            of "caption": TK_CAPTION
            of "center": TK_CENTER
            of "cite": TK_CITE
            of "code": TK_CODE
            of "col": TK_COL
            of "colgroup": TK_COLGROUP
            of "data": TK_DATA
            of "datalist": TK_DATALIST
            of "dd": TK_DD
            of "del": TK_DEL
            of "details": TK_DETAILS
            of "dfn": TK_DFN
            of "dialog": TK_DIALOG
            of "dir": TK_DIR
            of "div": TK_DIV
            of "dl": TK_DL
            of "dt": TK_DT
            of "em": TK_EM
            of "embed": TK_EMBED
            of "fieldset": TK_FIELDSET
            of "figcaption": TK_FIGCAPTION
            of "figure": TK_FIGURE
            of "font": TK_FONT
            of "footer": TK_FOOTER
            of "form": TK_FORM
            of "frame": TK_FRAME
            of "frameset": TK_FRAMESET
            of "false": TK_VALUE_BOOL
            of "for": TK_FOR
            of "h1": TK_H1
            of "h2": TK_h2
            of "h3": TK_H3
            of "h4": TK_H4
            of "h5": TK_h5
            of "h6": TK_h6
            of "head": TK_HEAD
            of "header": TK_HEADER
            of "hr": TK_HR
            of "html": TK_HTML
            of "i": TK_I
            of "iframe": TK_IFRAME
            of "img": TK_IMG
            of "input": TK_INPUT
            of "in": TK_IN
            of "if": TK_IF
            of "ins": TK_INS
            of "kbd": TK_KBD
            of "label": TK_LABEl
            of "legend": TK_LEGEND
            of "li": TK_LI
            of "link": TK_LINK
            of "main": TK_MAIN
            of "map": TK_MAP
            of "mark": TK_MARK
            of "meta": TK_META
            of "meter": TK_METER
            of "nav": TK_NAV
            of "noframes": TK_NOFRAMES
            of "noscript": TK_NOSCRIPT
            of "object": TK_OBJECT
            of "ol": TK_OL
            of "optgroup": TK_OPTGROUP
            of "option": TK_OPTION
            of "output": TK_OUTPUT
            of "p": TK_P
            of "param": TK_PARAM
            of "pre": TK_PRE
            of "progress": TK_PROGRESS
            of "q": TK_Q
            of "rp": TK_RP
            of "rt": TK_RT
            of "ruby": TK_RUBY
            of "s": TK_S
            of "samp": TK_SAMP
            of "script": TK_SCRIPT
            of "section": TK_SECTION
            of "select": TK_SELECT
            of "small": TK_SMALL
            of "source": TK_SOURCE
            of "span": TK_SPAN
            of "strike": TK_STRIKE
            of "strong": TK_STRONG
            of "style": TK_STYLE
            of "sub": TK_SUB
            of "summary": TK_SUMMARY
            of "sup": TK_SUP
            of "svg": TK_SVG
            of "table": TK_TABLE
            of "tbody": TK_TBODY
            of "td": TK_TD
            of "template": TK_TEMPLATE
            of "tfoot": TK_TFOOT
            of "th": TK_TH
            of "thead": TK_THEAD
            of "time": TK_TIME
            of "title": TK_TITLE
            of "tr": TK_TR
            of "true": TK_VALUE_BOOL
            of "track": TK_TRACK
            of "tt": TK_TT
            of "u": TK_U
            of "var": TK_VAR
            of "video": TK_VIDEO
            of "wbr": TK_WBR
            else: TK_IDENTIFIER

proc getToken*[T: Lexer](lex: var T): TokenTuple =
    ## Parsing through available tokens
    lex.kind = TK_INVALID
    setLen(lex.token, 0)
    skip lex
    case lex.buf[lex.bufpos]
    of EndOfFile:
        lex.startPos = lex.getColNumber(lex.bufpos)
        lex.kind = TK_EOF
    of '/':
        if lex.next('/'):
            lex.setTokenMulti(TK_COMMENT, 2, lex.nextToEOL.pos)
    of '.':
        lex.setToken(TK_ATTR_CLASS, 1)
    of '#':
        lex.setToken(TK_ATTR_ID, 1)
    of '!':
        if lex.next('='): lex.setTokenMulti(TK_NEQ, 2, 2)
    of '=':
        if lex.next('='): lex.setTokenMulti(TK_EQ, 2, 2)
        else: lex.setToken(TK_ASSIGN, 1)
    of ':':
        lex.setToken(TK_COLON, 1)
    of '>':
        lex.setToken(TK_NEST_OP, 1)
    of '$': lex.handleVariableIdent()
    of '0'..'9': lex.handleNumber()
    of 'a'..'z', 'A'..'Z', '_', '-': lex.handleIdent()
    of '"', '\'': lex.handleString()
    else: discard
    
    if lex.kind == TK_INVALID:
        lex.setError("Unrecognized character")
    elif lex.kind == TK_COMMENT:
        return lex.getToken()
    result = (kind: lex.kind, value: lex.token, wsno: lex.whitespaces, col: lex.startPos, line: lex.lineNumber)