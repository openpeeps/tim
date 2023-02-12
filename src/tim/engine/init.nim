# A high-performance compiled template engine inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import std/[tables, strutils, json]
import pkg/[pkginfo, jsony, klymene/cli]
import tim/engine/[meta, ast, parser, compiler]

export parser
export meta except TimEngine

const DockType = "<!DOCTYPE html>"
var Tim*: TimEngine
const DefaultLayout = "base"

when defined cli:
  import pkg/watchout
  from std/os import getCurrentDir
  from std/times import cpuTime

  proc newTimEngine*() =
    Tim.init(
      source = getCurrentDir() & "/../examples/templates",
      output = getCurrentDir() & "/../examples/storage",
      indent = 2,
      minified = true
    )

  proc compileCode(e: TimEngine, t: Template) =
    var p = e.parse(t.getSourceCode, t.getFilePath, templateType = t.getType)
    if p.hasError():
      e.errors = @[p.getError()]
      return
    var c = newCompiler(e, p.getStatements, t, e.shouldMinify, e.getIndent, t.getFilePath)
    if c.hasError():
      display t.getFilePath
      for err in c.getErrors():
        display err

  proc precompile*(e: TimEngine, callback: proc() {.gcsafe, nimcall.} = nil,
                  debug = false): seq[string] {.discardable.} =
    ## Pre-compile ``views`` and ``layouts``
    ## from ``.timl`` to HTML or BSON.
    ##
    ## Note that ``partials`` contents are collected on
    ## compile-time and merged within the view.
    if e.hasAnySources:
      # Will use `watchout` to watch for changes in `/templates` dir
      display "✨ Watching for changes..."
      proc watchoutCallback(file: watchout.File) {.closure.} =
        let initTime = cpuTime()
        display "✨ Changes detected"
        display file.getName(), indent = 3
        var timlTemplate = getTemplateByPath(e, file.getPath())
        if timlTemplate.isPartial:
          for depView in timlTemplate.getDependentViews():
            e.compileCode(getTemplateByPath(e, depView))
        else:
          e.compileCode(timlTemplate)
        display("Done in: $1" % [$(cpuTime() - initTime)])
        if callback != nil: # Run a custom callback, if available
          callback()

      var watchFiles: seq[string]
      for id, view in e.getViews().mpairs():
        e.compileCode(view)
        watchFiles.add view.getFilePath()
        result.add view.getName()
      
      for id, partial in e.getPartials().pairs():
        # Watch for changes in `partials` directory.
        watchFiles.add partial.getFilePath()

      for id, layout in e.getLayouts().mpairs():
        e.compileCode(layout)
        watchFiles.add layout.getFilePath()
        result.add layout.getName()

      # Start a new Thread with Watchout watching for live changes
      startThread(watchoutCallback, watchFiles, 450, shouldJoinThread = true)
    else: display("Can't find views")

else:
  when requires "watchout":
    import watchout
    from std/times import cpuTime

  var reloadHandler: string
  when requires "supranim":
    when not defined release:
      reloadHandler = "\n" & """
  <script type="text/javascript">
  document.addEventListener("DOMContentLoaded", function() {
    var connectionError = false
    var prevTime = localStorage.getItem("watchout") || 0
    function autoreload() {
      if(connectionError) {
        return;
      }
      fetch('/dev/live')
        .then(res => res.json())
        .then(body => {
          if(body.state == 0) return
          if(body.state > prevTime) {
            localStorage.setItem("watchout", body.state)
            location.reload()
          }
        }).catch(function() {
          connectionError = true
        });
      setTimeout(autoreload, 500)
    }
    autoreload();
  });
  </script>
  """

  proc newJIT(e: TimEngine, `template`: Template, data: JsonNode,
              viewCode = "", hasViewCode = false): Compiler =
    result = newCompiler(
      e = e,
      p = fromJson(e.readBson(`template`), Program),
      `template` = `template`,
      minify = e.shouldMinify,
      indent = e.getIndent,
      filePath = `template`.getFilePath,
      data = data,
      viewCode = viewCode,
      hasViewCode = hasViewCode
    )

  proc render*(e: TimEngine, viewName: string, layoutName = DefaultLayout,
              data, globals = %*{}): string =
    ## Renders a template view by name. Use dot notations
    ## for accessing views in sub directories,
    ## for example `render("product.sales.index")`
    ## will try look for a timl template at `product/sales/index.timl`
    if e.hasView viewName:
      let layoutName = 
        if e.hasLayout(layoutName):
          layoutName
        else: DefaultLayout
      var
        allData: JsonNode = %* {}
        view: Template = e.getView viewName
        layout: Template = e.getLayout(layoutName)
      
      if e.globalDataExists:
        allData.merge("globals", e.getGlobalData, globals)
      else:
        allData.merge("globals", %*{}, globals)
      allData.add("scope", data)
      result = DockType
      if view.isJitEnabled:
        # When enabled, will compile `timl` > `html` on the fly
        var cview = newJIT(e, view, allData)
        var clayout = newJIT(e, layout, allData, cview.getHtml & reloadHandler, hasViewCode = true)
        add result, clayout.getHtml
        if clayout.hasError:
          display("Warning:" & indent(layout.getFilePath, 1), br = "before")
          for err in clayout.getErrors:
            display(err, indent = 2)
        if cview.hasError:
          display("Warning:" & indent(view.getFilePath, 1), br = "before")
          for err in cview.getErrors:
            display(err, indent = 2)
      else:
        if layout.isJitEnabled:
          # Compile requested layout at runtime 
          let c = newJIT(e, layout, allData, view.getHtmlCode & reloadHandler, hasViewCode = true)
          add result, c.getHtml
          if c.hasError:
            display("Warning:" & indent(layout.getFilePath, 1), br = "before")
            for err in c.getErrors:
              display(err, indent = 2)
        else:
          # Otherwise get the precompiled HTML layout from memory
          # and resolve the `@view` placeholder using the current
          add result, layout.getHtmlCode % [
            layout.getPlaceholderId,
            if e.shouldMinify:
              view.getHtmlCode & reloadHandler
            else:
              indent(view.getHtmlCode & reloadHandler, layout.getPlaceholderIndent)
          ]

  proc compileCode(e: TimEngine, t: Template) =
    var p = e.parse(t.getSourceCode, t.getFilePath, templateType = t.getType)
    if p.hasError():
      e.errors = @[p.getError()]
      return
    if p.hasJit:
      t.enableJIT()
      e.writeBson(t, p.getStatementsStr, e.getIndent())
    else:
      var c = newCompiler(e, p.getStatements, t, e.shouldMinify, e.getIndent, t.getFilePath)
      if not c.hasError():
        e.writeHtml(t, c.getHtml())
      else:
        e.errors = c.getErrors()

  proc precompile*(e: TimEngine, callback: proc() {.gcsafe, nimcall.} = nil, debug = false) =
    ## Precompile `views` and `layouts` from `.timl`
    ## to static HTML or BSON.
    if e.hasAnySources:
      when not defined release:
        when requires "watchout":
          # Will use `watchout` to watch for changes in `/templates` dir
          proc watchoutCallback(file: watchout.File) {.closure.} =
            let initTime = cpuTime()
            echo "\n✨ Watchout resolve changes"
            echo file.getName()
            var timView = getTemplateByPath(e, file.getPath())
            if timView.isPartial:
              for depView in timView.getDependentViews():
                e.compileCode(getTemplateByPath(e, depView))
            else:
              e.compileCode(timView)
            if e.errors.len != 0:
              for err in e.errors:
                display err
              setLen(e.errors, 0)
            else:
              display("Done in: $1" % [$(cpuTime() - initTime)])
              if callback != nil:
                callback() # Run a custom callback, if available
           
          var watchFiles: seq[string]
          display("✓ Tim Templates", indent = 2)
          when compileOption("threads"):
            for id, view in e.getViews().mpairs():
              e.compileCode(view)
              watchFiles.add view.getFilePath()
              display(view.getName(), indent = 6)
            
            for id, partial in e.getPartials().pairs():
              # Watch for changes in `partials` directory.
              watchFiles.add partial.getFilePath()

            for id, layout in e.getLayouts().mpairs():
              e.compileCode(layout)
              watchFiles.add layout.getFilePath()
              display(layout.getName(), indent = 6)
            
            if e.errors.len != 0:
              for err in e.errors:
                display err
              setLen(e.errors, 0)
            # Start a new Thread with Watchout watching for live changes
            startThread(watchoutCallback, watchFiles, 550)
      else:
        for id, view in e.getViews().mpairs():
          e.compileCode(view)
          display(view.getName(), indent = 6)

        for id, layout in e.getLayouts().mpairs():
          e.compileCode(layout)
          display(layout.getName(), indent = 6)
        if e.errors.len != 0:
          for err in e.errors:
            display err
          setLen(e.errors, 0)