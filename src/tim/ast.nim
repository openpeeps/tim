# ⚡️ High-performance compiled
# template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim

from std/strutils import toUpperAscii
from std/enumutils import symbolName, symbolRank
from ./lexer import TokenTuple
from ./tokens import TokenKind

type
    HtmlNodeType = enum
        HtmlDoctype
        HtmlDiv
        HtmlA
        HtmlAbbr
        HtmlAcronym
        HtmlAddress
        HtmlApplet
        HtmlArea
        HtmlArticle
        HtmlAside
        HtmlAudio
        HtmlB
        HtmlBase
        HtmlBasefont
        HtmlBdi
        HtmlBdo

        HtmlSection

    HtmlAttribute* = object
        name*: string
        value*: string

    IDAttribute* = ref object
        value*: string

    HtmlNode* = ref object
        nodeType*: HtmlNodeType
        nodeName*: string
        id*: IDAttribute
        attributes*: seq[HtmlAttribute]
        nodes*: seq[HtmlNode]

proc isEmptyAttribute*[T: HtmlAttribute](attr: var T): bool = attr.name.len == 0 and attr.value.len == 0
proc isEmptyAttribute*[T: IDAttribute](attr: var T): bool = attr.value.len == 0

proc getSymbolName*[T: HtmlNodeType](nodeType: T): string =
    ## Get the stringified symbol name of the given HtmlNodeType
    var nodeName = nodeType.symbolName
    return toUpperAscii(nodeName[4 .. ^1])

proc getHtmlNodeType*[T: TokenTuple](token: T): HtmlNodeType = 
    result = case token.kind:
    of TK_DOCTYPE: HtmlDoctype
    of TK_A: HtmlA
    of TK_ABBR: HtmlAbbr
    of TK_ACRONYM: HtmlAcronym
    of TK_ADDRESS: HtmlAddress
    of TK_APPLET: HtmlApplet
    of TK_AREA: HtmlArea
    of TK_ARTICLE: HtmlArticle
    of TK_ASIDE: HtmlAside
    of TK_AUDIO: HtmlAudio
    of TK_B: HtmlB
    of TK_BASE: HtmlBase
    of TK_BASEFONT: HtmlBasefont
    of TK_BDI: HtmlBdi
    of TK_BDO: HtmlBdo
    of TK_DIV: HtmlDiv
    of TK_SECTION: HtmlSection
    else: HtmlDiv