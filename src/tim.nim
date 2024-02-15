# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim
import std/json except `%*`
import std/times

import pkg/[watchout]
import pkg/kapsis/cli

import tim/engine/[meta, parser, logging]
import tim/engine/compilers/html

from std/strutils import `%`, indent
from std/os import `/`

const
  DOCKTYPE = "<!DOCKTYPE html>"
  defaultLayout = "base"

proc jitCompiler*(engine: TimEngine, tpl: TimTemplate, data: JsonNode): HtmlCompiler =
  ## Compiles `tpl` AST at runtime
  newCompiler(engine.readAst(tpl), tpl, engine.isMinified(), engine.getIndentSize(), data)

proc displayErrors(l: Logger) =
  for err in l.errors:
    display(err)
  display(l.filePath)

proc compileCode*(engine: TimEngine, tpl: TimTemplate, refreshAst = false) =
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

proc precompile*(engine: TimEngine, callback: TimCallback = nil,
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
        # if not tpl.isUsed(): return # prevent compiling tpl if not in use
        case tpl.getType
        of ttView, ttLayout:
          engine.compileCode(tpl)
          if engine.errors.len > 0:
            for err in engine.errors:
              echo err
        else: discard

      # Callback `onChange`
      proc onChange(file: watchout.File) =
        # Runs when detecting changes
        let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
        # echo tpl.isUsed()
        # if not tpl.isUsed(): return # prevent compiling tpl if not in use
        echo "✨ Changes detected"
        echo indent(file.getName() & "\n", 3)
        # echo toUnix(getTime())
        case tpl.getType()
        of ttView, ttLayout:
          engine.compileCode(tpl)
          if engine.errors.len > 0:
            for err in engine.errors:
              echo err
        else:
          for path in tpl.getDeps:
            let deptpl = engine.getTemplateByPath(path)
            engine.compileCode(deptpl, refreshAst = true)
            if engine.errors.len > 0:
              for err in engine.errors:
                echo err

      # Callback `onDelete`
      proc onDelete(file: watchout.File) =
        # Runs when deleting a file
        echo "✨ Deleted\n", file.getName()
        engine.clearTemplateByPath(file.getPath())

      var w = newWatchout(@[engine.getSourcePath() / "*"], onChange,
        onFound, onDelete, recursive = true, ext = @["timl"])
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
    data["global"] = global
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