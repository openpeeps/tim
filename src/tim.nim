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

import tim/engine/[meta, parser, logging, std]
import tim/engine/compilers/html

from std/strutils import `%`, indent, split, parseInt, join
from std/os import `/`, sleep

from std/xmltree import escape
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

proc toHtml*(name, code: string, local = newJObject()): string =
  ## Read timl from `code` string 
  let p = parseSnippet(name, code)
  if likely(not p.hasErrors):
    var data = newJObject()
    data["local"] = local
    let c = newCompiler(parser.getAst(p), true, data = data)
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
      # when enabled, will save a cached ast
      # to disk for runtime computation. 
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
      # if engine.errors.len > 0:
      #   for err in engine.errors:
      #     echo err
      # else:

proc precompile*(engine: TimEngine, callback: TimCallback = nil,
    flush = true, waitThread = false, browserSyncPort = Port(6502),
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
        else:
          engine.resolveDependants(tpl.getDeps.toSeq)

      # Callback `onDelete`
      proc onDelete(file: watchout.File) =
        # Runs when deleting a file
        notify("✨ Deleted", file.getName())
        engine.clearTemplateByPath(file.getPath())

      var w =
        newWatchout(
          @[engine.getSourcePath() / "*"],
          onChange, onFound, onDelete,
          recursive = true,
          ext = @["timl"], delay = 200,
          browserSync =
            WatchoutBrowserSync(port: browserSyncPort,
              delay: browserSyncDelay)
          )
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
  import std/os
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
  import tim/engine/ast
  
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
            add fn, $m[3][0]
            fnReturnType = ast.getType(m[3][0])
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
                ident"localModule", newLit($id)
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
  import tim/app/[astCmd, compileCmd, reprCmd]

  commands:
    -- "Main Commands"
    c path(`timl`), string(`ext`), bool(-w), bool(--pretty):
      ## Transpile `.timl` file to a target source
    ast path(`timl`), filename(`output`):
      ## Generate binary AST from a `timl` file
    repr path(`ast`), string(`ext`), bool(--pretty):
      ## Read from a binary AST to target source