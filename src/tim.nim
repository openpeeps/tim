# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim
import std/json except `%*`
import std/times

import tim/engine/[meta, parser, compiler, logging]
import pkg/[watchout, kapsis/cli]

from std/strutils import `%`, indent
from std/os import `/`


const
  DOCKTYPE = "<!DOCKTYPE html>"
  defaultLayout = "base"

proc jitCompiler*(engine: Tim, tpl: TimTemplate, data: JsonNode): HtmlCompiler =
  ## Compiles `tpl` AST at runtime
  newCompiler(engine.readAst(tpl), tpl, engine.isMinified(), engine.getIndentSize(), data)

proc displayErrors(l: Logger) =
  for err in l.errors:
    display(err)
  display(l.filePath)

proc compileCode*(engine: Tim, tpl: TimTemplate, refreshAst = false) =
  # Compiles `tpl` TimTemplate to either `.html` or binary `.ast`
  var tplView: TimTemplate 
  if tpl.getType == ttView: 
    tplView = tpl
  var p: Parser = engine.newParser(tpl, tplView, refreshAst = refreshAst)
  if likely(not p.hasError):
    if tpl.jitEnabled():
      # when enabled, will save the generated binary ast
      # to disk for runtime computation. 
      engine.writeAst(tpl, p.getAst)
    else:
      # otherwise, compiles the generated AST and save
      # a pre-compiled HTML version on disk
      var c = newCompiler(p.getAst, tpl, engine.isMinified, engine.getIndentSize)
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

proc precompile*(engine: Tim, callback: TimCallback = nil,
    flush = true, waitThread = false) =
  ## Precompiles available templates inside `layouts` and `views`
  ## directories to either static `.html` or binary `.ast`.
  ## 
  ## Partials are not part of the precompilation processs. These
  ## are include-only files that can be imported into layouts
  ## or views via `@import` statement.
  ## 
  ## Note: Enable `flush` option to delete outdated files
  if flush: engine.flush()
  when not defined release:
    when defined timHotCode:
      var watchable: seq[string]
      # Define callback procs for pkg/watchout
      # Callback `onFound`
      proc onFound(file: watchout.File) =
        # Runs when detecting a new template.
        let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
        case tpl.getType
        of ttView, ttLayout:
          engine.compileCode(tpl)
          if engine.errors.len > 0:
            for err in engine.errors:
              echo err
            # setLen(engine.errors, 0)
        else: discard
      # Callback `onChange`
      proc onChange(file: watchout.File) =
        # Runs when detecting changes
        echo "✨ Changes detected"
        echo indent(file.getName() & "\n", 3)
        # echo toUnix(getTime())
        let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
        case tpl.getType()
        of ttView, ttLayout:
          engine.compileCode(tpl)
          if engine.errors.len > 0:
            for err in engine.errors:
              echo err
        else:
          for path in tpl.getDeps:
            let deptpl = engine.getTemplateByPath(path)
            # echo indent($(ttView) / deptpl.getName(), 4)
            engine.compileCode(deptpl, refreshAst = true)
            if engine.errors.len > 0:
              for err in engine.errors:
                echo err
      # Callback `onDelete`
      proc onDelete(file: watchout.File) =
        # Runs when deleting a file
        echo "✨ Deleted\n", file.getName()
        engine.clearTemplateByPath(file.getPath())

      var w = newWatchout(@[engine.getSourcePath() / "*"], onChange, onFound, onDelete)
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

proc render*(engine: Tim, viewName: string,
    layoutName = defaultLayout, global, local = newJObject()): string =
  ## Renders a view based on `viewName` and `layoutName`.
  ## Exposing data to a template is possible using `global` or
  ## `local` objects.
  if engine.hasView(viewName):
    var view: TimTemplate = engine.getView(viewName)
    var data: JsonNode = newJObject()
    if likely(engine.hasLayout(layoutName)):
      var layout: TimTemplate = engine.getLayout(layoutName)
      if not view.jitEnabled:
        # render a pre-compiled HTML
        result = DOCKTYPE
        add result, layout.getHtml()
        add result, indent(view.getHtml(), layout.getViewIndent)
        add result, layout.getTail()
      else:
        # compile and render template at runtime
        var data = newJObject()
        data["global"] = global
        data["local"] = local
        result = DOCKTYPE
        var layoutTail: string
        if not layout.jitEnabled:
          # when requested layout is pre-rendered
          # will use the static HTML version from disk
          add result, layout.getHtml()
          layoutTail = layout.getTail()
        else:
          var clayout = engine.jitCompiler(layout, data)
          if likely(not clayout.hasError):
            add result, clayout.getHtml()
            layoutTail = clayout.getTail()
          else:
            clayout.logger.displayErrors()
        var cview = engine.jitCompiler(view, data)
        if likely(not cview.hasError):
          add result, indent(cview.getHtml(), layout.getViewIndent)
        else:
          cview.logger.displayErrors()
        add result, layoutTail
    else:
      raise newException(TimError, "No layouts available")
  else:
    raise newException(TimError, "View not found: `$1`" % [viewName])

when defined napibuild:
  # Setup for building Tim as a node addon via NAPI
  import pkg/denim
  from std/sequtils import toSeq

  var timjs: Tim
  init proc(module: Module) =
    proc init(src: string, output: string,
        basepath: string, minify: bool, indent: int) {.export_napi.} =
      ## Initialize Tim Engine
      timjs = newTim(
        args.get("src").getStr,
        args.get("output").getStr,
        args.get("basepath").getStr,
        args.get("minify").getBool,
        args.get("indent").getInt
      )

    proc precompileSync() {.export_napi.} =
      ## Precompile Tim templates
      timjs.precompile(flush = true, waitThread = false)

    proc renderSync(view: string) {.export_napi.} =
      ## Render a `view` by name
      let x = timjs.render(args.get("view").getStr)
      return %*(x)

elif not isMainModule:
  import tim/engine/[meta, parser, compiler, logging]

  export parser, compiler, json
  export meta except Tim