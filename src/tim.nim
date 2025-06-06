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

import timpkg/engine/[meta, parser, logging]
import timpkg/engine/compilers/html

from timpkg/engine/ast import `$`

when not isMainModule:
  import timpkg/engine/stdlib

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

template displayErrors(l: Logger) =
  for err in l.errors:
    display(err)
  display(l.filePath)

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

# initialize Browser Sync & Reload using
# libdatachannel WebSocket server and Watchout
# for handling file monitoring and changes
import pkg/libdatachannel/bindings
import pkg/libdatachannel/websockets

# needs to be global
var
  watcher: Watchout
  wsServerConfig = initWebSocketConfig()
  hasChanges: bool

proc connectionCallback(wsserver: cint, ws: cint, userPtr: pointer) {.cdecl.} =
  proc wsMessageCallback(ws: cint, msg: cstring, size: cint, userPtr: pointer) =
    if hasChanges:
      ws.message("1")
      hasChanges = false
    else:
      ws.message("0")
    
  discard rtcSetMessageCallback(ws, wsMessageCallback)

proc precompile*(engine: TimEngine, flush = true,
    waitThread = false, browserSyncPort = Port(6502),
    browserSyncDelay = 100, global: JsonNode = newJObject(),
    watchoutNotify = true) =
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
      hasChanges = true

    # Callback `onDelete`
    proc onDelete(file: watchout.File) =
      # Runs when deleting a file
      notify("✨ Deleted", file.getName())
      engine.clearTemplateByPath(file.getPath())

    wsServerConfig.port = browserSyncPort.uint16
    websockets.startServer(addr(wsServerConfig), connectionCallback)
    sleep(100) # give some time for the web socket server to start

    let basepath = engine.getSourcePath()
    # Setup the filesystem monitor
    watcher =
      newWatchout(@[
        basepath / "layouts" / "*",
        basepath / "views" / "*",
        basepath / "partials"  / "*"
      ], "*.timl")
    watcher.onChange = onChange
    watcher.onFound = onFound
    watcher.onDelete = onDelete
    watcher.start()
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
      # echo view.jitEnabled
      if not view.jitEnabled:
        # render a pre-compiled HTML
        layoutWrapper:
          # add result, view.getHtml()
          add result,
            if engine.isMinified:
              view.getHtml()
            else:
              indent(view.getHtml(), layout.getViewIndent)
      else:
        # compile and render template at runtime
        layoutWrapper:
          var jitView = engine.jitCompiler(view, data, placeholders)
          if likely(not jitView.hasError):
            # add result, jitView.getHtml
            add result,
              if engine.isMinified:
                jitView.getHtml()
              else:
                indent(jitView.getHtml(), layout.getViewIndent)
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

elif defined timSwig:
  # Generate C API for generating SWIG wrappers
  # import pkg/genny
  
  # proc init*(src, output: string; minifyOutput = false; indentOutput = 2): TimEngine =
  #   ## Initialize TimEngine
  #   result = newTim(src, output, "", minifyOutput, indentOutput)
  
  # exportRefObject TimEngine:
  #   procs:
  #     init
  #     precompile

  # writeFiles("bindings/generated", "tim")
  # include genny/internal
  # todo
  discard

elif not isMainModule:
  # Expose Tim Engine API for Nim development
  # as a Nimble library
  import std/[hashes, enumutils]
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
          var hashKey = stdlib.getHashedIdent(id.strVal)
          var fn = "fn " & $m[0] & "*("
          var fnReturnType: NodeType
          var params: seq[string]
          var paramsType: seq[DataType]
          if m[3][0].kind != nnkEmpty:
            for p in m[3][1..^1]:
              add params, $p[0] & ":" & $p[1]
              hashKey = hashKey !& hashIdentity(parseEnum[DataType]($p[1]))
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
          add result, 
            newAssignment(
              nnkBracketExpr.newTree(
                ident"localModule",
                newLit hashKey
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
  import timpkg/app/[source, microservice, manage]

  commands:
    -- "Source-to-Source"
    # Transpile timl code to a specific target source.
    # For now only `-t:html` works. S2S targets planned:
    # JavaScript, Nim, Python, Ruby and more
    src path(`timl`),
      string(-t),       # choose a target (default target `html`)
      string(-o),       # save output to file
      ?json(--data),    # pass data to global/local scope
      bool(--pretty),   # pretty print output HTML (still buggy)
      bool(--nocache),  # tells Tim to import modules and rebuild cache
      bool(--bench),    # benchmark operations
      bool("--json-errors"):
        ## Transpile `timl` to HTML

    ast path(`timl`), filename(`output`):
      ## Serialize template to binary AST

    repr path(`ast`), string(`ext`), bool(--pretty):
      ## Deserialize binary AST to target source

    html path(`html_file`):
      ## Transpile HTML to Tim code

    -- "Microservice"
    new path(`config`):
      ## Initialize a new config file

    run path(`config`):
      ## Run Tim as a Microservice application

    build path(`ast`):
      ## Build pluggable templates `dll` from `.timl` files. Requires Nim

    bundle path(`config`):
      ## Bundle a standalone front-end app from project. Requires Nim

    -- "Development"
    # The built-in package manager store installed packages
    init:
      ## Initializes a new Tim Engine package

    install url(`pkg`):
      ## Install a package from remote source

    remove string(`pkg`):
      ## Remove an installed package@0.1.0 by name and version
