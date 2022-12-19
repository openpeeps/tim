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

var Tim* {.global.}: TimEngine
const DefaultLayout = "base"

proc newCompiler(engine: TimEngine, timlTemplate: TimlTemplate, data: JsonNode, viewCode = ""): Compiler =
    result = Compiler.init(
        astProgram = fromJson(engine.readBson(timlTemplate), Program),
        minified = engine.shouldMinify(),
        timlTemplate = timlTemplate,
        baseIndent = engine.getIndent(),
        filePath = timlTemplate.getFilePath(),
        data = data,
        viewCode = viewCode
    )

proc render*(engine: TimEngine, key: string, layoutKey = DefaultLayout,
                data: JsonNode = %*{}): string =
    ## Renders a template view by name. Use dot notations
    ## for accessing views in sub directories,
    ## for example `render("product.sales.index")`
    ## will try look for a timl template at `product/sales/index.timl`
    if engine.hasView(key):
        var view: TimlTemplate = engine.getView(key)
        var allData: JsonNode = %* {}
        if engine.globalDataExists:
            allData.add("globals", engine.getGlobalData())
        allData["scope"] = data
        if not engine.hasLayout(layoutKey):
            raise newException(TimDefect, "Could not find \"" & layoutKey & "\" layout.")

        var layout: TimlTemplate = engine.getLayout(layoutKey)
        result = DockType
        if view.isJitEnabled():
            # When enabled, will compile `timl` > `html` on the fly
            var cview = engine.newCompiler(view, allData)
            var clayout = engine.newCompiler(layout, allData, cview.getHtml())
            result.add clayout.getHtml()
        else:
            # Otherwise, load static views, but first
            # check if requested layout is available as BSON
            if layout.isJitEnabled():
                let c = engine.newCompiler(layout, allData, view.getHtmlCode)
                result.add(c.getHtml())
            else:
                if engine.shouldMinify():
                    result.add(layout.getHtmlCode() % [
                        layout.getPlaceholderId, view.getHtmlCode
                    ])
                else:
                    result.add(layout.getHtmlCode() % [
                        layout.getPlaceholderId,
                        indent(view.getHtmlCode, engine.getIndent)
                    ])

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

proc compileCode(engine: TimEngine, temp: var TimlTemplate) =
    var p = engine.parse(temp.getSourceCode(), temp.getFilePath(), templateType = temp.getType())
    if p.hasError():
        raise newException(SyntaxError, "\n"&p.getError())
    if p.hasJit() or temp.getType == Layout:
        temp.enableJIT()
        engine.writeBson(temp, p.getStatementsStr(), engine.getIndent())
    else:
        let c = Compiler.init(
            p.getStatements(),
            minified = engine.shouldMinify(),
            timlTemplate = temp,
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
                        # Run a custom callback, if available
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
        indent = 2,
        minified = false
    )

    Tim.setData(%*{
        "appName": "My application",
        "production": false,
        "keywords": ["template-engine", "html", "tim", "compiled", "templating"],
        "products": [
            {
                "id": "8629976",
                "name": "Riverside 900, 10-Speed Hybrid Bike",
                "price": 799.00,
                "currency": "USD",
                "composition": "100% Aluminium 6061",
                "sizes": [
                    {
                        "label": "S",
                        "stock": 31
                    },
                    {
                        "label": "M",
                        "stock": 94
                    },
                    {
                        "label": "L",
                        "stock": 86
                    }
                ]
            },
            {
                "id": "8219006",
                "name": "Riverside 500, 7-Speed Hybrid Bike",
                "price": 599.00,
                "currency": "USD",
                "composition": "100% Aluminium 6061",
                "sizes": [
                    {
                        "label": "S",
                        "stock": 31
                    },
                    {
                        "label": "M",
                        "stock": 94
                    },
                    {
                        "label": "L",
                        "stock": 86
                    }
                ]
            }
        ],
        "objects": {
            "a" : {
                "b": "ok"
            }
        }
    })

    discard Tim.precompile()
    echo Tim.render("index", data = %*{
        "username": "George"
    })