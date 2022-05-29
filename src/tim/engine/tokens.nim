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

tokens:
    A_Link       > "a"
    Abbr         > "abbr"
    Acronym      > "acronym"
    Address      > "address"
    Applet       > "applet"
    Area         > "area"
    Article      > "article"
    Aside        > "aside"
    Audio        > "audio"
    Bold         > "b"
    Base         > "base"
    Basefont     > "basefont"
    Bdi          > "bdi"
    Bdo          > "bdo"
    Big          > "big"
    Blockquote   > "blockquote"
    Body         > "body"
    Br           > "br"
    Button       > "button"
    Comment      > '/' .. EOL  # TODO TokTok: Handle strings like "//" .. EOL
    Canvas       > "canvas"
    Caption      > "caption"
    Center       > "center"
    Cite         > "cite"
    Code         > "code"
    Col          > "col"
    Colgroup     > "colgroup"
    Data         > "data"
    Datalist     > "datalist"
    DD           > "dd"
    Del          > "del"
    Details      > "details"
    DFN          > "dfn"
    Dialog       > "dialog"
    Dir          > "dir"
    Div          > "div"
    Doctype      > "doctype"
    DL           > "dl"
    DT           > "dt"
    EM           > "em"
    Embed        > "embed"
    Fieldset     > "fieldset"
    Figcaption   > "figcaption"
    Figure       > "figure"
    Font         > "font"
    Footer       > "footer"
    Form         > "form"
    Frame        > "frame"
    Frameset     > "frameset"
    H1           > "h1"
    H2           > "h2"
    H3           > "h3"
    H4           > "h4"
    H5           > "h5"
    H6           > "h6"
    Head         > "head"
    Header       > "header"
    Hr           > "hr"
    Html         > "html"
    Italic       > "i"
    Iframe       > "iframe"
    Img          > "img"
    Input        > "input"
    Ins          > "ins"
    Kbd          > "kbd"
    Label        > "label"
    Legend       > "legend"
    Li           > "li"
    Link         > "link"
    Main         > "main"
    Map          > "map"
    Mark         > "mark"
    Meta         > "meta"
    Meter        > "meter"
    Nav          > "nav"
    Noframes     > "noframes"
    Noscript     > "noscript"
    Object       > "object"
    Ol           > "ol"
    Optgroup     > "optgroup"
    Option       > "option"
    Output       > "output"
    Paragraph    > "p"
    Param        > "param"
    Pre          > "pre"
    Progress     > "progress"
    Quotation    > "q"
    RP           > "rp"
    RT           > "rt"
    Ruby         > "ruby"
    Strike       > "s"
    Samp         > "samp"
    Script       > "script"
    Section      > "section"
    Select       > "select"
    Small        > "small"
    Source       > "source"
    Span         > "span"
    Strike_Long  > "strike"
    Strong       > "strong"
    Style        > "style"
    Sub          > "sub"
    Summary      > "summary"
    Sup          > "sup"
    SVG          > "svg"
    Table        > "table"
    Tbody        > "tbody"
    TD           > "td"
    Template     > "template"
    Textarea     > "textarea"
    Tfoot        > "tfoot"
    TH           > "th"
    Thead        > "thead"
    Time         > "time"
    Title        > "title"
    TR           > "tr"
    Track        > "track"
    TT           > "tt"
    Underline    > "u"  
    UL           > "ul"
    Var          > "var"
    Video        > "video"
    WBR          > "wbr"
    Attr
    Attr_Class   > '.'
    Attr_ID      > '#'
    Assign       > '='
    Colon        > ':' 
    Nest_OP      > '>'
    And          > '&'
    Variable     > identWith('$')
    If           > "if"
    Elif         > "elif"
    Else         > "else"
    For          > "for"
    In           > "in"
    Or           > "or"
    Eq           > ('=', '=')
    Neq          > ('!', '=')
    Include       > ('@', "include")
    None

export TokenTuple, TokenKind