# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import pkginfo, jsony
import tim/engine/[ast, parser, meta, compiler]
import std/[tables, json]
from std/strutils import `%`, indent

when requires "watchout":
    import watchout
    from std/times import cpuTime

export parser
export meta except TimEngine

const DockType = "<!DOCTYPE html>"
const EndHtmlDocument = "</body></html>"

var Tim* {.global.}: TimEngine
const DefaultLayout = "base"

proc newCompiler(engine: TimEngine, timlTemplate: TimlTemplate, data: JsonNode): Compiler =
    result = Compiler.init(
        astProgram = fromJson(engine.readBson(timlTemplate), Program),
        minified = engine.shouldMinify(),
        templateType = timlTemplate.getType(),
        baseIndent = engine.getIndent(),
        filePath = timlTemplate.getFilePath(),
        data = data
    )

proc jitHtml(engine: TimEngine, view, layout: TimlTemplate, data: JsonNode): string =
    let clayout = engine.newCompiler(layout, data)
    let cview = engine.newCompiler(view, data)
    result = clayout.getHtml()
    if engine.shouldMinify():
        result.add cview.getHtml()
    else:
        result.add indent(cview.getHtml(), engine.getIndent())

proc render*(engine: TimEngine, key: string, layoutKey = DefaultLayout,
                data: JsonNode = %*{}): string =
    ## Renders a template view by name. Use dot-annotations
    ## for rendering views from sub directories directories,
    ## for example `render("product.sales.index")`
    ## will try look for a timl template at `product/sales/index.timl`
    if engine.hasView(key):
        var view: TimlTemplate = engine.getView(key)
        if not engine.hasLayout(layoutKey):
            raise newException(TimDefect, "Could not find \"" & layoutKey & "\" layout.")
        var layout: TimlTemplate = engine.getLayout(layoutKey)
        result = DockType
        if view.isJitEnabled():
            # When enabled, will compile `timl` > `html` on the fly
            result.add engine.jitHtml(view, layout, data)
        else:
            # Otherwise render precompiled templates
            let layoutCompilerInstance = engine.newCompiler(layout, data)
            result.add layoutCompilerInstance.getHtml()
            if engine.shouldMinify():
                result.add view.getHtmlCode()
            else:
                result.add indent(view.getHtmlCode(), engine.getIndent())

        when requires "supranim":
            when not defined release:
                # Enables auto-reloading handler when imported by a Supranim project
                proc httpReloader(): string =
                    result = """
<script type="text/javascript">
    document.addEventListener("DOMContentLoaded", function() {
        var prevTime = localStorage.getItem("watchout") || 0
        function liveChanges() {
            fetch('/watchout')
                .then(res => res.json())
                .then(body => {
                    if(body.state == 0) return
                    if(body.state > prevTime) {
                        localStorage.setItem("watchout", body.state)
                        location.reload()
                    }
                }).catch(function() {});
            setTimeout(liveChanges, 500)
        }
        liveChanges();
    });
</script>
"""
                case engine.getReloadType():
                    of HttpReloader:
                        # reload handler using http requests
                        result.add httpReloader()
                    else: discard
        result.add EndHtmlDocument

proc compileCode(engine: TimEngine, temp: var TimlTemplate) =
    let tpType = temp.getType()
    var p = engine.parse(temp.getSourceCode(), temp.getFilePath(), templateType = tpType)
    if p.hasError():
        raise newException(SyntaxError, "\n"&p.getError())
    if p.hasJIT() or tpType == Layout:
        temp.enableJIT()
        engine.writeBson(temp, p.getStatementsStr(), engine.getIndent())
    else:
        let c = Compiler.init(
            p.getStatements(),
            minified = engine.shouldMinify(),
            templateType = tpType,
            baseIndent = engine.getIndent(),
            filePath = temp.getFilePath()
        )
        engine.writeHtml(temp, c.getHtml())

proc precompile*(engine: var TimEngine, callback: proc() {.gcsafe, nimcall.} = nil,
                debug = false): seq[string] {.discardable.} =
    ## Pre-compile ``views`` and ``layouts``
    ## from ``.timl`` to HTML or BSON.
    ##
    ## Note that ``partials`` contents are collected on
    ## compile-time and merged within the view.
    if Tim.hasAnySources:
        when not defined release:
            # Enable auto precompile when in development mode
            when requires "watchout":
                # Will use `watchout` to watch for changes in `/templates` dir
                proc watchoutCallback(file: watchout.File) {.closure.} =
                    let initTime = cpuTime()
                    echo "\n✨ Watchout resolve changes"
                    echo file.getName()
                    var timlTemplate = getTemplateByPath(Tim, file.getPath())
                    if timlTemplate.isPartial:
                        for depView in timlTemplate.getDependentViews():
                            Tim.compileCode(getTemplateByPath(Tim, depView))
                    else:
                        Tim.compileCode(timlTemplate)
                    echo "Done in " & $(cpuTime() - initTime)
                    if callback != nil:
                        callback()
                var watchFiles: seq[string]
                when compileOption("threads"):
                    for id, view in Tim.getViews().mpairs():
                        Tim.compileCode(view)
                        watchFiles.add view.getFilePath()
                        result.add view.getName()
                    
                    for id, partial in Tim.getPartials().pairs():
                        # Watch for changes in `partials` directory.
                        watchFiles.add partial.getFilePath()

                    for id, layout in Tim.getLayouts().mpairs():
                        Tim.compileCode(layout)
                        watchFiles.add layout.getFilePath()
                        result.add layout.getName()

                    # Start a new Thread with Watchout watching for live changes
                    startThread(watchoutCallback, watchFiles, 550)
                    return

        for id, view in Tim.getViews().mpairs():
            Tim.compileCode(view)
            result.add view.getName()

        for id, layout in Tim.getLayouts().mpairs():
            Tim.compileCode(layout)
            result.add layout.getName()

when isMainModule:
    Tim.init(
        source = "../examples/templates",
        output = "../examples/storage",
        indent = 4,
        minified = false
    )
    discard Tim.precompile()
    echo Tim.render("index",
        data = %*{
            "app_name": "My application",
            "production": true,
            "name": "george",
            "rows": ["apple", "peanuts", "socks", "coke"],
            "countries": [
                {
                    "country": "romania",
                    "city": "bucharest"
                },
                {
                    "country": "greece",
                    "city": "athens"
                },
                {
                    "country": "italy",
                    "city": "rome"
                },
            ],
            "attributes": {
                "address": "Whatever address",
                "county": "yeye"
            }
        }
    )