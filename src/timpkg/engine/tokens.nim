# A blazing fast, cross-platform, multi-language
# template engine and markup language written in Nim.
#
#    Made by Humans from OpenPeeps
#    (c) George Lemon | LGPLv3 License
#    https://github.com/openpeeps/tim

import toktok

handlers:
  proc handleVarFmt(lex: var Lexer, kind: TokenKind) =
    lexReady lex
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

  proc handleCalls(lex: var Lexer, kind: TokenKind) =
    template collectSnippet(tkind: TokenKind) =
      while true:
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
        else:
          add lex
    lexReady lex
    if lex.next("js"):
      # setLen(lex.token, 0)
      let pos = lex.getColNumber(lex.bufpos)
      inc lex.bufpos, 3
      collectSnippet(tkJS)
    elif lex.next("sass"):
      setLen(lex.token, 0)
      inc lex.bufpos, 5
      # k = tkSass
    elif lex.next("yaml"):
      setLen(lex.token, 0)
      inc lex.bufpos, 5
      # k = tkYaml
    elif lex.next("json"):
      setLen(lex.token, 0)
      inc lex.bufpos, 5
      # k = tkJson
    elif lex.next("include"):
      lex.setToken tkInclude, 8
    elif lex.next("view"):
      lex.setToken tkView, 5
    elif lex.next("wasm"):
      let pos = lex.getColNumber(lex.bufpos)
      inc lex.bufpos, 5
      if lex.buf[lex.bufpos] == '#':
        var ident: string
        while true:
          if lex.buf[lex.bufpos] in Whitespace:
            break
          inc lex.bufpos
          add ident, lex.buf[lex.bufpos]
        lex.attr.add(ident.strip())
        collectSnippet(tkWasm)
      else:
        lex.setError("Invalid Runtime snippet missing ID attribute")
        return
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
      lex.setToken tkCall

  # proc handleSnippets(lex: var Lexer, kind: TokenKind) =    
  #   lex.startPos = lex.getColNumber(lex.bufpos)
  #   var k = tkJs
  #   if lex.next("javascript"):
  #     setLen(lex.token, 0)
  #     inc lex.bufpos, 11
  #   elif lex.next("sass"):
  #     setLen(lex.token, 0)
  #     inc lex.bufpos, 5
  #     k = tkSass
  #   elif lex.next("yaml"):
  #     setLen(lex.token, 0)
  #     inc lex.bufpos, 5
  #     k = tkYaml
  #   elif lex.next("json"):
  #     setLen(lex.token, 0)
  #     inc lex.bufpos, 5
  #     k = tkJson
  #   else:
  #     lex.setError("Unknown snippet. Tim knows about `js`|`javascript` or `sass`")
  #     return
  #   while true:
  #     case lex.buf[lex.bufpos]
  #     of '`':
  #       if lex.next("``"):
  #         lex.kind = k
  #         inc lex.bufpos, 3
  #         break
  #       else:
  #         add(lex)
  #     of EndOfFile:
  #       lex.setError("EOF reached before end of snippet")
  #       return
  #     else:
  #       add lex.token, lex.buf[lex.bufpos]
  #       inc lex.bufpos

  proc handleCustomIdent(lex: var Lexer, kind: TokenKind) =
    ## Handle variable declarations based the following char sets
    ## ``{'a'..'z', 'A'..'Z', '_', '-'}`` and ``{'0'..'9'}``
    lexReady lex
    inc lex.bufpos
    while true:
      if lex.hasLetters(lex.bufpos):
        add lex.token, lex.buf[lex.bufpos]
        inc lex.bufpos
      elif lex.hasNumbers(lex.bufpos):
        add lex.token, lex.buf[lex.bufpos]
        inc lex.bufpos
      else:
        dec lex.bufpos
        break
    lex.setToken kind

registerTokens defaultSettings:
  a           = "a"
  abbr        = "abbr"
  acronym     = "acronym"
  address     = "address"
  applet      = "applet"
  area        = "area"
  article     = "article"
  aside       = "aside"
  audio       = "audio"
  bold        = "b"
  base        = "base"
  basefont    = "basefont"
  bdi         = "bdi"
  bdo         = "bdo"
  big         = "big"
  blockquote  = "blockquote"
  body        = "body"
  br          = "br"
  button      = "button"
  divide      = '/':
    comment = '/' .. EOL
  canvas      = "canvas"
  caption     = "caption"
  center      = "center"
  cite        = "cite"
  code        = "code"
  col         = "col"
  colgroup    = "colgroup"
  data        = "data"
  datalist    = "datalist"
  dD          = "dd"
  del         = "del"
  details     = "details"
  dFN         = "dfn"
  dialog      = "dialog"
  dir         = "dir"
  `div`         = "div"
  doctype     = "doctype"
  dl          = "dl"
  dt          = "dt"
  em          = "em"
  embed       = "embed"
  fieldset    = "fieldset"
  figcaption  = "figcaption"
  figure      = "figure"
  font        = "font"
  footer      = "footer"
  form        = "form"
  frame       = "frame"
  frameset    = "frameset"
  h1          = "h1"
  h2          = "h2"
  h3          = "h3"
  h4          = "h4"
  h5          = "h5"
  h6          = "h6"
  head        = "head"
  header      = "header"
  hr          = "hr"
  html        = "html"
  italic      = "i"
  iframe      = "iframe"
  img         = "img"
  input       = "input"
  ins         = "ins"
  kbd         = "kbd"
  label       = "label"
  legend      = "legend"
  li          = "li"
  link        = "link"
  main        = "main"
  map         = "map"
  mark        = "mark"
  meta        = "meta"
  meter       = "meter"
  nav         = "nav"
  noframes    = "noframes"
  noscript    = "noscript"
  `object`      = "object"
  ol          = "ol"
  optgroup    = "optgroup"
  option      = "option"
  output      = "output"
  paragraph   = "p"
  param       = "param"
  pre         = "pre"
  progress    = "progress"
  quotation   = "q"
  rp          = "rp"
  rt          = "rt"
  ruby        = "ruby"
  strike      = "s"
  samp        = "samp"
  script      = "script"
  section     = "section"
  select      = "select"
  small       = "small"
  source      = "source"
  span        = "span"
  strike_Long = "strike"
  strong      = "strong"
  style       = "style"
  sub         = "sub"
  summary     = "summary"
  sup         = "sup"

  svg                 = "svg"
  svg_Animate         = "animate"
  svg_AnimateMotion   = "animateMotion"
  svg_AnimateTransform = "animateTransform"
  svg_Circle          = "circle"
  svg_ClipPath        = "clipPath"
  svg_Defs            = "defs"
  svg_Desc            = "desc"
  svg_Discard         = "discard"
  svg_Ellipse         = "ellipse"
  svg_Fe_Blend        = "feBlend"
  svg_Fe_ColorMatrix  = "feColorMatrix"
  svg_Fe_ComponentTransfer   = "feComponentTransfer"
  svg_Fe_Composite           = "feComposite"
  svg_Fe_ConvolveMatrix      = "feConvolveMatrix"
  svg_Fe_DiffuseLighting     = "feDiffuseLighting"
  svg_Fe_DisplacementMap     = "feDisplacementMap"
  svg_Fe_DistantLight        = "feDistantLight"
  svg_Fe_DropShadow          = "feDropShadow"
  svg_Fe_Flood               = "feFlood"
  svg_Fe_FuncA               = "feFuncA"
  svg_Fe_FuncB               = "feFuncB"
  svg_Fe_FuncG               = "feFuncG"
  svg_Fe_FuncR               = "feFuncR"
  svg_Fe_GaussianBlur        = "feGaussianBlur"
  svg_Fe_Image               = "feImage"
  svg_Fe_Merge               = "feMerge"
  svg_Fe_Morphology          = "feMorphology"
  svg_Fe_Offset              = "feOffset"
  svg_Fe_PointLight          = "fePointLight"
  svg_Fe_SpecularLighting    = "feSpecularLighting"
  svg_Fe_SpotLight           = "feSpotLight"
  svg_Fe_Title               = "feTitle"
  svg_Fe_Turbulence          = "feTurbulence"
  svg_Filter                 = "filter"
  svg_foreignObject          = "foreignObject"
  svg_G                      = "g"
  svg_Hatch                  = "hatch"
  svg_HatchPath              = "hatchpath"
  svg_Image                  = "image"
  svg_Line                   = "line"
  svg_LinearGradient         = "linearGradient"
  svg_Marker                 = "marker"
  svg_Mask                   = "mask"
  svg_Metadata               = "metadata"
  svg_Mpath                  = "mpath"
  svg_Path                   = "path"
  svg_Pattern                = "pattern"
  svg_Polygon                = "polygon"
  svg_Polyline               = "polyline"
  svg_RadialGradient         = "radialGradient"
  svg_Rect                   = "rect"
  svg_Set                    = "set"
  svg_Stop                   = "stop"
  svg_Switch                 = "switch"
  svg_Symbol                 = "symbol"
  svg_Text                   = "text"
  svg_TextPath               = "textpath"
  svg_TSpan                  = "tspan"
  svg_Use                    = "use"
  svg_View                   = "view"

  table       = "table"
  tbody       = "tbody"
  td          = "td"
  `template`  = "template"
  textarea    = "textarea"
  tfoot       = "tfoot"
  tH          = "th"
  thead       = "thead"
  time        = "time"
  title       = "title"
  tR          = "tr"
  track       = "track"
  tT          = "tt"
  underline   = "u"  
  uL          = "ul"
  `var`         = "var"
  video       = "video"
  wbr         = "wbr"
  attr                        # a tkIdentifier followed by `=` becomes tkAttr
  js
  sass
  yaml
  json
  # snippet = tokenize(handleSnippets, '`')
  lc = '{'
  rc = '}'
  lp = '('
  rp = ')'
  lb   = '['
  rb   = ']'
  dot  = '.'
  id   = '#'
  assign = '=':
    eq   = '='
  colon  = ':'
  comma  = ','
  gt     = '>':
    gte  = '='
  lt     = '<':
    lte  = '='
  amp    = '&'
  variable = tokenize(handleCustomIdent, '$')
  safeVariable = tokenize(handleCustomIdent, '%')
  `if`   = "if"
  `elif` = "elif"
  `else` = "else"
  sif    = '?'      # short hand `if` statement
  selse  = '|'      # short hand `else` statement
  `and`  = "and"
  `for`  = "for"
  `in`   = "in"
  `or`   = "or"
  `bool` = ["true", "false"]
  `not`  = '!':
    ne = '='
  at = tokenize(handleCalls, '@')
  `include`
  view
  `mixin`
  call
  # `end`
  runtime
  wasm
  plus = '+'
  minus = '-'
  multi = '*'
  `defer` = "defer"
  typeBool = "bool"
  typeInt = "int"
  typeString = "string"
  typeFloat = "float"
  none
