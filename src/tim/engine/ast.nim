# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim
import ./tokens
import std/[tables, json, macros]

import kapsis/cli

from std/htmlparser import tagToStr, htmlTag, HtmlTag
export tagToStr, htmlTag, HtmlTag

when not defined release:
  import std/jsonutils
else:
  import pkg/jsony

type
  NodeType* = enum
    ntUnknown = "void"

    ntLitInt = "int"
    ntLitString = "string"
    ntLitFloat = "float"
    ntLitBool = "bool"
    ntLitArray = "array"
    ntLitObject = "object"
    ntFunction = "function"
    ntLitVoid = "void"

    ntVariableDef = "Variable"
    ntAssignExpr = "Assignment"
    ntHtmlElement = "HtmlElement"
    ntInfixExpr = "InfixExpression"
    ntMathInfixExpr = "MathExpression"
    ntCommandStmt = "CommandStatement"
    ntIdent = "Identifier"
    ntCall = "FunctionCall"
    ntIdentPair
    ntDotExpr = "DotExpression"
    ntBracketExpr = "BracketExpression"
    ntIndexRange = "IndexRange"
    ntConditionStmt = "ConditionStatement"
    ntCaseStmt = "CaseExpression"
    ntLoopStmt = "LoopStmt"
    ntViewLoader = "ViewLoader"
    ntInclude = "Include"
    ntImport = "Import"
    ntPlaceholder = "Placeholder"
    ntStream = "Stream"
    ntJavaScriptSnippet = "JavaScriptSnippet"
    ntYamlSnippet = "YAMLSnippet"
    ntJsonSnippet = "JsonSnippet"
    ntClientBlock = "ClientSideStatement"
    ntStmtList = "StatementList"
    ntRuntimeCode = "Runtime"

  FunctionType* = enum
    fnImportLocal
    fnImportSystem
    fnImportModule

  CommandType* = enum
    cmdEcho = "echo"
    cmdReturn = "return"
    cmdDiscard = "discard"
    cmdBreak = "break"

  StorageType* = enum
    scopeStorage
      ## Data created inside a `timl` template.
      ## Scope data can be accessed by identifier name
      ## ```
      ## var say = "Hello"
      ## echo $say
      ## ```
    globalStorage
      ## Data exposed globally using a `JsonNode` object
      ## when initializing Tim Engine. Global data
      ## can be accessed from any layout, view or partial
      ## using the `$app` prefix
    localStorage
      ## Data exposed from a Controller using a `JsonNode` object is stored
      ## in a local storage.  Can be accessed from the current view, layout and its partials
      ## using the `$this` prefix.

  InfixOp* {.pure.} = enum
    None
    EQ          = "=="
    NE          = "!="
    GT          = ">"
    GTE         = ">="
    LT          = "<"
    LTE         = "<="
    AND         = "and"
    OR          = "or"
    AMP         = "&"   # string concat purpose

  MathOp* {.pure.} = enum
    invalidCalcOp
    mPlus = "+"
    mMinus = "-"
    mMulti = "*"
    mDiv = "/"
    mMod = "%"

  HtmlAttributes* = TableRef[string, seq[Node]]
  ConditionBranch* = tuple[expr: Node, body: seq[Node]]
  FnParam* = tuple[pName: string, pType: NodeType, pImplVal: Node, meta: Meta]
  Node* {.acyclic.} = ref object
    ## Part of the compiler's abstract syntax tree
    ## **Important** do not initialize this object directly
    case nt*: NodeType
    of ntHtmlElement:
      tag*: HtmlTag
      stag*: string
      attrs*: HtmlAttributes
        # used to store html attributes
      attrNodes*: seq[Node]
      nodes*: seq[Node]
    of ntVariableDef:
      varName*: string
        ## variable identifier
      varValue*: Node
        ## the value of a variable
      varType*: NodeType
        ## type of a variable, any of `string`, `int`, `float`, `array`, `object`
      varUsed*: bool        # todo find a way to manage used/unused variables
      varImmutable*: bool
        ## enabled when a variable is defined as `const`
    of ntAssignExpr:
      asgnIdent*: string
        ## identifier name
      asgnVal*: Node
        ## a Node value assigned to `asgnIdent`
    of ntInfixExpr:
      infixOp*: InfixOp
        ## the infix operator 
      infixLeft*, infixRight*: Node
        ## lhs, rhs nodes
    of ntMathInfixExpr:
      infixMathOp*: MathOp
        ## the infix operator for math operations
      infixMathLeft*, infixMathRight*: Node
        ## lhs, rhs nodes for math operations
    of ntConditionStmt:
      condIfBranch*: ConditionBranch
        ## the `if` branch of a conditional statement
      condElifBranch*: seq[ConditionBranch]
        ## a sequence of `elif` branches
      condElseBranch*: seq[Node]
        ## the body of an `else` branch
    of ntCaseStmt:
      caseExpr*: Node
      caseBranch*: seq[ConditionBranch]
      caseElse*: seq[Node]
    of ntLoopStmt:
      loopItem*: Node
        ## a node type of `ntIdent` or `ntIdentPair`
      loopItems*: Node
        ## a node type represeting an iterable storage
      loopBody*: seq[Node]
        ## a sequence of Node elements in `for` body
    of ntIdentPair:
      identPairs*: tuple[a, b: Node]
    of ntLitString:
      sVal*: string
      sVals*: seq[Node]
    of ntLitInt:
      iVal*: int
    of ntLitFloat:
      fVal*: float
    of ntLitBool:
      bVal*: bool
    of ntLitArray:
      arrayType*: NodeType
      arrayItems*: seq[Node]
        ## a sequence of nodes representing an array
    of ntLitObject:
      objectItems*: OrderedTableRef[string, Node]
        ## Ordered table of Nodes for object storage
    of ntCommandStmt:
      cmdType*: CommandType
        ## type of given command, either `echo` or `return`
      cmdValue*: Node
        ## the node value of the command 
    of ntIdent:
      identName*: string
        # identifier name
      identSafe*: bool
        # whether to escape the stored value of `identName`
      identArgs*: seq[Node]
    # of ntCall:
    #   callIdent*: string
    #     ## identifier name of a callable function
    #   callArgs*: seq[Node]
    #     ## a sequence of arguments to to pass
    of ntDotExpr:
      storageType*: StorageType
        ## holds the storage type of a dot expression
      lhs*, rhs*: Node
        ## lhs, rhs nodes of dot expression node
    of ntBracketExpr:
      bracketStorageType*: StorageType
        ## holds the storage type of a bracket expression
      bracketLHS*, bracketIndex*: Node
        ## lhs, rhs nodes of a bracket expression
    of ntIndexRange:
      rangeNodes*: array[2, Node]
      rangeLastIndex*: bool # from end to start using ^ circumflex accent
    of ntFunction:
      fnIdent*: string
        ## function identifier name
      fnParams*: OrderedTable[string, FnParam]
        ## an ordered table containing the function parameters
      fnBody*: seq[Node]
        ## the function body
      fnReturnType*: NodeType
        ## the return type of a function
        ## if a function has no return type, then `ntUnknown`
        ## is used as default (void)
      fnReturnHtmlElement*: HtmlTag
      fnFwdDecl*, fnExport*: bool
      fnType*: FunctionType
      fnSource*: string
    of ntJavaScriptSnippet,
      ntYamlSnippet, ntJsonSnippet:
        snippetCode*: string
          ## string-based snipept code for either
          ## `yaml`, `json` or `js`
          # todo add support bass code (bro lang)
          # find more about Bro on https://github.com/openpeeps/bro
    of ntInclude:
      includes*: seq[string]
        ## a sequence of files to be included
    of ntImport:
      modules*: seq[string]
        ## a sequence containing imported modules
    of ntPlaceholder:
      placeholderName*: string
        ## placeholder target name
    of ntStream:
      streamContent*: JsonNode
    of ntClientBlock:
      clientTargetElement*: string
        ## an existing HTML selector to used
        ## to insert generated JavaScript snippet
        ## using `insertAdjacentElement()`
      clientStmt*: seq[Node]
        ## nodes to interpret/transpile to JavaScript
        ## for client-side rendering. Note that only HTML
        ## elements will be transformed to JS code, while
        ## other statements (such `if`, `for`, `var`) are getting
        ## interpreted at compile-time (for static templates) or 
        ## on the fly for templates marked as jit.
    of ntStmtList:
      stmtList*: seq[Node]
    of ntRuntimeCode:
      runtimeCode*: string
    else: discard
    meta*: Meta

  ValueKind* = enum
    jsonValue, nimValue

  Value* = object
    case kind*: ValueKind
    of jsonValue:
      jVal*: JsonNode
    of nimValue:
      nVal*: Node

  Meta* = array[3, int]
  ScopeTable* = TableRef[string, Node]
  TimPartialsTable* = TableRef[string, (Ast, seq[cli.Row])]
  TimModulesTable* = TableRef[string, Ast]
  Ast* {.acyclic.} = ref object
    src*: string
      ## the source path of the ast
    nodes*: seq[Node]
      ## a seq containing tree nodes 
    partials*: TimPartialsTable
      ## AST trees from included partials 
    modules*: TimModulesTable
      ## AST trees from imported modules
    jit*: bool
      ## whether the current AST requires JIT compliation or not

const ntAssignableSet* =
  {ntLitString, ntLitInt, ntLitFloat,
  ntLitBool, ntLitObject, ntLitArray}

proc getInfixOp*(kind: TokenKind, isInfixInfix: bool): InfixOp =
  result =
    case kind:
    of tkEQ: EQ
    of tkNE: NE
    of tkLT: LT
    of tkLTE: LTE
    of tkGT: GT
    of tkGTE: GTE
    of tkAmp: AMP
    else:
      if isInfixInfix:
        case kind
        of tkAndAnd, tkAnd: AND
        of tkOROR, tkOR: OR
        of tkAmp: AMP
        else: None
      else: None

proc getInfixMathOp*(kind: TokenKind, isInfixInfix: bool): MathOp =
  result =
    case kind:
    of tkPlus: mPlus
    of tkMinus: mMinus
    of tkAsterisk: mMulti
    of tkDivide: mDiv
    of tkMod: mMod
    else: invalidCalcOp

proc getTag*(x: Node): string =
  # todo use pkg/htmlparser
  result =
    case x.tag
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
    else: x.stag # tagUnknown

proc getType*(x: NimNode): NodeType {.compileTime.} = 
  if x.strVal == "string":
    return ntLitString
  if x.strVal == "int":
    return ntLitInt
  if x.strVal == "float":
    return ntLitFloat
  if x.strVal == "bool":
    return ntLitBool
  if x.strVal == "object":
    return ntLitObject
  if x.strVal == "array":
    return ntLitArray
  result = ntUnknown

#
# AST to JSON convertors
#
# proc `$`*(node: Node): string =
#   {.gcsafe.}:
#     when not defined release:
#       pretty(toJson(node), 2)
#     else:
#       toJson(node)

# proc `$`*(nodes: seq[Node]): string =
#   {.gcsafe.}:
#     when not defined release:
#       pretty(toJson(nodes), 2)
#     else:
#       toJson(nodes)

proc `$`*(x: Ast): string =
  {.gcsafe.}:
    when not defined release:
      pretty(toJson(x), 2)
    else:
      toJson(x)

#
# AST Generators
#
proc newNode*(nt: static NodeType, tk: TokenTuple): Node =
  Node(nt: nt, meta: [tk.line, tk.pos, tk.col])

proc newNode*(nt: static NodeType): Node =
  Node(nt: nt)

proc newString*(tk: TokenTuple): Node =
  ## Create a new string value node
  result = newNode(ntLitString, tk)
  result.sVal = tk.value

proc newString*(v: string): Node =
  ## Create a new string value node
  result = newNode(ntLitString)
  result.sVal = v

proc newInteger*(v: int, tk: TokenTuple): Node =
  result = newNode(ntLitInt, tk)
  result.iVal = v

proc newInteger*(v: int): Node =
  result = newNode(ntLitInt)
  result.iVal = v

proc newFloat*(v: float, tk: TokenTuple): Node =
  ## Create a new float value node
  result = newNode(ntLitFloat, tk)
  result.fVal = v

proc newFloat*(v: float): Node =
  ## Create a new float value node
  result = newNode(ntLitFloat)
  result.fVal = v

proc newBool*(v: bool, tk: TokenTuple): Node =
  ## Create a new bool value Node
  result = newNode(ntLitBool, tk)
  result.bVal = v

proc newBool*(v: bool): Node =
  ## Create a new bool value Node
  result = newNode(ntLitBool)
  result.bVal = v

var voidNode = newNode(ntLitVoid)
proc getVoidNode*(): Node = voidNode

proc newVariable*(varName: string, varValue: Node, meta: Meta): Node =
  ## Create a new variable definition Node
  result = newNode(ntVariableDef)
  result.varName = varName
  result.varValue = varvalue
  result.meta = meta

proc newVariable*(varName: string, varValue: Node, tk: TokenTuple): Node =
  ## Create a new variable definition Node
  result = newNode(ntVariableDef, tk)
  result.varName = varName
  result.varValue = varvalue

proc newAssignment*(tk: TokenTuple, varValue: Node): Node =
  ## Create a new assignment Node
  result = newNode(ntAssignExpr, tk)
  result.asgnIdent = tk.value
  result.asgnVal = varValue

proc newFunction*(tk: TokenTuple, ident: string): Node =
  ## Create a new Function definition Node
  result = newNode(ntFunction, tk)
  result.fnIdent = ident

proc newCall*(tk: TokenTuple): Node =
  ## Create a new function call Node
  result = newNode(ntIdent, tk)
  result.identName = tk.value

proc newInfix*(lhs, rhs: Node, infixOp: InfixOp, tk: TokenTuple): Node =
  result = newNode(ntInfixExpr, tk)
  result.infixOp = infixOp
  result.infixLeft = lhs
  result.infixRight = rhs

proc newCommand*(cmdType: CommandType, node: Node, tk: TokenTuple): Node =
  ## Create a new command for `cmdType`
  result = newNode(ntCommandStmt, tk)
  result.cmdType = cmdType
  result.cmdValue = node

proc newIdent*(tk: TokenTuple): Node=
  result = newNode(ntIdent, tk)
  result.identName = tk.value

proc newHtmlElement*(tag: HtmlTag, tk: TokenTuple): Node =
  result = newNode(ntHtmlElement, tk)
  result.tag = tag
  case tag
  of tagUnknown:
    result.stag = tk.value
  else: discard

proc newCondition*(condIfBranch: ConditionBranch, tk: TokenTuple): Node =
  result = newNode(ntConditionStmt, tk)
  result.condIfBranch = condIfBranch

proc newArray*(items: seq[Node] = @[]): Node =
  ## Creates a new `Array` node
  result = newNode(ntLitArray)
  result.arrayItems = items

proc toTimNode*(x: JsonNode): Node =
  case x.kind
  of JString:
    result = newNode(ntLitString)
    result.sVal = x.str
  of JInt:
    result = newNode(ntLitInt)
    result.iVal = x.num
  of JFloat:
    result = newNode(ntLitFloat)
    result.fVal = x.fnum
  of JBool:
    result = newNode(ntLitBool)
    result.bVal = x.bval
  of JObject:
    result = newNode(ntLitObject)
    result.objectItems = newOrderedTable[string, Node]()
    for k, v in x:
      result.objectItems[k] = toTimNode(v)
  of JArray:
    result = newNode(ntLitArray)
    for v in x:
      result.arrayItems.add(toTimNode(v))
  else: discard

proc newStream*(node: JsonNode): Node =
  ## Create a new Stream from `node`
  Node(nt: ntStream, streamContent: node)

# proc toTimNode(): NimNode =
#   # https://github.com/nim-lang/Nim/blob/version-2-0/lib/pure/json.nim#L410
#   case x.kind
#   of nnkBracket:
#     # ntArrayStorage
#     if x.len == 0:
#       return newCall(bindSym"newArray")
#     result = newNimNode(nnkBracket)
#   of nnkTableConstr:
#     discard
#   else: discard # error?

# macro `%*`*(x: untyped): untyped =
#   ## Convert an expression to a Tim Node directly.
#   ## This macro is similar with `%*` from std/json,
#   ## except is generating Tim Nodes instead of JsonNode objects.
#   result = toTimNode(x)