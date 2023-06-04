# A high-performance compiled template engine
# inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, json, jsonutils]

from ./tokens import TokenKind, TokenTuple
from std/enumutils import symbolName

type
  NodeType* = enum
    NTNone
    NTStmtList
    NTInt
    NTFloat
    NTString
    NTBool
    NTId
    NTHtmlElement
    NTStatement
    NTConditionStmt
    NTShortConditionStmt
    NTForStmt
    NTMixinStmt
    NTPrefixStmt
    NTInfixStmt
    NTIncludeCall
    NTCall
    NTMixinCall
    NTMixinDef
    NTLet
    NTVar
    NTVariable
    NTIdentifier
    NTView
    NTJavaScript
    NTSass
    NTJson
    NTYaml
    NTResult

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
    HtmlHeader
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
    HtmlTextarea
  
  OperatorType* {.pure.} = enum
    None
    EQ          = "=="
    NE          = "!="
    GT          = ">"
    GTE         = ">="
    LT          = "<"
    LTE         = "<="
    AND         = "and"
    AMP         = "&"   # string concatenation
  
  HtmlAttributes* = Table[string, seq[Node]]
  IfBranch* = tuple[cond: Node, body: seq[Node]]
  SIfBranch* = tuple[cond: Node, body: HtmlAttributes]
  ElifBranch* = seq[IfBranch]
  MetaNode* = tuple[line, pos, col, wsno: int]
  ParamTuple* = tuple[key, value, typeSymbol: string, `type`: NodeType]
  
  AccessorKind* {.pure.} = enum
    None, Key, Value

  VarVisibility* = enum
    ## Defines three types of variables:
    ##
    ## - `GlobalVar` is reserved for data provided at the main level of your app using `setData()`. Global variables can be accessed in tim templates using `$app` object.
    ##
    ## - `ScopeVar` variables are defined at controller level via `render()` proc and exposed to its view, layout and partials under `$this` object.
    ##
    ## - `InternalVar` variables have some limitations. Can be defined in timl templates, and can hold either `string`, `int`, `float`, `bool`.
    ##
    ## **Note:** `$app` and `$this` are reserved variables.
    ## **Note** Global/Scope variables can be accessed using dot notation.
    GlobalVar
    ScopeVar
    InternalVar

  Node* = ref object
    nodeName*: string
    case nodeType*: NodeType
    of NTInt: 
      iVal*: int
    of NTFloat:
      fVal*: float
    of NTString:
      sVal*: string
      sConcat*: seq[Node]
    of NTBool:
      bVal*: bool
    of NTId:
      idVal*: string
    of NTConditionStmt:
      ifCond*: Node
      ifBody*, elseBody*: seq[Node]
      elifBranch*: ElifBranch
    of NTShortConditionStmt:
      sIfCond*: Node
      sIfBody*: HtmlAttributes
    of NTForStmt:
      forItem*: Node  # NTVariable
      forItems*: Node # NTVariable
      forBody*: seq[Node]
    of NTHtmlElement:
      htmlNodeName*: string
      htmlNodeType*: HtmlNodeType
      attrs*: HtmlAttributes
      nodes*: seq[Node]
      issctag*: bool
    of NTStmtList:
      stmtList*: Node
    of NTInfixStmt:
      infixOp*: OperatorType
      infixOpSymbol*: string
      infixLeft*, infixRight*: Node
    of NTIncludeCall:
      includeIdent*: string
    of NTCall:
      callIdent*: string
      callParams*: seq[Node] # NTString or NTVariable
    of NTMixinCall:
      mixinIdent*: string
    of NTMixinDef:
      mixinIdentDef*: string
      mixinParamsDef*: seq[ParamTuple]
      mixinBody*: seq[Node]
    of NTVariable:
      varIdent*: string
      varSymbol*: string
      varType*: NodeType # NTBool, NTInt, NTString
      visibility*: VarVisibility
      isSafeVar*: bool
      dataStorage*: bool
      accessors*: seq[Node]
      case accessorKind*: AccessorKind
      of Key:
        byKey*: string
      else: discard
    of NTJavaScript:
      jsCode*: string
    of NTSass:
      sassCode*: string
    of NTJson:
      jsonIdent*: string
      jsonCode*: string
    of NTYaml:
      yamlCode*: string
    else: discard
    meta*: MetaNode

  Program* = object
    nodes*: seq[Node]

proc `$`*(node: Node): string =
  result = pretty(toJson(node))

proc getSymbolName*(symbol: NodeType|OperatorType): string =
  # Get stringified symbol name (useful for debugging, otherwise is empty) 
  when not defined release:
    result = symbolName(symbol)
  else: result = ""

proc newNode*(nt: NodeType, tk: TokenTuple): Node =
  ## Create a new Node
  result = Node(nodeName: getSymbolName(nt), nodeType: nt)
  result.meta = (tk.line, tk.pos, tk.col, tk.wsno)

proc newSnippet*(tk: TokenTuple, ident = ""): Node =
  ## Add a new Snippet node. It can be `NTJavaScript`,
  ## `NTSass`, `NTJSON` or `NTYaml`
  if tk.kind == TK_JS:
    result = newNode(NTJavaScript, tk)
  elif tk.kind == TK_SASS:
    result = newNode(NTSass, tk)
  elif tk.kind == TK_JSON:
    result = newNode(NTJSon, tk)
    result.jsonIdent = ident
  elif tk.kind == TK_YAML:
    result = newNode(NTYaml, tk)

proc newExpression*(expression: Node): Node =
  ## Add a new `NTStmtList` expression node
  result = Node(
    nodeName: getSymbolName(NTStmtList),
    nodeType: NTStmtList,
    stmtList: expression
  )

proc newInfix*(infixLeft, infixRight: Node, infixOp: OperatorType): Node =
  ## Add a new `NTInfixStmt` node
  Node(
    nodeName: getSymbolName(NTInfixStmt),
    nodeType: NTInfixStmt,
    infixLeft: infixLeft,
    infixRight: infixRight,
    infixOp: infixOp,
    infixOpSymbol: getSymbolName(infixOp)
  )

proc newInfix*(infixLeft: Node): Node =
  ## Add a new `NTInfixStmt` node
  Node(
    nodeName: getSymbolName(NTInfixStmt),
    nodeType: NTInfixStmt,
    infixLeft: infixLeft,
    # infixRight: infixRight,
    # infixOp: infixOp,
    # infixOpSymbol: getSymbolName(infixOp)
  )

proc newInt*(iVal: int, tk: TokenTuple): Node =
  ## Add a new `NTInt` node
  Node(nodeName: getSymbolName(NTInt), nodeType: NTInt, iVal: iVal, meta: (tk.line, tk.pos, tk.col, tk.wsno))

proc newBool*(bVal: bool): Node =
  ## Add a new `NTBool` node
  Node(nodeName: getSymbolName(NTBool), nodeType: NTBool, bVal: bVal)

proc newString*(tk: TokenTuple, strs: seq[Node] = @[]): Node =
  ## Add a new `NTString` node
  Node(
    nodeName: getSymbolName(NTString),
    nodeType: NTString,
    sVal: tk.value,
    sConcat: strs,
    meta: (tk.line, tk.pos, tk.col, tk.wsno)
  )

proc newHtmlElement*(tk: TokenTuple): Node =
  ## Add a new `NTHtmlElement` node
  Node(
    nodeName: getSymbolName(NTHtmlElement),
    nodeType: NTHtmlElement,
    htmlNodeName: tk.value,
    meta: (tk.line, tk.pos, tk.col, tk.wsno)
  )

proc newIfExpression*(ifBranch: IfBranch, tk: TokenTuple): Node =
  ## Add a mew Conditional node
  Node(
    nodeName: getSymbolName(NTConditionStmt),
    nodeType: NTConditionStmt,
    ifCond: ifBranch.cond,
    ifBody: ifBranch.body,
    meta: (tk.line, tk.pos, tk.col, tk.wsno)
  )

proc newShortIfExpression*(ifBranch: SIfBranch, tk: TokenTuple): Node =
  ## Add a new short hand conditional node
  Node(
    nodeName: getSymbolName(NTShortConditionStmt),
    nodeType: NTShortConditionStmt,
    sIfCond: ifBranch.cond,
    sIfBody: ifBranch.body,
    meta: (tk.line, tk.pos, tk.col, tk.wsno)
  )

proc newCall*(ident: string, params: seq[Node]): Node =
  ## Add a new `NTCall` node
  Node(nodeName: getSymbolName(NTCall), nodeType: NTCall, callIdent: ident, callParams: params)

proc newMixin*(tk: TokenTuple): Node =
  ## Add a new `NTMixinCall` node
  Node(nodeName: getSymbolName(NTMixinCall), nodeType: NTMixinCall, mixinIdent: tk.value)

proc newMixinDef*(tk: TokenTuple): Node = 
  Node(nodeName: getSymbolName(NTMixinDef), nodeType: NTMixinDef, mixinIdentDef: tk.value)

proc newView*(tk: TokenTuple): Node =
  Node(nodeName: getSymbolName(NTView), nodeType: NTView, meta: (tk.line, tk.pos, tk.col, tk.wsno))

proc newInclude*(ident: string): Node =
  ## Add a new `NTIncludeCall` node
  Node(nodeName: getSymbolName(NTIncludeCall), nodeType: NTIncludeCall, includeIdent: ident)

proc newFor*(itemVarIdent, itemsVarIdent: Node, body: seq[Node], tk: TokenTuple): Node =
  ## Add a new `NTForStmt` node
  result = newNode(NTForStmt, tk)
  result.forBody = body
  result.forItem = itemVarIdent
  result.forItems = itemsVarIdent

proc newVariable*(tk: TokenTuple, isSafeVar, dataStorage = false,
        varType = NTString, varVisibility: VarVisibility = GlobalVar): Node =
  ## Add a new `NTVariable` node
  result = newNode(NTVariable, tk)
  result.varIdent = tk.value
  result.varSymbol = "$" & tk.value
  result.isSafeVar = isSafeVar
  result.dataStorage = dataStorage
  result.varType = varType
  result.visibility = varVisibility

proc newVarCallKeyAccessor*(tk: TokenTuple, fid: string): Node =
  result = Node(
    nodeName: getSymbolName(NTVariable),
    nodeType:  NTVariable,
    accessorKind: Key,
    byKey: fid,
    varIdent: tk.value,
    varSymbol: "$" & tk.value,
    meta: (tk.line, tk.pos, tk.col, tk.wsno)
  )

proc newVarCallValAccessor*(tk: TokenTuple): Node =
  result = Node(
    nodeName: getSymbolName(NTVariable),
    nodeType:  NTVariable,
    accessorKind: Value,
    varIdent: tk.value,
    varSymbol: "$" & tk.value,
    meta: (tk.line, tk.pos, tk.col, tk.wsno)
  )
