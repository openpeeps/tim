# A blazing fast, cross-platform, multi-language
# template engine and markup language written in Nim.
#
#    Made by Humans from OpenPeeps
#    (c) George Lemon | LGPLv3 License
#    https://github.com/openpeeps/tim

import std/[tables, json, jsonutils]

from ./tokens import TokenKind, TokenTuple
from std/enumutils import symbolName

type
  NodeType* = enum
    ntNone = "none"
    ntStmtList = "StatementList"
    ntInt = "int"
    ntFloat = "float"
    ntString = "string"
    ntBool = "bool"
    ntId = "ident"
    ntHtmlElement = "HtmlElement"
    ntStatement
    ntVarExpr = "VariableDeclaration"
    ntCondition = "ConditionStatement"
    ntShortConditionStmt = "ShortConditionStatement"
    ntForStmt = "ForStatement"
    ntMixinStmt = "MixinStatement"
    ntInfixStmt
    ntIncludeCall
    ntCall
    ntMixinCall
    ntMixinDef
    ntLet
    ntVar
    ntVariable
    ntIdentifier
    ntView
    ntJavaScript
    ntSass
    ntJson
    ntYaml
    ntResult
    ntRuntime

  InfixOp* {.pure.} = enum
    None = "none" 
    EQ          = "=="
    NEQ         = "!="
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
    GlobalVar
    ScopeVar
    InternalVar

  Node* {.acyclic.} = ref object
    case nt*: NodeType
    of ntInt: 
      iVal*: int
    of ntFloat:
      fVal*: float
    of ntString:
      sVal*: string
      sConcat*: seq[Node]
    of ntBool:
      bVal*: bool
    of ntId:
      idVal*: string
    of ntCondition:
      ifCond*: Node
      ifBody*, elseBody*: seq[Node]
      elifBranch*: ElifBranch
    of ntShortConditionStmt:
      sIfCond*: Node
      sIfBody*: HtmlAttributes
    of ntForStmt:
      forItem*: Node  # ntVariable
      forItems*: Node # ntVariable
      forBody*: seq[Node]
    of ntHtmlElement:
      htmlNodeName*: string
      attrs*: HtmlAttributes
      nodes*: seq[Node]
      selfCloser*: bool
    of ntStmtList:
      stmtList*: Node
    of ntInfixStmt:
      infixOp*: InfixOp
      infixLeft*, infixRight*: Node
    of ntIncludeCall:
      includeIdent*: string
    of ntCall:
      callIdent*: string
      callParams*: seq[Node] # ntString or ntVariable
    of ntMixinCall:
      mixinIdent*: string
    of ntMixinDef:
      mixinIdentDef*: string
      mixinParamsDef*: seq[ParamTuple]
      mixinBody*: seq[Node]
    of ntVarExpr:
      varIdentExpr*: string
      varTypeExpr*: NodeType # ntBool, ntInt, ntString, ntFloat
      varValue*: Node
    of ntVariable: # todo rename ntVarCall
      varIdent*: string
      varSymbol*: string
      varType*: NodeType # ntBool, ntInt, ntString, ntFloat
      visibility*: VarVisibility
      isSafeVar*: bool
      dataStorage*: bool
      accessors*: seq[Node]
      case accessorKind*: AccessorKind
      of Key:
        byKey*: string
      else: discard
    of ntJavaScript:
      jsCode*: string
    of ntSass:
      sassCode*: string
    of ntJson:
      jsonIdent*, jsonCode*: string
    of ntYaml:
      yamlCode*: string
    of ntRuntime:
      runtimeIdent*, runtimeCode*: string
    else: discard
    meta*: MetaNode

  Tree* = object
    nodes*: seq[Node]

proc `$`*(node: Node): string =
  result = pretty(toJson(node))

proc `$`*(tree: Tree): string =
  result = pretty(toJson(tree))

proc newNode*(nt: NodeType, tk: TokenTuple): Node =
  ## Create a new Node
  result = Node(nt: nt)
  result.meta = (tk.line, tk.pos, tk.col, tk.wsno)

proc newSnippet*(tk: TokenTuple, ident = ""): Node =
  ## Add a new Snippet node. It can be `ntJavaScript`,
  ## `ntSass`, `ntJSON` or `ntYaml`
  if tk.kind == tkJS:
    result = newNode(ntJavaScript, tk)
  elif tk.kind == tkSASS:
    result = newNode(ntSass, tk)
  elif tk.kind == tkJSON:
    result = newNode(ntJSon, tk)
    result.jsonIdent = ident
  elif tk.kind == tkYAML:
    result = newNode(ntYaml, tk)

proc newExpression*(expression: Node): Node =
  ## Add a new `ntStmtList` expression node
  result = Node(
    nt: ntStmtList,
    stmtList: expression
  )

proc newInfix*(infixLeft, infixRight: Node, infixOp: InfixOp): Node =
  ## Add a new `ntInfixStmt` node
  Node(
    nt: ntInfixStmt,
    infixLeft: infixLeft,
    infixRight: infixRight,
    infixOp: infixOp,
  )

proc newVar*(tk: TokenTuple, varType: NodeType, varValue: Node): Node =
  result = newNode(ntVarExpr, tk)
  result.varIdentExpr = tk.value
  result.varTypeExpr = varType
  result.varValue = varValue

proc newInfix*(infixLeft: Node): Node =
  ## Add a new `ntInfixStmt` node
  Node(nt: ntInfixStmt, infixLeft: infixLeft)

proc newInt*(iVal: int, tk: TokenTuple): Node =
  ## Add a new `ntInt` node
  Node(nt: ntInt, iVal: iVal, meta: (tk.line, tk.pos, tk.col, tk.wsno))

proc newBool*(bVal: bool): Node =
  ## Add a new `ntBool` node
  Node(nt: ntBool, bVal: bVal)

proc newFloat*(fVal: float): Node =
  ## Add a new `ntFloat` node
  Node(nt: ntFloat, fVal: fVal) 

proc newString*(tk: TokenTuple, strs: seq[Node] = @[]): Node =
  ## Add a new `ntString` node
  Node(
    nt: ntString,
    sVal: tk.value,
    sConcat: strs,
    meta: (tk.line, tk.pos, tk.col, tk.wsno)
  )

proc newHtmlElement*(tk: TokenTuple): Node =
  ## Add a new `ntHtmlElement` node
  Node(
    nt: ntHtmlElement,
    htmlNodeName: tk.value,
    meta: (tk.line, tk.pos, tk.col, tk.wsno)
  )

proc newIfExpression*(ifBranch: IfBranch, tk: TokenTuple): Node =
  ## Add a mew Conditional node
  Node(
    nt: ntCondition,
    ifCond: ifBranch.cond,
    ifBody: ifBranch.body,
    meta: (tk.line, tk.pos, tk.col, tk.wsno)
  )

proc newShortIfExpression*(ifBranch: SIfBranch, tk: TokenTuple): Node =
  ## Add a new short hand conditional node
  Node(
    nt: ntShortConditionStmt,
    sIfCond: ifBranch.cond,
    sIfBody: ifBranch.body,
    meta: (tk.line, tk.pos, tk.col, tk.wsno)
  )

proc newCall*(ident: string, params: seq[Node]): Node =
  ## Add a new `ntCall` node
  Node(nt: ntCall, callIdent: ident, callParams: params)

proc newMixin*(tk: TokenTuple): Node =
  ## Add a new `ntMixinCall` node
  Node(nt: ntMixinCall, mixinIdent: tk.value)

proc newMixinDef*(tk: TokenTuple): Node = 
  Node(nt: ntMixinDef, mixinIdentDef: tk.value)

proc newView*(tk: TokenTuple): Node =
  Node(nt: ntView, meta: (tk.line, tk.pos, tk.col, tk.wsno))

proc newInclude*(ident: string): Node =
  ## Add a new `ntIncludeCall` node
  Node(nt: ntIncludeCall, includeIdent: ident)

proc newFor*(itemVarIdent, itemsVarIdent: Node, body: seq[Node], tk: TokenTuple): Node =
  ## Add a new `ntForStmt` node
  result = newNode(ntForStmt, tk)
  result.forBody = body
  result.forItem = itemVarIdent
  result.forItems = itemsVarIdent

proc newVariable*(tk: TokenTuple, isSafeVar, dataStorage = false,
        varType = ntString, varVisibility: VarVisibility = GlobalVar): Node =
  ## Add a new `ntVariable` node
  result = newNode(ntVariable, tk)
  result.varIdent = tk.value
  result.varSymbol = "$" & tk.value
  result.isSafeVar = isSafeVar
  result.dataStorage = dataStorage
  result.varType = varType
  result.visibility = varVisibility

proc newVarCallKeyAccessor*(tk: TokenTuple, fid: string): Node =
  result = Node(
    nt:  ntVariable,
    accessorKind: Key,
    byKey: fid,
    varIdent: tk.value,
    varSymbol: "$" & tk.value,
    meta: (tk.line, tk.pos, tk.col, tk.wsno)
  )

proc newVarCallValAccessor*(tk: TokenTuple): Node =
  result = Node(
    nt:  ntVariable,
    accessorKind: Value,
    varIdent: tk.value,
    varSymbol: "$" & tk.value,
    meta: (tk.line, tk.pos, tk.col, tk.wsno)
  )

proc newRuntime*(tk: TokenTuple): Node =
  result = Node(nt: ntRuntime, runtimeCode: tk.value, runtimeIdent: tk.attr[0])