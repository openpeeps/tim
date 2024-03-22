# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim
import std/json except `%*`
import std/[times, options, asyncdispatch,
  sequtils, macros, macrocache, htmlgen]

import pkg/[watchout, httpx, websocketx]
import pkg/kapsis/cli

import tim/engine/[meta, parser, logging]
import tim/engine/compilers/html

from std/strutils import `%`, indent, split, parseInt, join
from std/os import `/`, sleep

from std/xmltree import escape

const
  DOCKTYPE = "<!DOCKTYPE html>"
  defaultLayout = "base"

const localStorage* = CacheSeq"LocalStorage"

macro initCommonStorage*(x: untyped) =
  ## Initializes a common localStorage that can be
  ## shared between controllers
  if x.kind == nnkStmtList:
    add localStorage, x[0]
  elif x.kind == nnkTableConstr:
    add localStorage, x
  else: error("Invalid common storage initializer. Use `{}`, or `do` block")

template `&*`*(n: untyped): untyped =
  ## Compile-time localStorage initializer
  ## that helps reusing shareable data.
  ## 
  ## Once merged it calls `%*` macro from `std/json`
  ## for converting NimNode to JsonNode
  macro toLocalStorage(x: untyped): untyped =
    if x.kind in {nnkTableConstr, nnkCurly}:
      var shareLocalNode: NimNode
      if localStorage.len > 0:
        shareLocalNode = localStorage[0]
      if x.len > 0:
        shareLocalNode.copyChildrenTo(x)
        return newCall(ident("%*"), x)
      if shareLocalNode != nil:
        return newCall(ident("%*"), shareLocalNode)
      return newCall(ident("%*"), newNimNode(nnkCurly))
    error("Local storage requires either `nnkTableConstr` or `nnkCurly`")
  toLocalStorage(n)

proc jitCompiler(engine: TimEngine,
    tpl: TimTemplate, data: JsonNode): HtmlCompiler =
  ## Compiles `tpl` AST at runtime
  engine.newCompiler(
    engine.readAst(tpl), tpl, engine.isMinified,
    engine.getIndentSize, data
  )

proc toHtml*(name, code: string): string =
  let p = parseSnippet(name, code)
  if likely(not p.hasErrors):
    let c = newCompiler(parser.getAst(p), false)
    return c.getHtml()

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

    .tim--error-col-8 {
      flex: 0 0 auto;
      width: 56.66666667%;
    }

    .tim--error-col-4 {
      flex: 0 0 auto;
      width: 43.33333333%;
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
    }

    .tim-error-preview-code li:last-child {
      border-bottom: 0
    }
    "
    section#timEngineErrorScreenWrapper > div.tim--error-container
      div.tim--error-row style="align-items: center"
  """
      add timErrorScreen, """
        div.tim--error-col-4
          header.timEngineErrorScreenHeader:
            h1 style="font-weight:bold;margin-bottom:20px": "Ugh! Something broke"
  """
      var rightSide: string
      for e in l.errors:
        let lc = e[1].text[1..^2].split(":")
        var ln = parseInt(lc[0])
        var txt = e[1].text
        add txt, e[2].text.indent(1)
        add txt, indent(e[3..^1].mapIt(it.text).join(" "), 1)
        add rightSide, indent("li.tim--error-li-msg: \"$1\"", 10)
        rightSide = rightSide % [txt]
      add timErrorscreen, rightSide
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
      # when enabled, will save a cached ast
      # to disk for runtime computation. 
      engine.writeAst(tpl, parser.getAst(p))
    else:
      # otherwise, compiles the generated AST and save
      # a pre-compiled HTML version on disk
      var c = engine.newCompiler(parser.getAst(p), tpl, engine.isMinified,
          engine.getIndentSize)
      if likely(not c.hasError):
        case tpl.getType:
        of ttView:
          engine.writeHtml(tpl, c.getHtml)
        of ttLayout:
          engine.writeHtml(tpl, c.getHead)
          engine.writeHtmlTail(tpl, c.getTail)
        else: discard
      else: c.logger.displayErrors()
  else: p.logger.displayErrors()

var sync: Thread[(Port, int)]
var lastModified, prevModified: Time

proc browserSync(x: (Port, int)) {.thread.} =
  proc onRequest(req: Request) {.async.} =
    if req.httpMethod == some(HttpGet):
      case req.path.get()
      of "/":
        req.send("Hello, Hello!") # todo a cool page here?
      of "/ws":
        try:
          var ws = await newWebSocket(req)
          while ws.readyState == Open:
            if lastModified > prevModified:
              # our JS snippet listens on `message`, so once
              # we have an update we can just send an empty string.
              # connecting to Tim's WebSocket via JS:
              #   const watchout = new WebSocket('ws://127.0.0.1:6502/ws');
              #   watchout.addEventListener('message', () => location.reload());
              await ws.send("")
              ws.close()
              prevModified = lastModified
            sleep(x[1])
        except WebSocketClosedError:
          echo "Socket closed"
        except WebSocketProtocolMismatchError:
          echo "Socket tried to use an unknown protocol: ", getCurrentExceptionMsg()
        except WebSocketError:
          req.send(Http404)
      else: req.send(Http404)
    else: req.send(Http503)
  let settings = initSettings(x[0], numThreads = 1)
  httpx.run(onRequest, settings)

proc resolveDependants(engine: TimEngine, x: seq[string]) =
  for path in x:
    let tpl = engine.getTemplateByPath(path)
    case tpl.getType
    of ttPartial:
      echo tpl.getDeps.toSeq
      engine.resolveDependants(tpl.getDeps.toSeq)
    else:
      engine.compileCode(tpl, refreshAst = true)
      # if engine.errors.len > 0:
      #   for err in engine.errors:
      #     echo err
      # else:
      lastModified = getTime()

proc precompile*(engine: TimEngine, callback: TimCallback = nil,
    flush = true, waitThread = false, browserSyncPort = Port(6502),
    browserSyncDelay = 550, global: JsonNode = newJObject(), watchoutNotify = true) =
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
  when not defined release:
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
          engine.compileCode(tpl)
          lastModified = getTime()
        else:
          engine.resolveDependants(tpl.getDeps.toSeq)

      # Callback `onDelete`
      proc onDelete(file: watchout.File) =
        # Runs when deleting a file
        notify("✨ Deleted", file.getName())
        engine.clearTemplateByPath(file.getPath())

      var w = newWatchout(@[engine.getSourcePath() / "*"], onChange,
        onFound, onDelete, recursive = true, ext = @["timl"], delay = 200)
      # start browser sync server in a separate thread
      createThread(sync, browserSync, (browserSyncPort, browserSyncDelay))
      # start filesystem monitor in a separate thread
      w.start(waitThread)
    else:
      for tpl in engine.getViews():
        engine.compileCode(tpl)
      for tpl in engine.getLayouts():
        engine.compileCode(tpl)
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
    var jitLayout = engine.jitCompiler(layout, data)
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
    layoutName = defaultLayout, local = newJObject()): string =
  ## Renders a view based on `viewName` and `layoutName`.
  ## Exposing data to a template is possible using `global` or
  ## `local` objects.
  if engine.hasView(viewName):
    var
      view: TimTemplate = engine.getView(viewName)
      data: JsonNode = newJObject()
    # data["global"] = global # todo merge global data
    data["local"] = local
    if likely(engine.hasLayout(layoutName)):
      var layout: TimTemplate = engine.getLayout(layoutName)
      if not view.jitEnabled:
        # render a pre-compiled HTML
        layoutWrapper:
          add result, indent(view.getHtml(), layout.getViewIndent)
      else:
        # compile and render template at runtime
        layoutWrapper:
          var jitView = engine.jitCompiler(view, data)
          if likely(not jitView.hasError):
            add result, indent(jitView.getHtml(), layout.getViewIndent)
          else:
            jitView.logger.displayErrors()
            hasError = true
    else:
      raise newException(TimError, "No layouts available")
  else:
    raise newException(TimError, "View not found: `$1`" % [viewName])

when defined napibuild:
  # Setup for building TimEngine as a node addon via NAPI
  import pkg/[denim, jsony]
  from std/sequtils import toSeq

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

    proc precompile(globals: object) {.export_napi.} =
      ## Precompile TimEngine templates
      var globals: JsonNode = jsony.fromJson($(args.get("globals")))
      timjs.precompile(flush = true, global = globals, waitThread = false)

    proc render(view: string, layout: string, local: object) {.export_napi.} =
      ## Render a `view` by name
      var local: JsonNode = jsony.fromJson($(args.get("local")))
      let x = timjs.render(
          args.get("view").getStr,
          args.get("layout").getStr,
          local
        )
      return %*(x)

elif not isMainModule:
  # Expose Tim Engine API for Nim development (as a Nimble librayr)
  export parser, html, json
  export meta except TimEngine

else:
  # Build Tim Engine as a standalone CLI application
  discard # todo
#   import pkg/kapsis
#   import ./tim/app/[runCommand]

#   App:
#     about:
#       "Tim Engine CLI application"
#     commands:
#       --- "Main Commands"
#       $ run