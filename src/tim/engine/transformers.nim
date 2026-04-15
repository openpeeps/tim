import std/os
import pkg/voodoo/extensibles

# Extend Voodoo AST and CodeGen to support
# HTML elements and other Tim Engine specific nodes
block extendVoodooAstAndCodeGen:
  extendEnum NodeKind:
    # Extend `NodeKind` enum to support HTML
    # elements and attributes in the AST
    nkHtmlElement
    nkHtmlAttribute
    nkJavaScriptSnippet
    nkViewLoader     # view loader using `@view` placeholder\
    nkClientBlock    # client block using `@client ... @end`
    nkMacro          # a block - {...}

  extendCase do:
    # Extend the Node variant to support HTML elements
    # attributes and JavaScript snippets
    type Node = ref object        # required by `extendCase`
      case kind: NodeKind
      # the branches we add to the Node variant
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

  # Extend the case statement by adding new branches
  # for code generation of the new node kinds we added to the AST
  #
  # Note that `case node.kind` is already defined in the original
  # `genStmt` procedure, the `extendCaseStmt` macro just allows us
  # to add new branches to it
  extendCaseStmt "codeGenStmt":
    case node.kind:
    of nkHtmlElement:
      # HTML element construction
      discard gen.htmlConstr(node)
    of nkJavaScriptSnippet:
      # JavaScript snippet construction
      let tag = "script"
      let tagPos = gen.chunk.getString(tag)
      gen.chunk.emit(opcBeginHtml)
      gen.chunk.emit(tagPos)
      discard gen.pushConst(ast.newStringLit(node.snippetCode))
      gen.chunk.emit(opcTextHtml)
      gen.chunk.emit(opcCloseHtml)
      gen.chunk.emit(tagPos)
    of nkMacro: discard gen.genMacro(node)

  # Extends the AST module with new node constructors and utilities
  # for HTML elements and macros
  extendModule "voodoo" / "language" / "ast.nim":
    const voidHtmlElements* = [tagArea, tagBase, tagBr, tagCol,
      tagEmbed, tagHr, tagImg, tagInput, tagLink, tagMeta,
      tagParam, tagSource, tagTrack, tagWbr, tagCommand,
      tagKeygen, tagFrame]

    proc newMacro*(children: varargs[Node]): Node =
      ## Construct a new block.
      newNode(nkMacro)

    proc newHtmlAttribute*(attrType: static HtmlAttributeType, attrNode: Node): Node =
      ## Construct a new HTML attribute node.
      result = Node(
        kind: nkHtmlAttribute,
        attrType: attrType,
        attrNode: attrNode
      )

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

    proc getTag*(node: Node): string =
      # Retrieves the HTML tag name from an HTML element node
      case node.tag
      of tagUnknown:
        result = node.tagCustom
      else:
        result = $node.tag

  extendModule "voodoo" / "language" / "codegen.nim":
    proc genMacro(node: Node, isInstantiation = false): Sym {.codegen.} =
      ## Generates code for a block of code that contains a procedure.
      if not isInstantiation and node[1].kind != nkEmpty:
        gen.pushScope()
      # get some basic metadata
      let
        name = node[0]
        formalParams = node[2]
        body = node[3]
        genericParams =
          if not isInstantiation:
            # collect generic params if we're not instantiating
            gen.collectGenericParams(node[1])
          else: none(seq[Sym])
        params = gen.collectParams(formalParams, genericParams)
        returnTy = # empty return type == void
          if formalParams[0].kind != nkEmpty:
            gen.lookup(formalParams[0])
          else:
            gen.module.sym"void"
      
      # create a new proc
      var (sym, theProc) =
            gen.script.newProc(name, impl = node,
                        params, returnTy, kind = pkNative, 
                        genKind = gen.kind)
      sym.genericParams = genericParams
      sym.procType = ProcType.procTypeMacro
      
      # add the proc into the declaration scope
      # we need to do this here, otherwise recursive calls will be broken
      gen.addSym(sym, scopeOffset = ord(sym.genericParams.isSome))

      # if we're in an instantiation or the proc is not generic, generate its code
      if not sym.isGeneric or isInstantiation:
        var
          chunk = newChunk(gen.chunk.file)
          procGen = initCodeGen(gen.script, gen.module, chunk, gkBlockProc,
            ctxAllocator =
              if gen.kind == gkToplevel: nil
              else: gen.ctxAllocator
          )
        theProc.chunk = chunk
        chunk.file = gen.chunk.file
        procGen.procReturnTy = returnTy

        # add the proc's parameters as locals
        # TODO: closures and upvalues
        procGen.pushScope()
        for (name, ty, implValTy, isMut, isOpt) in params:
          var varType = if isMut: skVar else: skLet
          let param = procGen.declareVar(name, varType, ty)
          param.varSet = true  # arguments are not assignable
        
        # todo
        # let stmtVar = procGen.declareVar(ast.newIdent("stmt"), skLet, gen.module.sym"any")
        # stmtVar.varSet = true
        # procGen.pushDefault(gen.module.sym"string")
        
        # define the default `attrs` variable
        # this is used to store the attributes of the block.
        let attrs = newIdent("attrs")
        procGen.declareVar(attrs, skVar, gen.module.sym"string", isMagic = true)
        procGen.pushDefault(gen.module.sym"string")
        procGen.popVar(attrs)
        
        # defines the default `blockStmt` variable
        # this is used to store any additional statements
        # provided at call time
        # let blockStmt = newIdent("blockStmt")
        # procGen.declareVar(blockStmt, skVar, gen.module.sym"any", isMagic = true)
        # procGen.popVar(blockStmt)

        # add the proc into the script
        gen.script.procs.add(theProc)
        if sym.procExport:
          gen.script.procsExport.add(theProc)

        # compile the proc's body
        discard procGen.genBlock(body, isStmt = true)

        # if the macro has any deferred code to be executed,
        # we need to emit it now.
        # procGen.chunk.emit(opcLoadDeferred)

        # finally, return ``result`` if applicable
        if returnTy.tyKind != ttyVoid:
          let resultSym = procGen.lookup(newIdent("result"))
          procGen.chunk.emit(opcPushL)
          procGen.chunk.emit(resultSym.varStackPos.uint8)
          procGen.chunk.emit(opcReturnVal)
        else:
          procGen.chunk.emit(opcReturnVoid)

      # pop the generic declaration scope
      if not isInstantiation and sym.isGeneric:
        gen.popScope()
      result = sym

    proc htmlConstr(node: Node): Sym {.codegen.} =
      # Constructs a new HTML element from Html object
      if gen.kind == gkProc:
        node.error(ErrOnlyUsableInAMacro % "HTML")
      let tag = node.getTag()
      let tagIdent = ast.newIdent(tag & "_" & $(gen.counter))
      let tagPos = gen.chunk.getString(tag)
      result = Sym(
        name: tagIdent,
        kind: skHtmlType,
        isVoidElement: node.tag in voidHtmlElements
      )
      if node.attributes.len > 0:
        gen.chunk.emit(opcBeginHtmlWithAttrs)
        gen.chunk.emit(tagPos)
        var classAttributes: seq[string]
        for attr in node.attributes:
          case attr.attrType:
          of htmlAttrClass:
            classAttributes.add(attr.attrNode.stringVal)
          of htmlAttrId:
            gen.chunk.emit(opcWSpace)
            gen.chunk.emit(opcAttrId)
            gen.chunk.emit(gen.chunk.getString(attr.attrNode.stringVal))
          of htmlAttr:
            if attr.attrNode.kind == nkInfix:
              gen.chunk.emit(opcWSpace) # add a space before the attribute
              discard gen.genExpr(attr.attrNode[2]) # value
              discard gen.genExpr(attr.attrNode[1]) # key
              gen.chunk.emit(opcAttr) # emit the attribute opcode
            else:
              # if the attribute is a simple identifier, we just emit it
              discard gen.genExpr(attr.attrNode)
              gen.chunk.emit(opcAttrKey)
          else: discard
        if classAttributes.len > 0:
          # if there are any classes, we emit them as a stringified value
          # TODO `--optimize` should enable deduplication of classes
          classAttributes = classAttributes.deduplicate()
          gen.chunk.emit(opcWSpace)
          gen.chunk.emit(opcAttrClass)
          gen.chunk.emit(gen.chunk.getString(classAttributes.join(" ")))
        gen.chunk.emit(opcAttrEnd)
      else:
        gen.chunk.emit(opcBeginHtml)
        gen.chunk.emit(tagPos)
      inc(gen.counter)

      if gen.kind == gkToplevel:
        gen.kind = gkHtmlNest

      if node.childElements.len > 0:
        gen.pushScope()
        for subNode in node.childElements:
          case subNode.kind
          of nkBool, nkInt, nkFloat, nkString:
            discard gen.pushConst(subNode)
            gen.chunk.emit(opcTextHtml)
          of nkIdent, nkDot, nkInfix, nkBracket:
            discard gen.genExpr(subNode)
            gen.chunk.emit(opcTextHtml)
          of nkCall:
            if subNode[0].ident[0] == '@':
              gen.chunk.emit(opcInnerHtml)
              gen.genStmt(subNode)
            else:
              let returnType: Sym = gen.genExpr(subNode)
              if returnType.tyKind != ttyVoid:
                # if the return type is not void, we emit it as text
                # so the returned value is rendered as text
                # inside the HTML element
                gen.chunk.emit(opcTextHtml)
          else:
            gen.chunk.emit(opcInnerHtml)
            gen.genStmt(subNode)
        gen.popScope()
      
      # add the generated symbol to the module
      if not result.isVoidElement:
        gen.chunk.emit(opcCloseHtml)
        gen.chunk.emit(tagPos)

      if gen.kind == gkHtmlNest:
        gen.kind = gkToplevel

  block extendVM:
    extendEnum Opcode:
      opcBeginHtml = "beginHtml"    ## construct HTML object
      opcBeginHtmlWithAttrs = "behinHtmlWithAttrs" ## construct HTML object with attributes
      opcAttrEnd = "attrEnd"        ## ends HTML object
      opcInnerHtml = "innerHtml"        ## ends HTML object
      opcTextHtml = "textHtml"      ## adds text to HTML object
      opcCloseHtml = "closeHtml"    ## closes HTML object

      opcAttrClass = "attrClass"    ## adds class to HTML object
      opcAttrId = "attrId"          ## adds id to HTML object
      opcAttr = "attr"
      opcAttrKey = "attrKey"        ## adds a key to HTML object attribute
      opcWSpace = "space"           ## adds whitespace to HTML result
    
    extendCaseStmt "vmParseChunkCase":
      case oc:
      of opcAttrClass, opcAttrId, opcBeginHtmlWithAttrs, opcBeginHtml, opcCloseHtml:
        let sid = readArg[uint16](pc)
        addOp(oc, sid.int64, 0, akString)
    
    extendCaseStmt "vmInterpretCase":
      case oc:
      # HTML generation
      of opcAttrClass:
        # special case for class attribute
        result.add("class=\"" & co.getArg1Str(pcIdx, currentChunk) & "\"")
      of opcAttrId:
        result.add("id=\"" & co.getArg1Str(pcIdx, currentChunk) & "\"")
      of opcWSpace:
        result.add(" ")
      of opcAttrEnd:
        result.add(">")
      of opcAttr:
        let key = stack.pop().stringVal[]
        let value = stack.pop()
        result.add(key & "=\"")
        case value.typeId
        of tyString: result.add(value.stringVal[])
        of tyInt:    result.add($value.intVal)
        of tyFloat:  result.add($value.floatVal)
        of tyBool:   result.add($(value.boolVal))
        of tyJsonStorage:
          result.add(value.jsonVal.toString())
        else: discard
        result.add("\"")
      of opcAttrKey:
        let attr = stack.pop()
        if attr.stringVal[].len > 0:
          result.add(" ") # leading space
          result.add(attr.stringVal[])
      of opcBeginHtmlWithAttrs:
        result.add("<" & co.getArg1Str(pcIdx, currentChunk))
      of opcBeginHtml:
        result.add("<" & co.getArg1Str(pcIdx, currentChunk) & ">")
      of opcTextHtml:
        let v = stack.pop()
        case v.typeId
        of tyString: result.add(v.stringVal[])
        of tyInt: result.add($v.intVal)
        of tyFloat: result.add($v.floatVal)
        of tyBool: result.add($(v.boolVal))
        of tyJsonStorage: result.add(v.jsonVal.toString())
        else: discard
      of opcInnerHtml:
        discard
      of opcCloseHtml:
        result.add("</" & co.getArg1Str(pcIdx, currentChunk) & ">")
