# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim
import std/json except `%*`
import std/[times, options, asyncdispatch, sequtils]

import pkg/[watchout, httpx, websocketx]
import pkg/kapsis/cli

import tim/engine/[meta, parser, logging]
import tim/engine/compilers/html

from std/strutils import `%`, indent
from std/os import `/`, sleep

const
  DOCKTYPE = "<!DOCKTYPE html>"
  defaultLayout = "base"

proc jitCompiler(engine: TimEngine,
    tpl: TimTemplate, data: JsonNode): HtmlCompiler =
  ## Compiles `tpl` AST at runtime
  engine.newCompiler(
    engine.readAst(tpl), tpl, engine.isMinified,
    engine.getIndentSize, data
  )

proc displayErrors(l: Logger) =
  for err in l.errors:
    display(err)
  display(l.filePath)

proc compileCode(engine: TimEngine, tpl: TimTemplate,
    refreshAst = false) =
  # Compiles `tpl` TimTemplate to either `.html` or binary `.ast`
  var p: Parser = engine.newParser(tpl, refreshAst = refreshAst)
  if likely(not p.hasError):
    if tpl.jitEnabled():
      # when enabled, will save a cached ast
      # to disk for runtime computation. 
      engine.writeAst(tpl, p.getAst)
    else:
      # otherwise, compiles the generated AST and save
      # a pre-compiled HTML version on disk
      var c = engine.newCompiler(p.getAst, tpl, engine.isMinified,
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
  else:
    p.logger.displayErrors()

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
      # echo tpl.getDeps.toSeq
      # echo tpl.getSourcePath
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
          # if engine.errors.len > 0:
          #   for err in engine.errors:
          #     echo err
        else: discard

      # Callback `onChange`
      proc onChange(file: watchout.File) =
        # Runs when detecting changes
        let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
        notify("✨ Changes detected", file.getName())
        case tpl.getType()
        of ttView, ttLayout:
          engine.compileCode(tpl)
          # if engine.errors.len > 0:
          #   for err in engine.errors:
          #     echo err
          # else:
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
      jitLayout.logger.displayErrors()
  add result, layoutTail

proc render*(engine: TimEngine, viewName: string,
    layoutName = defaultLayout, global, local = newJObject()): string =
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
    else:
      raise newException(TimError, "No layouts available")
  else:
    raise newException(TimError, "View not found: `$1`" % [viewName])

when defined napibuild:
  # Setup for building TimEngine as a node addon via NAPI
  import pkg/denim
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

    proc precompileSync() {.export_napi.} =
      ## Precompile TimEngine templates
      timjs.precompile(flush = true, waitThread = false)

    proc renderSync(view: string) {.export_napi.} =
      ## Render a `view` by name
      let x = timjs.render(args.get("view").getStr)
      return %*(x)

elif not isMainModule:
  # Expose Tim Engine API for Nim development (as a Nimble librayr)
  export parser, html, json
  export meta except TimEngine
# else:
#   # Build Tim Engine as a standalone CLI application
#   import pkg/kapsis
#   import ./tim/app/[runCommand]

#   App:
#     about:
#       "Tim Engine CLI application"
#     commands:
#       --- "Main Commands"
#       $ run