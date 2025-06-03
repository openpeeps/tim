# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://tim-engine.com

import std/[hashes, strutils, json, sequtils, options]

when not defined release:
  import std/jsonutils
else:
  import pkg/jsony

from pkg/htmlparser import tagToStr, htmlTag, HtmlTag
export htmlTag, tagToStr, HtmlTag

type
  NodeKind* = enum
    # leafs
    nkEmpty          # empty node
    nkBool           # bool literal
    nkInt            # int literal
    nkFloat          # float literal
    nkString         # string literal
    nkIdent          # identifier
    nkVarTy          # identifier variable
    nkNil            # nil literal

    # general
    nkScript         # full script
    nkIdentDefs      # identifier definitions - a, b: s = x
    nkFormalParams   # formal params - (a: s, ...) -> t
    nkGenericParams  # generic params - [T, U: X]
    nkRecFields      # record fields - { a, b: t; c: u }

    # expressions
    nkPrefix         # prefix operator - op expr
    nkPostfix        # postfix operator - expr op
    nkInfix          # infix operator - left op right
    nkDot            # dot expression - left.right
    nkBracket
    nkColon          # colon expression - left: right
    nkIndex          # index expression - left[a, ...]
    nkCall           # call - left(a, ...)
    nkIf             # if expression - if expr {...} elif expr {...} else {...}

    # types
    nkProcTy         # procedure type - proc (...) -> t
    nkTypeDef        # type definition - type t = s
    
    # statements
    nkVar = "var"            # var declaration - var a = x
    nkLet = "let"            # let declaration - let a = x
    nkConst = "const"          # const declaration - const a = x
    nkWhile          # while loop - while cond {...}
    nkFor            # for loop - for x in y {...}
    nkBreak          # break statement - break
    nkContinue       # continue statement - continue
    nkReturn         # return statement - return x
    nkYield          # yield statement - yield x
    nkImport         # import statement - import "path/to/module"
    nkInclude        # include statement - include "path/to/file" 
    nkStatic         # static statement 

    # html
    nkHtmlElement    # html element - <tag attr="value">...</tag>
    nkHtmlAttribute

    # declarations
    nkObject         # object declaration - object o[T, ...] {...}
    nkArray          # array declaration - array[T, ...] {...}
    nkProc           # procedure declaration - proc p(a: s, ...) -> t {...}
    nkMacro          # a block - {...}
    nkIterator       # iterator declaration - iterator i(a: s, ...) -> t {...}
    nkBlock          # block statement - block {...}
    nkJavaScriptSnippet

  HtmlAttributeType* = enum
    htmlAttrClass, htmlAttrId, htmlAttrIdent, htmlAttr

  Node* {.acyclic.} = ref object          ## An AST node.
    ln*, col*: int            ## Line information used for compile errors
    # file*: string
    case kind*: NodeKind      ## The kind of the node
    of nkEmpty, nkNil:
      discard
    of nkBool:
      boolVal*: bool
    of nkInt:
      intVal*: int64
    of nkFloat:
      floatVal*: float64
    of nkString:
      stringVal*: string
    of nkIdent:
      ident*: string
    of nkTypeDef:
      typeIdent*: string
      typeTy*: Node
    of nkVarTy:
      varType*: Node
    of nkHtmlElement:
      case tag*: HtmlTag
      of tagUnknown:
        tagCustom*: string
      else: discard
      attributes*: seq[Node]
      childElements*: seq[Node]
    of nkHtmlAttribute:
      attrType*: HtmlAttributeType
      attrNode*: Node
    of nkJavaScriptSnippet:
      snippetCode*: string
      snippetCodeAttrs*: seq[(string, Node)]
    else:
      children*: seq[Node]

  Ast* {.acyclic.} = ref object
    nodes*: seq[Node]

const LeafNodes = {nkEmpty..nkIdent}

when not defined release:
  proc debugEcho*(node: Node) {.gcsafe.} =
    {.gcsafe.}:
      echo pretty(toJson(node), 2)

  proc debugEcho*(nodes: seq[Node]) {.gcsafe.} =
    {.gcsafe.}:
      echo pretty(toJson(nodes), 2)
# else:
#   proc debugEcho*(node: Node) {.gcsafe.} =
#     static:
#       warning("`debugEcho` has no effect when building with `release` flag")

#   proc debugEcho*(nodes: seq[Node]) {.gcsafe.} =
#     static:
#       warning("`debugEcho` has no effect when building with `release` flag")

proc len*(node: Node): int =
  result = node.children.len

proc `[]`*(node: Node, index: int | BackwardsIndex): Node =
  result = node.children[index]

proc `[]`*(node: Node, slice: HSlice): seq[Node] =
  result = node.children[slice]

proc `[]=`*(node: Node, index: int | BackwardsIndex, child: Node) =
  node.children[index] = child

iterator items*(node: Node): Node =
  if node.kind == nkHtmlElement:
    for child in node.childElements:
      yield child
  else:  
    for child in node.children:
      yield child

iterator pairs*(node: Node): tuple[i: int, n: Node] =
  for i, child in node.children:
    yield (i, child)

proc add*(node, child: Node): Node {.discardable.} =
  node.children.add(child)
  result = node

proc add*(node: Node, children: openarray[Node]): Node {.discardable.} =
  node.children.add(children)
  result = node

proc hash*(node: Node): Hash =
  var h = Hash(0)
  h = h !& hash(node.kind)
  case node.kind
  of nkEmpty: discard
  of nkBool: h = h !& hash(node.boolVal)
  of nkInt: h = h !& hash(node.intVal)
  of nkFloat: h = h !& hash(node.floatVal)
  of nkString: h = h !& hash(node.stringVal)
  of nkIdent: h = h !& hash(node.ident)
  else:
    h = h !& hash(node.len)
    h = h !& hash(node.children)
  result = h

proc `$`*(node: Node): string =
  ## Stringify a node. This only supports leaf nodes, for trees,
  ## use ``treeRepr``.
  assert node.kind in LeafNodes, "only leaf nodes can be `$`'ed"
  case node.kind
  of nkEmpty: result = ""
  of nkBool: result = $node.boolVal
  of nkInt: result = $node.intVal
  of nkFloat: result = $node.floatVal
  of nkString: result = node.stringVal.escape
  of nkIdent: result = node.ident
  else: discard

proc treeRepr*(node: Node): string =
  ## Stringify a node into a tree representation.
  case node.kind
  of nkEmpty: result = "Empty"
  of nkBool: result = "Bool " & $node.boolVal
  of nkInt: result = "Int " & $node.intVal
  of nkFloat: result = "Float " & $node.floatVal
  of nkString: result = "String " & escape(node.stringVal)
  of nkIdent: result = "Ident " & node.ident
  else:
    result = ($node.kind)[2..^1]
    var children = ""
    for i, child in node.children:
      children.add('\n' & child.treeRepr)
    result.add(children.indent(2))

proc render*(node: Node): string =
  ## Renders the node's AST representation into a string. Note that this is
  ## imperfect and can't fully reproduce the actual user input (this, for
  ## instance, omits parentheses, as they are ignored by the parser).
  proc join(nodes: seq[Node], delimiter: string): string =
    for i, node in nodes:
      result.add(node.render)
      if i != nodes.len - 1:
        result.add(delimiter)

  case node.kind
  of nkEmpty: result = ""
  of nkNil: result = "nil"

  # html elements
  of nkHtmlElement: result = ""
  of nkHtmlAttribute: result = ""
  of nkJavaScriptSnippet:
    result = node.snippetCode
    # if node.snippetCodeAttrs.len > 0:
    #   result.add(" " & node.snippetCodeAttrs.mapIt($1 & "=" & $2.render).join(", "))
  of nkScript: result = node.children.join("\n")
  of nkStatic: result = "static"
  of nkBlock:
    result =
      if node.len == 0: "{}"
      else: "{\n" & node.children.join("\n").indent(2) & "\n}"
  of nkMacro, nkArray:
    discard # todo
  of nkIdentDefs:
    result = node[0..^3].join(", ")
    if node[^2].kind != nkEmpty: result.add(": " & node[^2].render)
    if node[^1].kind != nkEmpty: result.add(" = " & node[^1].render)
  of nkFormalParams:
    result = '(' & node[1..^1].join(", ") & ')'
    if node[0].kind != nkEmpty: result.add(" -> " & node[0].render)
  of nkGenericParams: result = '[' & node.children.join(", ") & ']'
  of nkRecFields: result = node.children.join("\n")
  of nkBool, nkInt, nkFloat, nkString: result = $node
  of nkIdent:
    let identName = $node
    result =
      if identName.validIdentifier: identName
      else: identName
  of nkVarTy:
    result = "var " & node.varType.render
  of nkPrefix, nkPostfix:
    result = node[0].render & node[1].render
  of nkInfix:
    result = node[1].render & ' ' & node[0].render & ' ' & node[2].render
  of nkImport:
    result = "@import " & node[0].render
  of nkInclude:
    result = "@include " & node[0].render
  of nkDot:
    result = node[0].render & '.' & node[1].render
  of nkBracket:
    result = node[0].render & "[" & node[1].render & "]"
  of nkColon: result = node[0].render & ": " & node[1].render
  of nkIndex: result = node[0].render & '[' & node[1].render & ']'
  of nkCall: result = node[0].render & '(' & node[1..^1].join(", ") & ')'
  of nkIf:
    result = "if " & node[0].render & ' ' & node[1].render
    let
      hasElse = node.children.len mod 2 == 1
      elifBranches =
        if hasElse: node[2..^2]
        else: node[2..^1]
    for i in countup(0, elifBranches.len - 1, 2):
      result.add(" elif " & elifBranches[i].render & ' ' &
                 elifBranches[i + 1].render)
    if hasElse:
      result.add(" else " & node[^1].render)
  of nkProcTy:
    result = "proc " & node[0].render
  of nkTypeDef:
    discard # todo
  of nkVar, nkLet, nkConst:
    result = $node.kind & " " & node[0].render
  of nkWhile: result = "while " & node[0].render & ' ' & node[1].render
  of nkFor:
    result = "for " & node[0].render & " in " & node[1].render &
             ' ' & node[2].render
  of nkBreak: result = "break"
  of nkContinue: result = "continue"
  of nkReturn, nkYield:
    result =
      if node.kind == nkReturn: "return"
      else: "yield"
    if node[0].kind != nkEmpty: result.add(' ' & node[0].render)
  of nkObject:
    result = "object " & node[0].render & node[1].render & " {\n" &
             node[2].render.indent(2) & "\n}\n"
  of nkProc, nkIterator:
    result = (
        if node.kind == nkProc:
          "proc "
        else: "iterator "
      ) & (node[0].render & node[1].render & node[2].render & ' ' & node[3].render)
    if node[0].kind != nkEmpty:
      result.add('\n')

proc newNode*(kind: NodeKind): Node =
  ## Construct a new node.
  Node(kind: kind)

proc newEmpty*: Node =
  ## Construct a new empty node.
  newNode(nkEmpty)

let defaultNil* = newNode(nkNil)
  # Used to represent `nil` in the AST

proc newNil*: Node =
  ## Construct a new nil node.
  newNode(nkNil)

proc newMacro*(children: varargs[Node]): Node =
  ## Construct a new block.
  newNode(nkMacro)

proc nkBlock*(children: varargs[Node]): Node =
  ## Construct a new block.
  newNode(nkBlock)  

proc newTree*(kind: NodeKind, children: varargs[Node]): Node =
  ## Construct a new branch node with the given kind.
  assert kind notin LeafNodes, "kind must denote a branch node"
  result = newNode(kind)
  result.add(children)

proc newBoolLit*(val: bool): Node =
  ## Construct a new bool literal.
  result = newNode(nkBool)
  result.boolVal = val

proc newIntLit*(val: int64): Node =
  ## Construct a new integer literal.
  result = newNode(nkInt)
  result.intVal = val

proc newFloatLit*(val: float64): Node =
  ## Construct a new float literal.
  result = newNode(nkFloat)
  result.floatVal = val

proc newStringLit*(val: string): Node =
  ## Construct a new string literal.
  result = newNode(nkString)
  result.stringVal = val

proc newIdent*(ident: string): Node =
  ## Construct a new ident node.
  result = newNode(nkIdent)
  result.ident = ident

proc newIdentDefs*(names: openarray[Node], ty: Node,
                   value = newEmpty()): Node =
  ## Construct a new nkIdentDefs node.
  result = newTree(nkIdentDefs, names)
  result.add([ty, value])

proc newInfix*(op, left, right: Node): Node =
  ## Construct a new infix node.
  result = newTree(nkInfix, op, left, right)

proc newCall*(ident: Node, args: varargs[Node]): Node =
  ## Construct a new call node.
  result = newTree(nkCall, ident)
  for arg in args:
    result.add(arg)

proc newHtmlElement*(tag: HtmlTag, tagStr: string): Node =
  ## Construct a new HTML element node.
  case tag
  of tagUnknown:
    result = Node(
      kind: nkHtmlElement,
      tag: tagUnknown,
      tagCustom: tagStr
    )
  else:
    result = Node(kind: nkHtmlElement, tag: tag)

proc newHtmlAttribute*(attrType: static HtmlAttributeType, attrNode: Node): Node =
  ## Construct a new HTML attribute node.
  result = Node(
    kind: nkHtmlAttribute,
    attrType: attrType,
    attrNode: attrNode)

proc `$`*(tag: HtmlTag): string =
  result = case tag
    of tagA: "a"
    of tagAbbr: "abbr"
    of tagAcronym: "acronym"
    of tagAddress: "address"
    of tagApplet: "applet"
    of tagArea: "area"
    of tagArticle: "article"
    of tagAside: "aside"
    of tagAudio: "audio"
    of tagB: "b"
    of tagBase: "base"
    of tagBasefont: "basefont"
    of tagBdi: "bdi"
    of tagBdo: "bdo"
    of tagBig: "big"
    of tagBlockquote: "blockquote"
    of tagBody: "body"
    of tagBr: "br"
    of tagButton: "button"
    of tagCanvas: "canvas"
    of tagCaption: "caption"
    of tagCenter: "center"
    of tagCite: "cite"
    of tagCode: "code"
    of tagCol: "col"
    of tagColgroup: "colgroup"
    of tagCommand: "command"
    of tagDatalist: "datalist"
    of tagDd: "dd"
    of tagDel: "del"
    of tagDetails: "details"
    of tagDfn: "dfn"
    of tagDialog: "dialog"
    of tagDiv: "div"
    of tagDir: "dir"
    of tagDl: "dl"
    of tagDt: "dt"
    of tagEm: "em"
    of tagEmbed: "embed"
    of tagFieldset: "fieldset"
    of tagFigcaption: "figcaption"
    of tagFigure: "figure"
    of tagFont: "font"
    of tagFooter: "footer"
    of tagForm: "form"
    of tagFrame: "frame"
    of tagFrameset: "frameset"
    of tagH1: "h1"
    of tagH2: "h2"
    of tagH3: "h3"
    of tagH4: "h4"
    of tagH5: "h5"
    of tagH6: "h6"
    of tagHead: "head"
    of tagHeader: "header"
    of tagHgroup: "hgroup"
    of tagHtml: "html"
    of tagHr: "hr"
    of tagI: "i"
    of tagIframe: "iframe"
    of tagImg: "img"
    of tagInput: "input"
    of tagIns: "ins"
    of tagIsindex: "isindex"
    of tagKbd: "kbd"
    of tagKeygen: "keygen"
    of tagLabel: "label"
    of tagLegend: "legend"
    of tagLi: "li"
    of tagLink: "link"
    of tagMap: "map"
    of tagMark: "mark"
    of tagMenu: "menu"
    of tagMeta: "meta"
    of tagMeter: "meter"
    of tagNav: "nav"
    of tagNobr: "nobr"
    of tagNoframes: "noframes"
    of tagNoscript: "noscript"
    of tagObject: "object"
    of tagOl: "ol"
    of tagOptgroup: "optgroup"
    of tagOption: "option"
    of tagOutput: "output"
    of tagP: "p"
    of tagParam: "param"
    of tagPre: "pre"
    of tagProgress: "progress"
    of tagQ: "q"
    of tagRp: "rp"
    of tagRt: "rt"
    of tagRuby: "ruby"
    of tagS: "s"
    of tagSamp: "samp"
    of tagScript: "script"
    of tagSection: "section"
    of tagSelect: "select"
    of tagSmall: "small"
    of tagSource: "source"
    of tagSpan: "span"
    of tagStrike: "strike"
    of tagStrong: "strong"
    of tagStyle: "style"
    of tagSub: "sub"
    of tagSummary: "summary"
    of tagSup: "sup"
    of tagTable: "table"
    of tagTbody: "tbody"
    of tagTd: "td"
    of tagTextarea: "textarea"
    of tagTfoot: "tfoot"
    of tagTh: "th"
    of tagThead: "thead"
    of tagTime: "time"
    of tagTitle: "title"
    of tagTr: "tr"
    of tagTrack: "track"
    of tagTt: "tt"
    of tagU: "u"
    of tagUl: "ul"
    of tagVar: "var"
    of tagVideo: "video"
    of tagWbr: "wbr"
    else: "" # non-standard HTML tag / custom tag

proc getTag*(node: Node): string =
  result =
    case node.tag
    of tagUnknown: node.tagCustom
    else: $node.tag

const voidHtmlElements* = [tagArea, tagBase, tagBr, tagCol,
  tagEmbed, tagHr, tagImg, tagInput, tagLink, tagMeta,
  tagParam, tagSource, tagTrack, tagWbr, tagCommand,
  tagKeygen, tagFrame]