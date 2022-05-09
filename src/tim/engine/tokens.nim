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

type
    TokenKind* = enum
        TK_NONE
        TK_COMMENT          # //
        TK_DOCTYPE
        TK_A
        TK_ABBR
        TK_ACRONYM
        TK_ADDRESS
        TK_APPLET
        TK_AREA
        TK_ARTICLE
        TK_ASIDE
        TK_AUDIO
        TK_B
        TK_BASE
        TK_BASEFONT
        TK_BDI
        TK_BDO
        TK_BIG
        TK_BLOCKQUOTE
        TK_BODY
        TK_BR
        TK_BUTTON
        TK_CANVAS
        TK_CAPTION
        TK_CENTER
        TK_CITE
        TK_CODE
        TK_COL
        TK_COLGROUP
        TK_DATA
        TK_DATALIST
        TK_DD
        TK_DEL
        TK_DETAILS
        TK_DFN
        TK_DIALOG
        TK_DIR
        TK_DIV
        TK_DL
        TK_DT
        TK_EM
        TK_EMBED
        TK_FIELDSET
        TK_FIGCAPTION
        TK_FIGURE
        TK_FONT
        TK_FOOTER
        TK_FORM
        TK_FRAME
        TK_FRAMESET
        TK_H1
        TK_H2
        TK_H3
        TK_H4
        TK_H5
        TK_H6
        TK_HEAD
        TK_HEADER
        TK_HR
        TK_HTML
        TK_I
        TK_IFRAME
        TK_IMG
        TK_INPUT
        TK_INS
        TK_KBD
        TK_LABEL
        TK_LEGEND
        TK_LI
        TK_LINK
        TK_MAIN
        TK_MAP
        TK_MARK
        TK_META
        TK_METER
        TK_NAV
        TK_NOFRAMES
        TK_NOSCRIPT
        TK_OBJECT
        TK_OL
        TK_OPTGROUP
        TK_OPTION
        TK_OUTPUT
        TK_P
        TK_PARAM
        TK_PRE
        TK_PROGRESS
        TK_Q
        TK_RP
        TK_RT
        TK_RUBY
        TK_S
        TK_SAMP
        TK_SCRIPT
        TK_SECTION
        TK_SELECT
        TK_SMALL
        TK_SOURCE
        TK_SPAN
        TK_STRIKE
        TK_STRONG
        TK_STYLE
        TK_SUB
        TK_SUMMARY
        TK_SUP
        TK_SVG
        TK_TABLE
        TK_TBODY
        TK_TD
        TK_TEMPLATE
        TK_TEXTAREA
        TK_TFOOT
        TK_TH
        TK_THEAD
        TK_TIME
        TK_TITLE
        TK_TR
        TK_TRACK
        TK_TT
        TK_U
        TK_UL
        TK_VAR
        TK_VIDEO
        TK_WBR

        TK_ATTR
        TK_ATTR_CLASS   # .
        TK_ATTR_ID      # #
        TK_ASSIGN       # =
        TK_COLON        # :
        TK_INTEGER      # 0-9
        TK_STRING       # `"`..`"`
        TK_NEST_OP      # >
        TK_IDENTIFIER
        TK_VARIABLE     # $[az_AZ_09]
        TK_IF           # if
        TK_ELIF         # elif
        TK_ELSE         # else
        TK_FOR          # for
        TK_IN           # in
        TK_OR           # or
        TK_EQ           # ==
        TK_NEQ          # !=
        TK_VALUE_BOOL
        TK_VALUE_FLOAT
        TK_VALUE_INT
        TK_VALUE_JSON
        TK_VALUE_NIL
        TK_VALUE_STRING
        TK_INVALID
        TK_EOF          # end of file
