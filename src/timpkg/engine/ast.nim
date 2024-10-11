# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim
import ./tokens
import std/[tables, json, macros, hashes]

import pkg/sorta
import pkg/kapsis/cli

from std/htmlparser import tagToStr, htmlTag, HtmlTag
export tagToStr, htmlTag, HtmlTag

when not defined release:
  import std/jsonutils
else:
  import pkg/jsony

type
  NodeType* = enum
    ntUnknown = "untyped"

    ntLitInt = "int"
    ntLitString = "string"
    ntLitFloat = "float"
    ntLitBool = "bool"
    ntLitArray = "array"
    ntLitObject = "object"
    ntFunction = "function"
    ntBlock = "block"
    ntLitVoid = "void"

    ntVariableDef = "Variable"
    ntAssignExpr = "Assignment"
    ntHtmlElement = "HtmlElement"
    ntHtmlAttribute = "HtmlAttribute"
    ntInfixExpr = "InfixExpression"
    ntParGroupExpr = "GroupExpression"
    ntMathInfixExpr = "MathExpression"
    ntCommandStmt = "CommandStatement"
    ntIdent = "Identifier"
    ntIdentVar = "VarIdentifier"
    ntBlockIdent = "BlockIdentifier"
    ntComponent = "Component"
    ntTypeDef = "TypeDefinition"
    ntEscape = "EscapedIdentifier"
    ntCall = "FunctionCall"
    ntIdentPair
    ntDotExpr = "DotExpression"
    ntBracketExpr = "BracketExpression"
    ntIndexRange = "IndexRange"
    ntDoBlock = "DoBlock"
    ntConditionStmt = "ConditionStatement"
    ntCaseStmt = "CaseExpression"
    ntLoopStmt = "LoopStmt"
    ntWhileStmt = "WhileStmt"
    ntViewLoader = "ViewLoader"
    ntInclude = "Include"
    ntImport = "Import"
    ntPlaceholder = "Placeholder"
    ntStream = "stream" # todo rename to `json`
    ntJavaScriptSnippet = "JavaScriptSnippet"
    ntYamlSnippet = "YAMLSnippet"
    ntJsonSnippet = "JsonSnippet"
    ntClientBlock = "ClientSideStatement"
    ntStmtList = "StatementList"
    ntRuntimeCode = "Runtime"
    ntReference = "Reference"

  FunctionType* = enum
    fnImportLocal
    fnImportSystem
    fnImportModule

  CommandType* = enum
    cmdEcho = "echo"
    cmdReturn = "return"
    cmdDiscard = "discard"
    cmdBreak = "break"
    cmdContinue = "continue"
    cmdAssert = "assert"

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
  HtmlAttributesTable* = TableRef[string, seq[Node]]
  ConditionBranch* = tuple[expr: Node, body: Node]
  FnParam* = tuple[
    paramName: string,
    paramType: NodeType,
    paramImplicitValue: Node,
    paramDataTypeValue: DataType,
    paramTypeGenericIdent: Node,
    pTypeName: string,
    isMutable: bool,
    meta: Meta
  ]
  
  DataType* = enum
    typeNone = "none"
    typeNil = "nil"
    typeVoid = "void"
    typeInt = "int"
    typeString = "string"
    typeFloat = "float"
    typeBool = "bool"
    typeStream = "stream"
    typeArray = "array"
    typeObject = "object"
    typeFunction = "function"
    typeBlock = "block"
    typeHtmlElement = "html"
    typeAny = "any"
    typeIdentifier

  TypeDefintionObjectField* = tuple[
    fieldType: DataType,
    fieldTypeName: string,
    fieldTypeImpl: Node   # an implicit `Node` value, when available
  ]

  TypeDefinition* = ref object
    typeName*: string
    case dataType*: DataType
    of typeInt, typeString, typeBool, typeFloat:
      discard
    of typeArray:
      # arraySize*: uint
      arrayType*: DataType
        ## `typeAny` allows creates a mixed array
    of typeObject:
      objectType*: OrderedTableRef[string, TypeDefintionObjectField]
    else: discard # todo

  ObjectStorage* = OrderedTableRef[string, Node]
  
  VisibilityType* = enum
    vtPrivate
      ## Default for all definitions. Marks definitions
      ## as private so it can be used outside of the module
    vtProtected
      ## Any block, function, variable or type definition
      ## suffixed with `**` is marked as protected.
      ## Which makes the definition publicly available
      ## for internal use. This may be useful for packages
      ## to share components
    vtPublic
      ## Definitions suffixed with a single `*`
      ## results in a public definition

  Node* {.acyclic.} = ref object
    ## Part of the compiler's abstract syntax tree
    ## **Important** do not initialize this object directly
    case nt*: NodeType
    of ntHtmlElement:
      tag*: HtmlTag
      stag*: string
      attrs*: HtmlAttributes
        # used to store html attributes
      nodes*: seq[Node]
      htmlMultiplyBy*: Node # ntLitInt or a callable that returns ntLitInt
      htmlAttributes*: seq[Node]
    of ntHtmlAttribute:
      attrName*: string
      attrValue*: Node
    of ntVariableDef:
      varName*: string
        ## variable identifier
      varValue*: Node
        ## the value of a variable
      varValueType*: TypeDefinition
      # varType*: NodeType
      varImmutable*: bool
        ## enabled when a variable is defined as `const`
    of ntAssignExpr:
      asgnIdent*: Node
        ## an ntIdent identifier name
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
    of ntParGroupExpr:
      groupExpr*: Node
    of ntConditionStmt:
      condIfBranch*: ConditionBranch
        ## the `if` branch of a conditional statement
      condElifBranch*: seq[ConditionBranch]
        ## a sequence of `elif` branches
      condElseBranch*: Node # ntStmtList
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
      loopBody*: Node # ntStmtList
    of ntWhileStmt:
      whileExpr*: Node # ntIdent or ntInfixExpr
      whileBody*: Node # ntStmtList
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
      objectItems*: ObjectStorage
        ## Ordered table of Nodes for object storage
    of ntCommandStmt:
      cmdType*: CommandType
        ## type of given command, either `echo` or `return`
      cmdValue*: Node
        ## the node value of the command 
    of ntIdentVar:
      identVarName*: string
      identVarSafe*: bool
    of ntIdent, ntBlockIdent:
      identName*: string
        # identifier name
      identSafe*: bool
        # whether to escape the stored value of `identName`
      identArgs*: seq[Node]
    of ntComponent:
      ## Generate a custom element via JavaScript. A Tim component
      ## inherits from the standard `HTMLElement` class
      componentIdent*: string
      componentName*: string
        ## The name of a custom element must contain a dash.
        ##  So <x-tags>, <my-element>, and <my-awesome-app> are all
        ## valid names, while <tabs> and <foo_bar> are not.
        ## This requirement is so the HTML parser can distinguish
        ## custom elements from regular elements. It also ensures
        ## forward compatibility when new tags are added to HTML
      componentConnected*: Node
        ## Called each time the component is added
        ## to the document. The specification recommends that,
        ## as far as possible, developers should implement custom
        ## element setup in this callback rather than the constructor
      componentDisconnected*: Node
        ## Called each time the element is removed
        ## from the document
      componentAdopted*: Node
        ## Called each time the element is moved to
        ## a new document
      componentAttributeChanged*: Node
        ## Called when attributes are changed,
        ## added, removed, or replaced
      componentObservedAttributes: seq[string]
        ## Elements can react to attribute changes by defining a
        ## `componentAttributeChanged`. The browser will call this
        ## method for every change to attributes listed in the
        ## `componentObservedAttributes` sequence
      componentBody*: Node # ntStmtList
    of ntTypeDef:
      typeExport*: VisibilityType
      typeIdent*: string
      typeStructDef*: TypeDefinition
        ## Holds a custom `TypeDefinition` object
      typeStruct*: OrderedTableRef[string, (DataType, string)]
    of ntEscape:
      escapeIdent*: Node # ntIdent
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
    of ntFunction, ntBlock:
      fnIdent*: Node
        ## an `ntIdent` node to identify the function
      fnParams*: OrderedTableRef[string, FnParam]
        ## an ordered table containing the function parameters
      fnBody*: Node # ntStmtList
        ## the function body
      fnReturnType*: NodeType
        ## the return type of a function
        ## if a function has no return type, then `ntUnknown`
        ## is used as default (void)
      fnReturnHtmlElement*: HtmlTag
      fnFwdDecl*, fnExport*, fnAnon*: bool
      fnType*: FunctionType
      fnSource*: string
      fnLazyScope*: ScopeTable
    of ntJavaScriptSnippet,
      ntYamlSnippet, ntJsonSnippet:
        snippetId*, snippetCode*: string
        snippetCodeAttrs*: seq[(string, Node)]
          ## string-based snippet code for either
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
      clientBind*: Node # ntDoBlock
    of ntStmtList:
      stmtList*: seq[Node]
        ## A sequence of `Node` in a statement list
    of ntDoBlock:
      doBlockCode*: string
      ## optionally, `@client` and `block` can be followed
      ## by `@do` block, which allows for fast JavaScript bindings
    of ntRuntimeCode:
      runtimeCode*: string
    of ntReference:
      refNode*, refValue*: Node
    else: discard
    meta*: Meta

  Meta* = array[3, int]
  
  ScopeTable* = ref object
    ## ScopeTable is used to store variables,
    ## functions and blocks
    data*: OrderedTable[Hash, seq[Node]]
    variables*: OrderedTable[Hash, Node]
      ## an ordered table of Node, here
      ## we'll store variable declarations
    functions*, blocks*: OrderedTable[Hash, Node]
      ## an ordered table of seq[Node] where we store 
      ## all functions and blocks.

  TimPartialsTable* = TableRef[string, (Ast, seq[cli.Row])]
  TimModulesTable* = TableRef[string, Ast]

  Ast* {.acyclic.} = ref object
    ## The main structure of the Abstract Syntax Tree
    ## used to store created Nodes, partials
    ## and modules.
    src*: string
      ## the source path of the ast
    nodes*: seq[Node]
      ## a seq containing tree nodes 
    partials*: TimPartialsTable
      ## AST trees from included partials 
    modules*: TimModulesTable
      ## AST trees from imported modules
    forwardDeclarations*: OrderedTableRef[string, seq[Node]] = newOrderedTable[string, seq[Node]]()
    jit*: bool
      ## whether the current AST requires JIT compliation or not

const
  ntAssignableSet* =
    {ntLitString, ntLitInt, ntLitFloat, ntLitBool}
  ntAssignables* = ntAssignableSet + {ntLitObject, ntLitArray}

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
  # Compile-time proc to transform x `NimNode` to `NodeType`
  expectKind x, nnkBracketExpr
  if x[0].eqIdent("Node"):
    if x[1].eqIdent("ntLitString"):
      return ntLitString
    if x[1].eqIdent("ntLitInt"):
      return ntLitInt
    if x[1].eqIdent("ntLitFloat"):
      return ntLitFloat
    if x[1].eqIdent("ntLitBool"):
      return ntLitBool
    if x[1].eqIdent("ntLitObject"):
      return ntLitObject
    if x[1].eqIdent("ntLitArray"):
      return ntLitArray
    result = ntUnknown

proc toString*(node: JsonNode): string =
  if node == nil: return "null"
  result =
    case node.kind
    of JString: node.str
    of JInt:    $node.num
    of JFloat:  $node.fnum
    of JBool:   $node.bval
    of JObject, JArray: $(node)
    else: "null"

proc toString*(node: Node): string =
  if likely(node != nil):
    result =
      case node.nt
      of ntLitString: node.sVal
      of ntLitInt:    $node.iVal
      of ntLitFloat:  $node.fVal
      of ntLitBool:   $node.bVal
      of ntStream: toString(node.streamContent)
      else: ""

#
# AST to JSON convertors
#
# proc `$`*(node: Node): string =
#   {.gcsafe.}:
#     when not defined release:
#       pretty(toJson(node), 2)
#     else:
#       toJson(node)

proc printAstNodes*(x: Ast): string =
  {.gcsafe.}:
    when not defined release:
      $(toJson(x.nodes))
    else:
      toJson(x.nodes)

proc `$`*(x: Ast): string =
  {.gcsafe.}:
    when not defined release:
      pretty(toJson(x), 2)
    else:
      toJson(x)

when not defined release:
  proc debugEcho*(node: Node) {.gcsafe.} =
    {.gcsafe.}:
      echo pretty(toJson(node), 2)

  proc debugEcho*(nodes: seq[Node]) {.gcsafe.} =
    {.gcsafe.}:
      echo pretty(toJson(nodes), 2)
else:
  proc debugEcho*(node: Node) {.gcsafe.} =
    static:
      warning("`debugEcho` has no effect when building with `release` flag")

  proc debugEcho*(nodes: seq[Node]) {.gcsafe.} =
    static:
      warning("`debugEcho` has no effect when building with `release` flag")

#
# AST Generators
#
proc trace*(tk: TokenTuple): Meta =
  result = [tk.line, tk.pos, tk.col]

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
  result.asgnIdent = newNode(ntIdent, tk)
  result.asgnIdent.identName = tk.value
  result.asgnVal = varValue

proc newAssignment*(ident, varValue: Node): Node =
  ## Create a new assignment Node
  result = newNode(ntAssignExpr)
  result.asgnIdent = ident
  result.asgnVal = varValue
  result.meta = ident.meta

proc newFunction*(tk: TokenTuple, ident: Node): Node =
  ## Create a new Function definition Node
  result = newNode(ntFunction, tk)
  result.fnIdent = ident

proc newFunction*(tk: TokenTuple): Node =
  ## Create a new anonymous function definition Node
  result = newNode(ntFunction, tk)
  result.fnAnon = true

proc newCall*(tk: TokenTuple): Node =
  ## Create a new function call Node
  result = newNode(ntIdent, tk)
  result.identName = tk.value

proc newComponent*(tk: TokenTuple): Node =
  ## Create a new Component node
  result = ast.newNode(ntComponent, tk)
  result.componentIdent = tk.value

proc newBlockIdent*(tk: TokenTuple): Node =
  ## Create a new macro call Node
  result = newNode(ntBlockIdent, tk)
  result.identName = tk.value

proc newStmtList*(tk: TokenTuple): Node =
  ## Create a new statement Node
  result = newNode(ntStmtList, tk) 

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

proc newIdent*(tk: TokenTuple): Node =
  result = newNode(ntIdent, tk)
  result.identName = tk.value

proc newIdentVar*(tk: TokenTuple): Node =
  result = newNode(ntIdentVar, tk)
  result.identVarName = tk.value

proc newHtmlElement*(tag: HtmlTag, tk: TokenTuple): Node =
  result = newNode(ntHtmlElement, tk)
  result.tag = tag
  case tag
  of tagUnknown:
    result.stag = tk.value
  else: discard

proc newHtmlAttribute*(name: sink string, value: Node, tk: TokenTuple): Node =
  result = newNode(ntHtmlAttribute, tk)
  result.attrName = name
  result.attrValue = value

proc newCondition*(condIfBranch: ConditionBranch, tk: TokenTuple): Node =
  result = newNode(ntConditionStmt, tk)
  result.condIfBranch = condIfBranch

proc newArray*(items: seq[Node] = @[]): Node =
  ## Creates a new `Array` node
  result = newNode(ntLitArray)
  result.arrayItems = items

proc newObject*(fields: OrderedTableRef[string, Node]): Node =
  ## Creates a new `Object` node
  result = newNode(ntLitObject)
  if fields != nil:
    result.objectItems = fields

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

proc getDefaultValue*(dt: DataType): Node =
  case dt
  of typeString:
    ast.newString(newStringOfCap(0))
  of typeInt:
    ast.newInteger(0)
  of typeFloat:
    ast.newFloat(0.0)
  of typeBool:
    ast.newBool(false)
  of typeArray:
    ast.newArray()
  of typeObject:
    ast.newObject(nil)
  else:
    nil

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