# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, strutils, sequtils, json, critbits]
import pkg/[zmq, watchout, jsony]
import pkg/kapsis/[cli]

import ./config
import ../engine/[meta, parser, logging]
import ../engine/compilers/[html, nimc]

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
    case config.target
    of tsHtml:
      # When `HTML` is the preferred target source
      # Tim Engine will run as a microservice app in background
      # powered by Zero MQ. The pre-compiled templates are stored
      # in a Cache table for when rendering is needed.
      # echo engine.getTargetSourcePath(tpl, config.output, $config.target)
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
        else:
          c.logger.displayErrors()
      # Cache[tpl.getHash()] = c.getHtml().strip
    of tsNim:
      let c = nimc.newCompiler(parser.getAst(p))
      writeFile(engine.getTargetSourcePath(tpl, config.output, $config.target), c.exportCode())
    else: discard
  else: p.logger.displayErrors()

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

proc precompile(engine: TimEngine, config: TimConfig, globals: JsonNode) =
  ## Pre-compiles available templates
  engine.setGlobalData(globals)
  proc notify(label, fname: string) =
    echo label
    echo indent(fname & "\n", 3)

  # Callback `onFound`
  proc onFound(file: watchout.File) =
    # Runs when detecting a new template.
    let tpl: TimTemplate =
        engine.getTemplateByPath(file.getPath())
    case tpl.getType
    of ttView, ttLayout:
      engine.transpileCode(tpl, config)
    else: discard

  # Callback `onChange`
  proc onChange(file: watchout.File) =
    # Runs when detecting changes
    let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
    notify("✨ Changes detected", file.getName())
    case tpl.getType()
    of ttView, ttLayout:
      engine.transpileCode(tpl, config)
    else:
      engine.resolveDependants(tpl.getDeps.toSeq, config)

  # Callback `onDelete`
  proc onDelete(file: watchout.File) =
    # Runs when deleting a file
    notify("✨ Deleted", file.getName())
    engine.clearTemplateByPath(file.getPath())

  var watcher =
    newWatchout(
      @[engine.getSourcePath() / "*"],
      onChange, onFound, onDelete,
      recursive = true,
      ext = @["timl"], delay = config.sync.delay,
      browserSync =
        WatchoutBrowserSync(
          port: config.sync.port,
          delay: config.sync.delay
        )
      )
  # watch for file changes in a separate thread
  watcher.start(config.target != tsHtml)

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

proc render(engine: TimEngine, viewName, layoutName: string, local = newJObject()): string =
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

proc run*(engine: var TimEngine, config: TimConfig) =
  config.output = normalizedPath(engine.getBasePath / config.output)
  case config.target
  of tsHtml:
    display("Tim Engine is running at " & address)
    var rep = listen(address, mode = REP)
    var hasGlobalStorage: bool
    defer: rep.close()
    while true:
      let req = rep.receiveAll()
      try:
        let command = req[0]
        case command
        of "render":
          let local = req[3].fromJson
          let output = engine.render(req[1], req[2], local)
          rep.send(output)
        of "global.storage": # runs once
          if not hasGlobalStorage:
            let globals = req[1].fromJson
            engine.precompile(config, globals)
            hasGlobalStorage = true
            rep.send("")
          else:
            rep.send("")
        else: discard # unknown command error ?
      except TimError as e:
        rep.send(e.msg)
      sleep(10)
  else:
    discard existsOrCreateDir(config.output / "views")
    discard existsOrCreateDir(config.output / "layouts")
    discard existsOrCreateDir(config.output / "partials")
    display("Tim Engine is running Source-to-Source")
    engine.precompile(config, newJObject())
