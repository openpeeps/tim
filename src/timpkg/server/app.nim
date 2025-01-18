# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, asyncdispatch, strutils,
  sequtils, json, critbits, options]

import pkg/[httpbeast, watchout, jsony]
import pkg/importer/resolver
import pkg/kapsis/cli

import ./config
import ../engine/[meta, parser, logging]
import ../engine/compilers/[html, nimc]

#
# Tim Engine Setup
#
type
  CacheTable = CritBitTree[string]

var Cache = CacheTable()
const
  address = "tcp://127.0.0.1:5559"
  DOCKTYPE = "<!DOCKTYPE html>"
  defaultLayout = "base"

template displayErrors(l: Logger) =
  for err in l.errors:
    display(err)
  display(l.filePath)

proc transpileCode(engine: TimEngine, tpl: TimTemplate,
    config: TimConfig, refreshAst = false) =
  ## Transpile `tpl` TimTemplate to a specific target source
  var p: Parser = engine.newParser(tpl, refreshAst = refreshAst)
  if likely(not p.hasError):
    if tpl.jitEnabled():
      # if marked as JIT will save the produced
      # binary AST on disk for runtime computation
      engine.writeAst(tpl, parser.getAst(p))
    else:
      # otherwise, compiles AST to static HTML
      var c = html.newCompiler(engine, parser.getAst(p), tpl,
        engine.isMinified, engine.getIndentSize)
      if likely(not c.hasError):
        case tpl.getType:
          of ttView:
            engine.writeHtml(tpl, c.getHtml)
          of ttLayout:
            engine.writeHtml(tpl, c.getHead)
          else: discard
      else: displayErrors c.logger
  else: displayErrors p.logger

proc resolveDependants(engine: TimEngine,
    deps: seq[string], config: TimConfig) =
  for path in deps:
    let tpl = engine.getTemplateByPath(path)
    case tpl.getType
    of ttPartial:
      echo tpl.getDeps.toSeq
      engine.resolveDependants(tpl.getDeps.toSeq, config)
    else:
      engine.transpileCode(tpl, config, true)

proc precompile(engine: TimEngine, config: TimConfig, globals: JsonNode = newJObject()) =
  ## Pre-compiles available templates
  engine.setGlobalData(globals)
  engine.importsHandle = resolver.initResolver()
  if not config.compilation.release:  
    proc onFound(file: watchout.File) =
      # Callback `onFound`
      # Runs when detecting a new template.
      let tpl: TimTemplate =
          engine.getTemplateByPath(file.getPath())
      case tpl.getType
      of ttView, ttLayout:
        engine.transpileCode(tpl, config)
      else: discard

    proc onChange(file: watchout.File) =
      # Callback `onChange`
      # Runs when detecting changes
      let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
      displayInfo("✨ Changes detected\n   " & file.getName())
      case tpl.getType()
      of ttView, ttLayout:
        engine.transpileCode(tpl, config)
      else:
        engine.resolveDependants(tpl.getDeps.toSeq, config)

    proc onDelete(file: watchout.File) =
      # Callback `onDelete`
      # Runs when deleting a file
      displayInfo("Deleted a template\n   " & file.getName())
      engine.clearTemplateByPath(file.getPath())

    var watcher =
      newWatchout(
        @[engine.getSourcePath() / "*"],
        onChange, onFound, onDelete,
        recursive = true,
        ext = @[".timl"],
        delay = config.browser_sync.delay,
        browserSync =
          WatchoutBrowserSync(
            port: config.browser_sync.port,
            delay: config.browser_sync.delay
          )
        )
    # watch for file changes in a separate thread
    watcher.start() # config.target != tsHtml
  else:
    discard

proc jitCompiler(engine: TimEngine,
    tpl: TimTemplate, data: JsonNode): HtmlCompiler =
  ## Compiles `tpl` AST at runtime
  html.newCompiler(
    engine,
    engine.readAst(tpl),
    tpl,
    engine.isMinified,
    engine.getIndentSize,
    data
  )

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
  add result, layoutTail

proc render*(engine: TimEngine, viewName: string, layoutName = "base", local = newJObject()): string =
  # Renders a `viewName`
  if likely(engine.hasView(viewName)):
    var
      view: TimTemplate = engine.getView(viewName)
      data: JsonNode = newJObject()
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
    raise newException(TimError, "View not found")

#
# Tim Engine - Server handle
#
from std/httpcore import HttpCode
proc startServer(engine: TimEngine) =
  proc onRequest(req: Request): Future[void] =
    {.gcsafe.}:
      req.send(200.HttpCode, engine.render("index"), "Content-Type: text/html")
  
  httpbeast.run(onRequest, initSettings(numThreads = 1))

proc run*(engine: var TimEngine, config: TimConfig) =
  ## Tim can serve the HTTP service with TCP or Unix socket.
  ## 
  ## **Note** By default, Unix socket would only be available to same user.
  ## If you want access it from Nginx, you need to loosen permissions.
  displayInfo("Preloading templates...")
  let globals = %*{} # todo
  engine.precompile(config, globals)
  displayInfo("Tim Engine Server is up & running")
  engine.startServer()