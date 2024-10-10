# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/json except `%*`
import std/[times, asyncdispatch,
  sequtils, macros, macrocache, strutils, os]

import pkg/watchout
import pkg/importer/resolver
import pkg/kapsis/cli

import timpkg/engine/[meta, parser, logging, std]
import timpkg/engine/compilers/html

from timpkg/engine/ast import `$`

# from std/strutils import `%`, indent, split, parseInt, join

const
  DOCKTYPE = "<!DOCKTYPE html>"
  defaultLayout = "base"
  localStorage* = CacheSeq"LocalStorage"
    # Compile-time Cache seq to handle local data

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

proc jitCompiler(engine: TimEngine,
    tpl: TimTemplate, data: JsonNode,
    placeholders: TimEngineSnippets = nil): HtmlCompiler =
  ## Compiles `tpl` AST at runtime
  engine.newCompiler(
    ast = engine.readAst(tpl),
    tpl = tpl,
    minify = engine.isMinified,
    indent = engine.getIndentSize,
    data = data,
    placeholders = placeholders
  )

proc toHtml*(name, code: string, local = newJObject(), minify = true): string =
  ## Read timl from `code` string 
  let p = parseSnippet(name, code)
  if likely(not p.hasErrors):
    var data = newJObject()
    data["local"] = local
    let c = newCompiler(
      ast = parser.getAst(p),
      minify,
      data = data
    )
    if likely(not c.hasErrors):
      return c.getHtml()
    raise newException(TimError, "c.logger.errors.toSeq[0]") # todo
  raise newException(TimError, "p.logger.errors.toSeq[0]") # todo

proc toAst*(name, code: string): string =
  let p = parseSnippet(name, code)
  if likely(not p.hasErrors):
    return ast.printAstNodes(parser.getAst(p))

when not defined release:
  when not defined napibuild:
    proc showHtmlError(msg: var string, engine: TimEngine, l: Logger) =
      var timErrorScreen = """
    style: "
    #timEngineErrorScreenWrapper {
      font-family: system-ui,-apple-system,'Segoe UI',Roboto,'Helvetica Neue','Noto Sans','Liberation Sans',Arial,sans-serif,'Apple Color Emoji','Segoe UI Emoji','Segoe UI Symbol','Noto Color Emoji';
      background-color: #111;
      color: #fff;
      position: fixed;
      top:0;
      left:0;
      width: 100%;
      height: 100%;
      display: flex;
    }

    #timEngineErrorScreenWrapper * {
      box-sizing: border-box;
    }

    header.timEngineErrorScreenHeader {
      background: #111;
      padding: 25px
    }

    header.timEngineErrorScreenHeader h1 {
      font-size: 48px;
      margin: 0;
    }

    .tim--error-container {
      width: 100%;
      padding:0 1.5rem;
      margin: auto;
      align-self: center;
    }

    .tim--error-row {
      display: flex;
      flex-wrap: wrap;
      margin:0 -1.5rem
    }

    .tim--error-row>* {
      flex-shrink: 0;
      width: 100%;
      max-width: 100%;
    }

    .tim-error-preview-code {
      background: #212121;
      overflow-x: auto;
      font-size: 16px;
      font-family: ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,Liberation Mono,Courier New,monospace;
    }
    .tim-error-preview-code li:before {
      content: attr(data-lineno)
    }
    .tim-error-preview-code li {
      list-style: none;
      min-height: 29px;
      line-height: 29px;
      text-wrap: nowrap;
    }

    .tim--error-li-msg {
      font-family: ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,Liberation Mono,Courier New,monospace;
      font-size: 16px;
      list-style: decimal;
      background-color: #ea4444a1;
      border-radius: 5px;
      padding: 2px 10px;
      margin-bottom: 10px;
      text-align: left;
    }

    .tim-error-preview-code li:last-child {
      border-bottom: 0
    }
    "
    section#timEngineErrorScreenWrapper > div.tim--error-container
      div.tim--error-row style="align-items: center"
        div style="text-align:center; align-self:center; max-width:650px; margin:auto;"
          img width="200" height="200"
              alt="Tim Engine"
              src="https://raw.githubusercontent.com/openpeeps/tim/main/.github/timengine.png"
          header.timEngineErrorScreenHeader
            h1 style="font-weight:bold;margin-bottom:20px": "Oups! Something broke"
  """
      var errmsgs: string
      for e in l.errors:
        let lc = e[1].text[1..^2].split(":")
        var ln = parseInt(lc[0])
        var txt = e[1].text
        add txt, e[2].text.indent(1)
        add txt, indent(e[3..^1].mapIt(it.text).join(" "), 1)
        add errmsgs, indent("li.tim--error-li-msg: \"$1\"", 10)
        errmsgs = errmsgs % [txt]
      add timErrorscreen, errmsgs
      msg = toHtml("tim-engine-error", timErrorScreen)
    var htmlerror: string

template displayErrors(l: Logger) =
  for err in l.errors:
    display(err)
  display(l.filePath)
  when not defined release:
    when not defined napibuild:
      if engine.showHtmlErrors:
        htmlerror.showHtmlError(engine, l)

proc compileCode(engine: TimEngine, tpl: TimTemplate,
    refreshAst = false) =
  # Compiles `tpl` TimTemplate to either `.html` or binary `.ast`
  var p: Parser = engine.newParser(tpl, refreshAst = refreshAst)
  if likely(not p.hasError):
    if tpl.jitEnabled():
      # if marked as JIT will save the produced
      # binary AST on disk for runtime computation
      engine.writeAst(tpl, parser.getAst(p))
    else:
      # otherwise, compiles the generated AST and save
      # a pre-compiled HTML version on disk
      var c = engine.newCompiler(parser.getAst(p),
          tpl, engine.isMinified, engine.getIndentSize)
      if likely(not c.hasError):
        case tpl.getType:
        of ttView:
          engine.writeHtml(tpl, c.getHtml)
        of ttLayout:
          engine.writeHtml(tpl, c.getHead)
          engine.writeHtmlTail(tpl, c.getTail)
        else: discard
      else:
        c.logger.displayErrors()
  else: p.logger.displayErrors()

proc resolveDependants(engine: TimEngine, x: seq[string]) =
  for path in x:
    let tpl = engine.getTemplateByPath(path)
    case tpl.getType
    of ttPartial:
      echo tpl.getDeps.toSeq
      engine.resolveDependants(tpl.getDeps.toSeq)
    else:
      engine.compileCode(tpl, refreshAst = true)

proc precompile*(engine: TimEngine, flush = true,
    waitThread = false, browserSyncPort = Port(6502),
    browserSyncDelay = 200, global: JsonNode = newJObject(), watchoutNotify = true) =
  ## Precompiles available templates inside `layouts` and `views`
  ## directories to either static `.html` or binary `.ast`.
  ## 
  ## Enable `flush` option to delete outdated generated
  ## files (enabled by default).
  ## 
  ## Enable filesystem monitor by compiling with `-d:timHotCode` flag.
  ## You can create a separate thread for precompiling templates
  ## (use `waitThread` to keep the thread alive)
  if flush: engine.flush()
  engine.setGlobalData(global)
  engine.importsHandle = resolver.initResolver()
  when defined timHotCode:
    # Define callback procs for pkg/watchout
    proc notify(label, fname: string) =
      if watchoutNotify:
        echo label
        echo indent(fname & "\n", 3)

    # Callback `onFound`
    proc onFound(file: watchout.File) =
      # Runs when detecting a new template.
      let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
      # if not tpl.isUsed(): return # prevent compiling tpl if not in use
      case tpl.getType
      of ttView, ttLayout:
        engine.compileCode(tpl)
      else: discard

    # Callback `onChange`
    proc onChange(file: watchout.File) =
      # Runs when detecting changes
      let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
      notify("✨ Changes detected", file.getName())
      case tpl.getType()
      of ttView, ttLayout:
        # engine.importsHandle.excl(file.getPath())
        engine.compileCode(tpl)
      else:
        # engine.importsHandle.excl(file.getPath())
        engine.resolveDependants(engine.importsHandle.dependencies(file.getPath).toSeq)

    # Callback `onDelete`
    proc onDelete(file: watchout.File) =
      # Runs when deleting a file
      notify("✨ Deleted", file.getName())
      engine.clearTemplateByPath(file.getPath())

    let basepath = engine.getSourcePath()
    let watcher =
      newWatchout(
        dirs = @[basepath / "layouts" / "*",
                basepath / "views" / "*",
                basepath / "partials" / "*"],
        onChange, onFound, onDelete,
        recursive = true,
        ext = @[".timl"],
        delay = browserSyncDelay,
        browserSync =
          WatchoutBrowserSync(
            port: browserSyncPort,
            delay: browserSyncDelay
          )
        )
    watcher.start() # watch for file changes in a separate thread
  else:
    for tpl in engine.getViews():
      engine.compileCode(tpl)
    for tpl in engine.getLayouts():
      engine.compileCode(tpl)

template layoutWrapper(getViewBlock) {.dirty.} =
  result = DOCKTYPE
  var layoutTail: string
  var hasError: bool
  if not layout.jitEnabled:
    # when requested layout is pre-rendered
    # will use the static HTML version from disk
    add result, layout.getHtml()
    getViewBlock
    layoutTail = layout.getTail()
  else:
    var jitLayout = engine.jitCompiler(layout, data, placeholders)
    if likely(not jitLayout.hasError):
      add result, jitLayout.getHead()
      getViewBlock
      layoutTail = jitLayout.getTail()
    else:
      hasError = true
      jitLayout.logger.displayErrors()
  when not defined release:
    if engine.showHtmlErrors and hasError:
      when not defined napibuild:
        add result, htmlerror
        htmlerror = ""
  add result, layoutTail

proc render*(engine: TimEngine, viewName: string,
    layoutName = defaultLayout, local = newJObject(),
    placeholders: TimEngineSnippets = nil): string =
  ## Renders a view based on `viewName` and `layoutName`.
  ## Exposing data from controller to the current template is possible
  ## using the `local` object.
  if engine.hasView(viewName):
    var
      view: TimTemplate = engine.getView(viewName)
      data: JsonNode = newJObject()
    data["local"] = local
    if likely(engine.hasLayout(layoutName)):
      var layout: TimTemplate = engine.getLayout(layoutName)
      if not view.jitEnabled:
        # render a pre-compiled HTML
        layoutWrapper:
          add result, view.getHtml()
          # add result,
          #   if engine.isMinified:
          #     view.getHtml()
          #   else:
          #     indent(view.getHtml(), layout.getViewIndent)
      else:
        # compile and render template at runtime
        layoutWrapper:
          var jitView = engine.jitCompiler(view, data, placeholders)
          if likely(not jitView.hasError):
            add result, jitView.getHtml
            # add result,
            #   if engine.isMinified:
            #     jitView.getHtml()
            #   else:
            #     indent(jitView.getHtml(), layout.getViewIndent)
          else:
            jitView.logger.displayErrors()
            hasError = true
    else:
      raise newException(TimError, "Trying to wrap `" & viewName & "` view using non-existing layout " & layoutName)
  else:
    raise newException(TimError, "View not found " & viewName)

when defined napibuild:
  # Setup for building TimEngine as a node addon via NAPI
  import pkg/[denim, jsony]
  # import std/os
  # from std/sequtils import toSeq

  var timjs: TimEngine
  init proc(module: Module) =
    proc init(src: string, output: string,
        basepath: string, minify: bool, indent: int) {.export_napi.} =
      ## Initialize TimEngine Engine
      timjs = newTim(
        args.get("src").getStr,
        args.get("output").getStr,
        args.get("basepath").getStr,
        args.get("minify").getBool,
        args.get("indent").getInt
      )

    proc precompile(opts: object) {.export_napi.} =
      ## Precompile TimEngine templates
      var opts: JsonNode = jsony.fromJson($(args.get("opts")))
      var globals: JsonNode
      if opts.hasKey"data":
        globals = opts["data"]
      var browserSync: JsonNode
      if opts.hasKey"watchout":
        browserSync = opts["watchout"]
      let browserSyncPort = browserSync["port"].getInt
      timjs.flush() # each precompilation will flush old files
      timjs.setGlobalData(globals)
      timjs.importsHandle = initResolver()
      if browserSync["enable"].getBool:
        # Define callback procs for pkg/watchout
        proc notify(label, fname: string) =
          echo label
          echo indent(fname & "\n", 3)

        # Callback `onFound`
        proc onFound(file: watchout.File) =
          # Runs when detecting a new template.
          let tpl: TimTemplate = timjs.getTemplateByPath(file.getPath())
          case tpl.getType
          of ttView, ttLayout:
            timjs.compileCode(tpl)
          else: discard

        # Callback `onChange`
        proc onChange(file: watchout.File) =
          # Runs when detecting changes
          let tpl: TimTemplate = timjs.getTemplateByPath(file.getPath())
          notify("✨ Changes detected", file.getName())
          case tpl.getType()
          of ttView, ttLayout:
            timjs.compileCode(tpl)
          else:
            timjs.resolveDependants(timjs.importsHandle.dependencies(file.getPath).toSeq)

        # Callback `onDelete`
        proc onDelete(file: watchout.File) =
          # Runs when deleting a file
          notify("✨ Deleted", file.getName())
          timjs.clearTemplateByPath(file.getPath())

        let basepath = timjs.getSourcePath()
        var w =
          newWatchout(
            dirs = @[basepath / "layouts" / "*",
                basepath / "views" / "*",
                basepath / "partials" / "*"],
            onChange, onFound, onDelete,
            recursive = true,
            ext = @[".timl"], delay = 200,
            browserSync =
              WatchoutBrowserSync(port: Port(browserSyncPort),
                delay: browserSync["delay"].getInt)
            )
        # start filesystem monitor in a separate thread
        w.start()
      else:
        for tpl in timjs.getViews():
          timjs.compileCode(tpl)
        for tpl in timjs.getLayouts():
          timjs.compileCode(tpl)

    proc render(view: string, layout: string, local: object) {.export_napi.} =
      ## Render a `view` by name
      var local: JsonNode = jsony.fromJson($(args.get("local")))
      let x = timjs.render(
          args.get("view").getStr,
          args.get("layout").getStr,
          local
        )
      return %*(x)

    proc fromHtml(path: string) {.export_napi.} =
      ## Read Tim code from `path` and output minified HTML
      let path = $args.get("path")
      let p = parseSnippet(path.extractFilename, readFile(path))
      if likely(not p.hasErrors):
        let c = newCompiler(parser.getAst(p), true)
        return %*c.getHtml()

    proc toHtml(name: string, code: string) {.export_napi.} =
      ## Transpile `code` to minified HTML
      let
        name = $args.get("name")
        code = $args.get("code")
        p = parseSnippet(name, code)
      if likely(not p.hasErrors):
        let c = newCompiler(parser.getAst(p), true)
        return %*c.getHtml()

elif not isMainModule:
  # Expose Tim Engine API for Nim development
  # as a Nimble library
  import std/enumutils
  import timpkg/engine/ast
  
  export ast, parser, html, json, stdlib
  export meta except TimEngine
  export localModule, SourceCode, Arg, NodeType

  proc initLocalModule(modules: NimNode): NimNode =
    result = newStmtList()
    var functions: seq[string]
    modules.expectKind nnkArgList
    for mblock in modules[0]:
      mblock.expectKind nnkBlockStmt
      for m in mblock[1]:
        case m.kind
        of nnkProcDef:
          let id = m[0]
          var fn = "fn " & $m[0] & "*("
          var fnReturnType: NodeType
          var params: seq[string]
          if m[3][0].kind != nnkEmpty:
            for p in m[3][1..^1]:
              add params, $p[0] & ":" & $p[1]
            add fn, params.join(",")
            add fn, "): "
            fnReturnType = ast.getType(m[3][0])
            add fn, $fnReturnType
          else:
            add fn, ")"
          add functions, fn
          var lambda = nnkLambda.newTree(newEmptyNode(), newEmptyNode(), newEmptyNode())
          var procParams = newNimNode(nnkFormalParams)
          procParams.add(
            ident("Node"),
            nnkIdentDefs.newTree(
              ident("args"),
              nnkBracketExpr.newTree(
                ident("openarray"),
                ident("Arg")
              ),
              newEmptyNode()
            ),
            nnkIdentDefs.newTree(
              ident("returnType"),
              ident("NodeType"),
              ident(symbolName(ntLitString))
            )
          )
          add lambda, procParams
          add lambda, newEmptyNode()
          add lambda, newEmptyNode()
          add lambda, m[6]
          let callableName = id.strVal
          let callableId = callableName[0] & toLowerAscii(callableName[1..^1])
          add result, 
            newAssignment(
              nnkBracketExpr.newTree(
                ident"localModule", newLit(callableId)
              ),
              lambda
            )
        else:
          add result, m
    add result,
      newAssignment(
        nnkBracketExpr.newTree(
          ident("stdlib"),
          newLit("*")
        ),
        nnkTupleConstr.newTree(
          ident("localModule"),
          newCall(ident("SourceCode"), newLit(functions.join("\n")))
        )
      )

  macro initModule*(x: varargs[untyped]): untyped =
    initLocalModule(x)

else:
  # Build Tim Engine as a standalone CLI application
  import pkg/kapsis
  import pkg/kapsis/[runtime, cli]
  import timpkg/app/[astCmd, srcCmd, reprCmd]
  #import timpkg/app/[jitCmd, pkgCmd, vmCmd]

  commands:
    -- "Source-to-Source"
    src string(-t), path(`timl`), string(-o),
      ?json(--data),    # pass data to global/local scope
      bool(--pretty),   # pretty print output HTML
      bool(--nocache),  # tells Tim to not cache packages
      bool("--json-errors"):
        ## Transpile `timl` to a target source

    ast path(`timl`), filename(`output`):
      ## Generate binary AST from a `timl` file

    repr path(`ast`), string(`ext`), bool(--pretty):
      ## Read from a binary AST to target source

    # -- "Microservice"
    # # run path(`config`):
    # #   ## Run Tim as a Microservice application
    # # bundle path(`ast`):
    # #   ## Produce binary dynamic templates (dll) from AST. Requires Nim
    # analyze path(`timl`):
    #   ## Performs a static analyze
    # run:
    #   ## Run a Tim Engine Virtual Machine through a UNIX socket

    # -- "Development"
    # install url(`pkg`):
    #   ## Install a package from remote source
    # uninstall string(`pkg`):
    #   ## Uninstall a package from local source
