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
    HtmlNodeType* = enum
        HtmlDoctype
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
        HtmlBig
        HtmlBlockquote
        HtmlBody
        HtmlBr
        HtmlButton
        HtmlCanvas
        HtmlCaption
        HtmlCenter
        HtmlCite
        HtmlCode
        HtmlCol
        HtmlColgroup
        HtmlData
        HtmlDatalist
        HtmlDd
        HtmlDel
        HtmlDetails
        HtmlDfn
        HtmlDialog
        HtmlDir
        HtmlDiv
        HtmlDl
        HtmlDt
        HtmlEm
        HtmlEmbed
        HtmlFieldset
        HtmlFigcaption
        HtmlFigure
        HtmlFont
        HtmlFooter
        HtmlForm
        HtmlFrame
        HtmlFrameset
        HtmlH1
        HtmlH2
        HtmlH3
        HtmlH4
        HtmlH5
        HtmlH6
        HtmlHead
        HtmlHr
        HtmlHtml
        HtmlI
        HtmlIframe
        HtmlImg
        HtmlInput
        HtmlIns
        HtmlKbd
        HtmlLabel
        HtmlLegend
        HtmlLi
        HtmlLink
        HtmlMain
        HtmlMap
        HtmlMark
        HtmlMeta
        HtmlMeter
        HtmlNav
        HtmlNoframes
        HtmlNoscript
        HtmlObject
        HtmlOl
        HtmlOptgroup
        HtmlOption
        HtmlOutput
        HtmlP
        HtmlParam
        HtmlPre
        HtmlProgress
        HtmlQ
        HtmlRp
        HtmlRT
        HtmlRuby
        HtmlS
        HtmlSamp
        HtmlScript
        HtmlSection
        HtmlSelect
        HtmlSmall
        HtmlSource
        HtmlSpan
        HtmlStrike
        HtmlStrong
        HtmlStyle
        HtmlSub
        HtmlSummary
        HtmlSup
        HtmlSvg
        HtmlText
        HtmlTable
        HtmlTbody
        HtmlTd
        HtmlTemplate
        HtmlTfoot
        HtmlTh
        HtmlThead
        HtmlTime
        HtmlTitle
        HtmlTr
        HtmlTrack
        HtmlTt
        HtmlU
        HtmlVar
        HtmlVideo
        HtmlWbr

    HtmlAttribute* = object
        name*: string
        value*: string

    IDAttribute* = ref object
        value*: string

    MetaNode* = tuple[column, indent, line: int]

    HtmlNode* = ref object
        case nodeType*: HtmlNodeType
        of HtmlText:
            text*: string
        else: nil
        nodeName*: string
        id*: IDAttribute
        attributes*: seq[HtmlAttribute]
        nodes*: seq[HtmlNode]
        meta*: MetaNode

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
    of TK_BIG: HtmlBig
    of TK_BLOCKQUOTE: HtmlBlockquote
    of TK_BODY: HtmlBody
    of TK_BR: HtmlBr
    of TK_BUTTON: HtmlButton
    of TK_CANVAS: HtmlCanvas
    of TK_CAPTION: HtmlCaption
    of TK_CENTER: HtmlCenter
    of TK_CITE: HtmlCite
    of TK_CODE: HtmlCode
    of TK_COL: HtmlCol
    of TK_COLGROUP: HtmlColgroup
    of TK_DATA: HtmlData
    of TK_DATALIST: HtmlDatalist
    of TK_DD: HtmlDd
    of TK_DEL: HtmlDel
    of TK_Details: HtmlDetails
    of TK_DFN: HtmlDfn
    of TK_DIALOG: HtmlDialog
    of TK_DIR: HtmlDir
    of TK_DIV: HtmlDiv
    of TK_DL: HtmlDl
    of TK_DT: HtmlDt
    of TK_EM: HtmlEm
    of TK_EMBED: HtmlEmbed
    of TK_FIELDSET: HtmlFieldset
    of TK_FIGCAPTION: HtmlFigcaption
    of TK_FIGURE: HtmlFigure
    of TK_FONT: HtmlFont
    of TK_FOOTER: HtmlFooter
    of TK_FORM: HtmlForm
    of TK_FRAME: HtmlFrame
    of TK_FRAMESET: HtmlFrameset
    of TK_H1: HtmlH1
    of TK_H2: HtmlH2
    of TK_H3: HtmlH3
    of TK_H4: HtmlH4
    of TK_H5: HtmlH5
    of TK_h6: HtmlH6
    of TK_HEAD: HtmlHead
    of TK_HR: HtmlHr
    of TK_HTML: HtmlHtml
    of TK_I: HtmlI
    of TK_IFRAME: HtmlIframe
    of TK_IMG: HtmlImg
    of TK_INPUT: HtmlInput
    of TK_INS: HtmlIns
    of TK_KBD: HtmlKbd
    of TK_LABEL: HtmlLabel
    of TK_LEGEND: HtmlLegend
    of TK_LI: HtmlLi
    of TK_LINK: HtmlLink
    of TK_MAIN: HtmlMain
    of TK_MAP: HtmlMap
    of TK_MARK: HtmlMark
    of TK_META: HtmlMeta
    of TK_METER: HtmlMeter
    of TK_NAV: HtmlNav
    of TK_NOFRAMES: HtmlNoframes
    of TK_NOSCRIPT: HtmlNoscript
    of TK_OBJECT: HtmlObject
    of TK_OL: HtmlOl
    of TK_OPTGROUP: HtmlOptgroup
    of TK_OPTION: HtmlOption
    of TK_OUTPUT: HtmlOutput
    of TK_P: HtmlP
    of TK_PARAM: HtmlParam
    of TK_PRE: HtmlPre
    of TK_PROGRESS: HtmlProgress
    of TK_Q: HtmlQ
    of TK_RP: HtmlRp
    of TK_RT: HtmlRT
    of TK_RUBY: HtmlRuby
    of TK_S: HtmlS
    of TK_SAMP: HtmlSamp
    of TK_SCRIPT: HtmlScript
    of TK_SECTION: HtmlSection
    of TK_STRING: HtmlText
    of TK_SELECT: HtmlSelect
    of TK_SMALL: HtmlSmall
    of TK_SOURCE: HtmlSource
    of TK_SPAN: HtmlSpan
    of TK_STRIKE: HtmlStrike
    of TK_STRONG: HtmlStrong
    of TK_STYLE: HtmlStyle
    of TK_SUB: HtmlSub
    of TK_SUMMARY: HtmlSummary
    of TK_SUP: HtmlSup
    of TK_SVG: HtmlSvg
    of TK_TABLE: HtmlTable
    of TK_TBODY: HtmlTbody
    of TK_TD: HtmlTd
    of TK_TEMPLATE: HtmlTemplate
    of TK_TFOOT: HtmlTfoot
    of TK_TH: HtmlTh
    of TK_THEAD: HtmlThead
    of TK_TIME: HtmlTime
    of TK_TITLE: HtmlTitle
    of TK_TR: HtmlTr
    of TK_TRACK: HtmlTrack
    of TK_TT: HtmlTt
    of TK_U: HtmlU
    of TK_VAR: HtmlVar
    of TK_VIDEO: HtmlVideo
    of TK_WBR: HtmlWbr
    else: HtmlDiv