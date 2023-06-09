# A high-performance compiled template engine
# inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, strutils, json]
import pkg/[pkginfo, jsony, kapsis/cli]
import timpkg/engine/[meta, ast, parser, compiler, utils]

export parser
export meta except TimEngine

const DockType = "<!DOCTYPE html>"
var Tim*: TimEngine
const DefaultLayout = "base"

when defined cli:
  include ./cli/init
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

  proc newJIT(e: TimEngine, tpl: Template, data: JsonNode,
              viewCode = "", hasViewCode = false): Compiler =
    result = newCompiler(
      e = e,
      p = e.readAst(tpl),
      tpl = tpl,
      minify = e.shouldMinify,
      indent = e.getIndent,
      filePath = tpl.getFilePath,
      data = data,
      viewCode = viewCode,
      hasViewCode = hasViewCode
    )

  proc render*(e: TimEngine, viewName: string, layoutName = DefaultLayout,
              data, globals = %*{}): string =
    ## Render a template view by name (without extension). Use dot notation
    ## to render a nested template render("checkout.loggedin")
    if e.hasView viewName:
      let layoutName = 
        if e.hasLayout(layoutName):
          layoutName
        else: DefaultLayout
      var
        allData = newJObject()
        view: Template = e.getView viewName
        layout: Template = e.getLayout layoutName
      if e.globalDataExists:
        allData.merge("globals", e.getGlobalData, globals)
      else:
        allData.merge("globals", %*{}, globals)
      allData.add("scope", data)
      result = DockType
      if view.isJitEnabled:
        # Compile view at runtime
        var cview = newJIT(e, view, allData)
        var clayout = newJIT(e, layout, allData, cview.getHtml & reloadHandler, hasViewCode = true)
        add result, clayout.getHtml
        if clayout.hasError:
          for err in clayout.getErrors:
            display(span("Warning", fgYellow), span(err))
            display(indent(layout.getFilePath, 1), br="after")
        if cview.hasError:
          for err in cview.getErrors:
            display(span("Warning", fgYellow), span(err))
            display(indent(view.getFilePath, 1), br="after")
        freem(cview)
        freem(clayout)
      else:
        if layout.isJitEnabled:
          # Compile layout at runtime
          var c = newJIT(e, layout, allData, view.getHtmlCode & reloadHandler, hasViewCode = true)
          add result, c.getHtml
          if c.hasError:
            display("Warning:" & indent(layout.getFilePath, 1), br = "before")
            for err in c.getErrors:
              display(err, indent = 2)
          freem(c)
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

  proc compileCode(e: TimEngine, t: Template, fModified = false) =
    # if not t.isModified and fModified == false: return
    var p = e.parse(t.getSourceCode, t.getFilePath, templateType = t.getType)
    if p.hasError:
      e.errors = @[p.getError]
      return
    if p.hasJit:
      t.enableJit
      e.writeAst(t, p.getStatements, e.getIndent)
      freem(p)
    else:
      var c = newCompiler(e, p.getStatements, t, e.shouldMinify, e.getIndent, t.getFilePath)
      if not c.hasError():
        e.writeHtml(t, c.getHtml())
      else:
        e.errors = c.getErrors()
      freem(c)

  proc precompile*(e: TimEngine, callback: proc() {.gcsafe, nimcall.} = nil, debug = false) =
    ## Precompile `views` and `layouts` from `.timl` to static HTML or packed AST via MessagePack.
    ## To be used in the main state of your application.
    if e.templatesExists:
      when not defined release:
        when requires "watchout":
          # Will use `watchout` to watch for changes in `/templates` dir
          proc watchoutCallback(file: watchout.File) {.closure.} =
            let initTime = cpuTime()
            display "\n✨ Watchout resolve changes"
            display file.getName()
            var timView = getTemplateByPath(e, file.getPath())
            var fModified = false # to force compilation
            if timView.isPartial:
              for depView in timView.getDependentViews():
                let timPartial = getTemplateByPath(e, depView)
                if timPartial.isModified:
                  fModified = true
                e.compileCode(timPartial)
              # e.compileCode(timView, fModified)
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
            for id, view in e.getViews:
              e.compileCode(view)
              watchFiles.add view.getFilePath()
              display(view.getName(), indent = 6)
            
            for id, partial in e.getPartials:
              # Watch for changes in `partials` directory.
              watchFiles.add partial.getFilePath()

            for id, layout in e.getLayouts:
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
        display("✓ Tim Templates", indent = 2)
        for id, view in e.getViews:
          e.compileCode(view)
          display(view.getName(), indent = 6)

        for id, layout in e.getLayouts:
          e.compileCode(layout)
          display(layout.getName(), indent = 6)
        if e.errors.len != 0:
          for err in e.errors:
            display err
          setLen(e.errors, 0)

  proc tim2html*(code: string, minify = false, indent = 2, data = %*{}): string =
    ## Parse snippets of timl `code` to HTML.
    ## Note: calling this proc won't generate/cache AST.
    var p = parser.parse(code)
    if not p.hasError:
      result = newCompiler(p.getStatements, minify, indent, data).getHtml
      freem(p)
    else: raise newException(TimParsingError, p.getError)