# A high-performance compiled template engine
# inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import toktok

static:
  Program.settings(true, "TK_")

handlers:
  proc handleVarFmt*(lex: var Lexer, kind: TokenKind) =
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
    lex.setToken kind

  proc handleCalls*(lex: var Lexer, kind: TokenKind) =
    lex.startPos = lex.getColNumber(lex.bufpos)
    setLen(lex.token, 0)
    if lex.next("include"):
      lex.setToken TK_INCLUDE, 8
      lex.token = "include"
    elif lex.next("view"):
      lex.setToken TK_VIEW, 5
      lex.token = "view"
    else:
      inc lex.bufpos
      setLen(lex.token, 0)
      while true:
        if lex.hasLetters(lex.bufpos) or lex.hasNumbers(lex.bufpos):
          add lex.token, lex.buf[lex.bufpos]
          inc lex.bufpos
        else:
          dec lex.bufpos
          break
      lex.setToken TK_CALL

  proc handleSnippets*(lex: var Lexer, kind: TokenKind) =    
    lex.startPos = lex.getColNumber(lex.bufpos)
    var k = TK_JS
    if lex.next("``javascript"):
      setLen(lex.token, 0)
      inc lex.bufpos, 13
    elif lex.next("``sass"):
      setLen(lex.token, 0)
      inc lex.bufpos, 7
      k = TK_SASS
    elif lex.next("``yaml"):
      setLen(lex.token, 0)
      inc lex.bufpos, 7
      k = TK_YAML
    elif lex.next("``json"):
      setLen(lex.token, 0)
      inc lex.bufpos, 7
      k = TK_JSON
    else:
      lex.setError("Unknown snippet. Tim knows about `js`|`javascript` or `sass`")
      return
    while true:
      case lex.buf[lex.bufpos]
      of '`':
        if lex.next("``"):
          lex.kind = k
          inc lex.bufpos, 3
          break
        else:
          add lex.token, lex.buf[lex.bufpos]
          inc lex.bufpos
      of EndOfFile:
        lex.setError("EOF reached before end of snippet")
        return
      else:
        add lex.token, lex.buf[lex.bufpos]
        inc lex.bufpos

tokens:
  A            > "a"
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
  Divide       > '/':
    Comment  > '/' .. EOL
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
  # 
  # SVG Support
  # 
  SVG                  > "svg"
  SVG_Animate          > "animate"
  SVG_AnimateMotion    > "animateMotion"
  SVG_AnimateTransform > "animateTransform"
  SVG_Circle           > "circle"
  SVG_ClipPath         > "clipPath"
  SVG_Defs             > "defs"
  SVG_Desc             > "desc"
  SVG_Discard          > "discard"
  SVG_Ellipse          > "ellipse"
  SVG_Fe_Blend         > "feBlend"
  SVG_Fe_ColorMatrix   > "feColorMatrix"
  SVG_Fe_ComponentTransfer    > "feComponentTransfer"
  SVG_Fe_Composite            > "feComposite"
  SVG_Fe_ConvolveMatrix       > "feConvolveMatrix"
  SVG_Fe_DiffuseLighting      > "feDiffuseLighting"
  SVG_Fe_DisplacementMap      > "feDisplacementMap"
  SVG_Fe_DistantLight         > "feDistantLight"
  SVG_Fe_DropShadow           > "feDropShadow"
  SVG_Fe_Flood                > "feFlood"
  SVG_Fe_FuncA                > "feFuncA"
  SVG_Fe_FuncB                > "feFuncB"
  SVG_Fe_FuncG                > "feFuncG"
  SVG_Fe_FuncR                > "feFuncR"
  SVG_Fe_GaussianBlur         > "feGaussianBlur"
  SVG_Fe_Image                > "feImage"
  SVG_Fe_Merge                > "feMerge"
  SVG_Fe_Morphology           > "feMorphology"
  SVG_Fe_Offset               > "feOffset"
  SVG_Fe_PointLight           > "fePointLight"
  SVG_Fe_SpecularLighting     > "feSpecularLighting"
  SVG_Fe_SpotLight            > "feSpotLight"
  SVG_Fe_Title                > "feTitle"
  SVG_Fe_Turbulence           > "feTurbulence"
  SVG_Filter                  > "filter"
  SVG_foreignObject           > "foreignObject"
  SVG_G                       > "g"
  SVG_Hatch                   > "hatch"
  SVG_HatchPath               > "hatchpath"
  SVG_Image                   > "image"
  SVG_Line                    > "line"
  SVG_LinearGradient          > "linearGradient"
  SVG_Marker                  > "marker"
  SVG_Mask                    > "mask"
  SVG_Metadata                > "metadata"
  SVG_Mpath                   > "mpath"
  SVG_Path                    > "path"
  SVG_Pattern                 > "pattern"
  SVG_Polygon                 > "polygon"
  SVG_Polyline                > "polyline"
  SVG_RadialGradient          > "radialGradient"
  SVG_Rect                    > "rect"
  SVG_Set                     > "set"
  SVG_Stop                    > "stop"
  SVG_Switch                  > "switch"
  SVG_Symbol                  > "symbol"
  SVG_Text                    > "text"
  SVG_TextPath                > "textpath"
  SVG_TSpan                   > "tspan"
  SVG_Use                     > "use"
  SVG_View                    > "view"

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
  Attr                        # a TK_IDENTIFIER followed by `=` becomes TK_ATTR
  JS
  SASS
  YAML
  JSON
  Snippet           > tokenize(handleSnippets, '`')
  LCurly       > '{'
  RCurly       > '}'
  LPar         > '('
  RPar         > ')'
  LBra         > '['
  RBra         > ']'
  Dot          > '.'
  ID           > '#'
  Assign       > '=':
    EQ       ? '='
  Colon        > ':'
  Comma        > ','
  GT           > '>':
    GTE      ? '='
  LT           > '<':
    LTE      ? '='
  AMP          > '&'
  Variable          > tokenize(handleCustomIdent, '$')
  Safe_Variable     > tokenize(handleCustomIdent, '%')
  If           > "if"
  Elif         > "elif"
  Else         > "else"
  SIf          > '?'      # short hand `if` statement
  SElse        > '|'      # short hand `else` statement
  And          > "and"
  For          > "for"
  In           > "in"
  Or           > "or"
  Bool_True    > "true"
  Bool_False   > "false"
  Not          > '!':
    NEQ      ? '='
  At           > tokenize(handleCalls, '@')
  Include
  View
  StartsWith
  EndsWith
  Mixin
  Call
  # At           > '@':
  #   Include  ? "include"
  #   Mixin    ? "mixin"
  #   View     ? "view"
  #   StartsWith > "startsWith"
  #   EndsWith   > "endsWith"
  #   Contaisn   > "contains"
  PLUS         > '+'
  MINUS        > '-'
  MULTI        > '*'
  Defer        > "defer"
  Type_Bool         > "bool"
  Type_Int          > "int"
  Type_String       > "string"
  None

#export TokenTuple, TokenKind