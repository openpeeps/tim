# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import std/tables

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
        NTHtmlElement
        NTStatement
        NTConditionStmt
        NTForStmt
        NTMixinStmt
        NTPrefixStmt
        NTInfixStmt
        NTIncludeCall
        NTMixinCall
        NTMixinDef
        NTLet
        NTVar
        NTVariable
        NTIdentifier
        NTView

    HtmlNodeType* = enum
        Html_Doctype
        Html_A
        Html_Abbr
        Html_Acronym
        Html_Address
        Html_Applet
        Html_Area
        Html_Article
        Html_Aside
        Html_Audio
        Html_B
        Html_Base
        Html_Basefont
        Html_Bdi
        Html_Bdo
        Html_Big
        Html_Blockquote
        Html_Body
        Html_Br
        Html_Button
        Html_Canvas
        Html_Caption
        Html_Center
        Html_Cite
        Html_Code
        Html_Col
        Html_Colgroup
        Html_Data
        Html_Datalist
        Html_Dd
        Html_Del
        Html_Details
        Html_Dfn
        Html_Dialog
        Html_Dir
        Html_Div
        Html_Dl
        Html_Dt
        Html_Em
        Html_Embed
        Html_Fieldset
        Html_Figcaption
        Html_Figure
        Html_Font
        Html_Footer
        Html_Form
        Html_Frame
        Html_Frameset
        Html_H1
        Html_H2
        Html_H3
        Html_H4
        Html_H5
        Html_H6
        Html_Head
        Html_Header
        Html_Hr
        Html_Html
        Html_I
        Html_Iframe
        Html_Img
        Html_Input
        Html_Ins
        Html_Kbd
        Html_Label
        Html_Legend
        Html_Li
        Html_Link
        Html_Main
        Html_Map
        Html_Mark
        Html_Meta
        Html_Meter
        Html_Nav
        Html_Noframes
        Html_Noscript
        Html_Object
        Html_Ol
        Html_Optgroup
        Html_Option
        Html_Output
        Html_P
        Html_Param
        Html_Pre
        Html_Progress
        Html_Q
        Html_Rp
        Html_RT
        Html_Ruby
        Html_S
        Html_Samp
        Html_Script
        Html_Section
        Html_Select
        Html_Small
        Html_Source
        Html_Span
        Html_Strike
        Html_Strong
        Html_Style
        Html_Sub
        Html_Summary
        Html_Sup
        Html_Textarea
    
    OperatorType* {.pure.} = enum
        None
        EQ          = "=="
        NE          = "!="
        GT          = ">"
        GTE         = ">="
        LT          = "<"
        LTE         = "<="
        AND         = "&"   # used for string concatenation
    
    HtmlAttributes* = Table[string, seq[string]]
    IfBranch* = tuple[cond: Node, body: seq[Node]]
    ElifBranch* = seq[IfBranch]
    MetaNode* = tuple[line, pos, col, wsno: int]
    ParamTuple* = tuple[key, value, typeSymbol: string, `type`: NodeType]
    
    AccessorKind* {.pure.} = enum
        None, Key, Value

    Node* = ref object
        nodeName*: string
        case nodeType*: NodeType
        of NTInt: 
            iVal*: int
        of NTFloat:
            fVal*: float
        of NTString:
            sVal*: string
        of NTBool:
            bVal*: bool
        of NTConditionStmt:
            ifCond*: Node
            ifBody*, elseBody*: seq[Node]
            elifBranch*: ElifBranch
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
            isSafeVar*: bool
            dataStorage*: bool
            case accessorKind*: AccessorKind
            of Key:
                byKey*: string
            else: nil
        else: nil
        meta*: MetaNode

    Program* = object
        nodes*: seq[Node]

proc newNode*(nt: NodeType, tk: TokenTuple): Node =
    result = Node(nodeName: nt.symbolName, nodeType: nt)
    result.meta = (tk.line, tk.pos, tk.col, tk.wsno)

proc newExpression*(expression: Node): Node =
    ## Add a new `NTStmtList` expression node
    result = Node(
        nodeName: NTStmtList.symbolName,
        nodeType: NTStmtList,
        stmtList: expression
    )

proc newInfix*(infixLeft, infixRight: Node, infixOp: OperatorType): Node =
    ## Add a new `NTInfixStmt` node
    Node(
        nodeName: NTInfixStmt.symbolName,
        nodeType: NTInfixStmt,
        infixLeft: infixLeft,
        infixRight: infixRight,
        infixOp: infixOp,
        infixOpSymbol: infixOp.symbolName
    )

proc newInt*(iVal: int): Node =
    ## Add a new `NTInt` node
    Node(nodeName: NTInt.symbolName, nodeType: NTInt, iVal: iVal)

proc newBool*(bVal: bool): Node =
    ## Add a new `NTBool` node
    Node(nodeName: NTBool.symbolName, nodeType: NTBool, bVal: bVal)

proc newString*(tk: TokenTuple): Node =
    ## Add a new `NTString` node
    Node(
        nodeName: NTString.symbolName,
        nodeType: NTString,
        sVal: tk.value,
        meta: (tk.line, tk.pos, tk.col, tk.wsno)
    )

proc newHtmlElement*(tk: TokenTuple): Node =
    ## Add a new `NTHtmlElement` node
    Node(
        nodeName: NTHtmlElement.symbolName,
        nodeType: NTHtmlElement,
        htmlNodeName: tk.value,
        meta: (tk.line, tk.pos, tk.col, tk.wsno)
    )

proc newIfExpression*(ifBranch: IfBranch, tk: TokenTuple): Node =
    ## Add a mew Conditional node
    Node(
        nodeName: NTConditionStmt.symbolName,
        nodeType: NTConditionStmt,
        ifCond: ifBranch.cond,
        ifBody: ifBranch.body,
        meta: (tk.line, tk.pos, tk.col, tk.wsno)
    )

proc newMixin*(tk: TokenTuple): Node =
    ## Add a new `NTMixinCall` node
    Node(nodeName: NTMixinCall.symbolName, nodeType: NTMixinCall, mixinIdent: tk.value)

proc newMixinDef*(tk: TokenTuple): Node = 
    Node(nodeName: NTMixinDef.symbolName, nodeType: NTMixinDef, mixinIdentDef: tk.value)

proc newView*(tk: TokenTuple): Node =
    Node(nodeName: NTView.symbolName, nodeType: NTView, meta: (tk.line, tk.pos, tk.col, tk.wsno))

proc newInclude*(ident: string): Node =
    ## Add a new `NTIncludeCall` node
    Node(nodeName: NTIncludeCall.symbolName, nodeType: NTIncludeCall, includeIdent: ident)

proc newFor*(itemVarIdent, itemsVarIdent: Node, body: seq[Node], tk: TokenTuple): Node =
    ## Add a new `NTForStmt` node
    result = newNode(NTForStmt, tk)
    result.forBody = body
    result.forItem = itemVarIdent
    result.forItems = itemsVarIdent

proc newVariable*(tk: TokenTuple, isSafeVar, dataStorage = false, varType = NTString): Node =
    ## Add a new `NTVariable` node
    result = newNode(NTVariable, tk)
    result.varIdent = tk.value
    result.varSymbol = "$" & tk.value
    result.isSafeVar = isSafeVar
    result.dataStorage = dataStorage
    result.varType = varType

proc newVarCallKeyAccessor*(tk: TokenTuple, fid: string): Node =
    result = Node(
        nodeName: NTVariable.symbolName,
        nodeType:  NTVariable,
        accessorKind: Key,
        byKey: fid,
        varIdent: tk.value,
        varSymbol: "$" & tk.value,
        meta: (tk.line, tk.pos, tk.col, tk.wsno)
    )

proc newVarCallValAccessor*(tk: TokenTuple): Node =
    result = Node(
        nodeName: NTVariable.symbolName,
        nodeType:  NTVariable,
        accessorKind: Value,
        varIdent: tk.value,
        varSymbol: "$" & tk.value,
        meta: (tk.line, tk.pos, tk.col, tk.wsno)
    )
