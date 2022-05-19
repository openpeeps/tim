# A High-performance, compiled template engine
# inspired by Emmmet Syntax.
# 
# Tim Engine can be used as a Nim Library via Nimble
# or as a binary application for language agnostic
# projects.
# 
#       (c) 2022 George Lemon | Released under MIT License
#       Made by Humans from OpenPeep
#       https://github.com/openpeep/tim

import toktok

# TODO replace internal lexer with TokTok
# https://github.com/openpeep/toktok

tokens:
    Tk_A            > 'a'
    Tk_Abbr         > "abbr"
    Tk_Acronym      > "acronym"
    Tk_Address      > "address"
    Tk_Applet       > "applet"
    Tk_Area         > "area"
    Tk_Article      > "article"
    Tk_Aside        > "aside"
    Tk_Audio        > "audio"
    Tk_B            > 'b'
    Tk_Base         > "base"
    Tk_Basefont     > "basefont"
    Tk_Bdi          > "bdi"
    Tk_Bdo          > "bdo"
    Tk_Big          > "big"
    Tk_Blockquote   > "blockquote"
    Tk_Body         > "body"
    Tk_Br           > "br"
    Tk_Button       > "button"
    Tk_Comment      > "//" .. EOL
    Tk_Canvas       > "canvas"
    Tk_Caption      > "caption"
    Tk_Center       > "center"
    Tk_Cite         > "cite"
    Tk_Code         > "code"
    Tk_Col          > "col"
    Tk_Colgroup     > "colgroup"
    Tk_Data         > "data"
    Tk_Datalist     > "datalist"
    Tk_DD           > "dd"
    Tk_Del          > "del"
    Tk_Details      > "details"
    Tk_DFN          > "dfn"
    TK_Dialog       > "dialog"
    Tk_Dir          > "dir"
    Tk_Div          > "div"
    Tk_Docktype     > "doctype"
    Tk_DL           > "dl"
    Tk_DT           > "dt"
    Tk_EM           > "em"
    Tk_Embed        > "embed"
    TK_Fieldset     > "fieldset"
    Tk_Figcaption   > "figcaption"
    TK_Figure       > "figure"
    Tk_Font         > "font"
    Tk_Footer       > "footer"
    Tk_Form         > "form"
