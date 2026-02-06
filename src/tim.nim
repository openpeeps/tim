# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

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

  extendCase:
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

  extendCaseStmt "codeGenStmt":
    case node.kind:
    of nkHtmlElement:
      # HTML element construction
      discard gen.htmlConstr(node)
    of nkJavaScriptSnippet:
      # JavaScript snippet construction
      # discard gen.storeJavaScript(node)
      discard

  extendModule "voodoo/src/voodoo/language/ast.nim":
    const voidHtmlElements* = [tagArea, tagBase, tagBr, tagCol,
      tagEmbed, tagHr, tagImg, tagInput, tagLink, tagMeta,
      tagParam, tagSource, tagTrack, tagWbr, tagCommand,
      tagKeygen, tagFrame]

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

  extendModule "voodoo/src/voodoo/language/codegen.nim":
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
              if returnType.tyKind != tyVoid:
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

when defined napi_build:
  # Building Tim Engine as a NAPI module
  # This allows Tim Engine to be used in Node.js/Bun.js applications

  import std/[strutils, json]
  import pkg/[denim, jsony, watchout]
  
  import ./tim/pm/initializer
  
  var timjs: TimEngine
  init proc(module: Module) =
    proc init(src: string, output: string, basepath: string) {.export_napi.} =
      ## Initialize Tim Engine
      timjs = newTim(
        args.get("src").getStr,
        args.get("output").getStr,
        args.get("basepath").getStr
      )
      timjs.precompile(firstRun = true)

    proc render(view: string, layout: string = "base"): string {.export_napi.} =
      ## Render a Tim Engine template based on the view and layout paths
      let
        layoutPath = args.get("layout").getStr
        layout = timjs.getLayout(layoutPath)
        
        viewPath = args.get("view").getStr
        view = timjs.getView(viewPath)

      return bindings.`%*`(evaluate(view, layout))

elif isMainModule:
  # Building Tim Engine as a CLI application
  import pkg/kapsis
  import pkg/kapsis/[runtime, cli]
  import ./tim/app/[build, dev]

  commands:
    #
    # Source to Source commands
    # Used to transpile `timl` code to a specific target source
    # Planning to support: HTML, Nim, JS, PHP, Python, Ruby and more
    #
    -- "Source to Source"
    src path(`timl`),
      string(--ext),       # choose a target (default target `html`)
      string(-o),       # save output to file
      ?json(--data),    # pass data to global/local scope
      bool(--nocache),  # tells Tim to import modules and rebuild cache
      bool(--bench):    # benchmark operations
        ## Transpile `timl` to specific target source
    
    ast path(`timl`):
      ## Transpile timl code to AST representation

    #
    # Development commands
    # Used to manage Tim Engine packages locally
    #
    -- "Development"
    init ?string(`pkg`):
      ## Init a new package
    install string(`pkg`):
      ## Install a package from remote source
    develop string(`pkg`):
      ## Create a symlink to a package in local source
    remove string(`pkg`):
      ## Remove a package from local source

else:
  # Importing Tim Engine as a Nimble library
  # so it can be used in other Nim projects
  import std/[macros, strutils, macrocache, json]

  import ./tim/pm/initializer
  export initializer

  const
    localStorage* = CacheSeq"LocalStorage"

  macro initCommonStorage*(x: untyped) =
    ## Initializes a common localStorage that can be
    ## shared between controllers
    if x.kind == nnkStmtList:
      add localStorage, x[0]
    elif x.kind == nnkTableConstr:
      add localStorage, x
    else: error("Invalid common storage initializer. Use `{}`, or `do` block")

  proc toLocalStorage*(x: NimNode): NimNode =
    if x.kind in {nnkTableConstr, nnkCurly}:
      var shareLocalNode: NimNode
      if localStorage.len > 0:
        shareLocalNode = localStorage[0]
      if x.len > 0:
        shareLocalNode.copyChildrenTo(x)
        return newCall(ident("%*"), x)
      if shareLocalNode != nil:
        return newCall(ident("%*"), shareLocalNode)
    result = newCall(ident"newJObject")
    # error("Local storage requires either `nnkTableConstr` or `nnkCurly`")

  macro `&*`*(n: untyped): untyped =
    ## Compile-time localStorage initializer
    ## that helps reusing shareable data.
    ## 
    ## Once merged it calls `%*` macro from `std/json`
    ## for converting NimNode to JsonNode
    result = toLocalStorage(n)

  proc flush*(engine: TimEngine) =
    ## Flush the Tim Engine cache
    discard # to be implemented

  proc render*(engine: TimEngine, view: string, layout: string = "base",
              data: JsonNode): string =
    ## Render a Tim Engine template based on the view and layout templates.
    ## 
    ## Optionally, you can pass a `JsonNode` object as data to be used
    ## within the template as local data available under the `$this` variable.
    ## 
    ## If no layout is provided, the default `base` layout will be used.
    ## 
    ## Raises a `TimEngineError` if the view or layout templates are not found.
    ## Ensure to handle these exceptions in your web server to respond
    ## with appropriate HTTP status codes (e.g., 404 or 500).
    let
      viewTpl: TimTemplate = engine.getView(view.replace(".", "/"))
      layoutTpl: TimTemplate = engine.getLayout(layout)
    
    if viewTpl == nil:
      raise newException(TimEngineError, "View template not found: " & view)

    if layoutTpl == nil:
      raise newException(TimEngineError, "Layout template not found: " & layout)
    return eval(viewTpl, layoutTpl, data, engine.globalData)
  