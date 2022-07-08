# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import pkginfo, bson
import tim/engine/[parser, compiler, meta]
import std/[tables, json]

from std/times import cpuTime
from std/strutils import indent

when requires "watchout":
    import watchout
when requires "emitter":
    import emitter

export parser, meta, compiler

const Docktype = "<!DOCTYPE html>"

proc render*[T: TimEngine](engine: T, key: string, layoutKey = "base", data: JsonNode = %*{}): string =
    ## Renders a template view by name. Use dot-annotations
    ## for rendering views in nested directories.
    if engine.hasView(key):
        # TODO handle templates marked with JIT
        var view: TimlTemplate = engine.getView(key)
        if not engine.hasLayout(layoutKey):
            raise newException(TimDefect, "Could not find \"" & layoutKey & "\" layout.")
        var layout: TimlTemplate = engine.getLayout(layoutKey)
        result = Docktype
        result.add layout.getHtmlCode()
        result.add view.getHtmlCode()
        when requires "supranim":
            when not defined release:
                proc httpReloader(): string =
                    # Reload Supranim application using
                    # the HttpReloader method
                    result = """
<script type="text/javascript">
document.addEventListener("DOMContentLoaded", function() {
    var prevTime = localStorage.getItem("watchout") || 0
    let watchoutLiveReload = function() {
        fetch('/watchout')
            .then(response => response.json())
            .then(body => {
                if(body.state == 0) return
                if(body.state > prevTime) {
                    localStorage.setItem("watchout", body.state)
                    location.reload()
                }
            }).catch(function() {});
        setTimeout(watchoutLiveReload, 500)
    }
    watchoutLiveReload();
});
</script>
"""
                proc wsReloader(): string =
                    # Reload Supranim application using
                    # a WebSocket Connection 
                    # TODO
                    result = ""

                case engine.getReloadType():
                of HttpReloader:
                    result.add httpReloader()
                of WSReloader:
                    result.add wsReloader()
                else: discard

        result.add layout.getHtmlTailsCode()

proc preCompileTemplate[T: TimEngine](engine: T, temp: var TimlTemplate) =
    let tpType = temp.getType()
    var p: Parser = engine.parse(temp.getSourceCode(), temp.getFilePath(), templateType = tpType)
    if p.hasError():
        raise newException(TimSyntaxError, "\n"&p.getError())
    let c = Compiler.init(p.getStatements(), minified = engine.shouldMinify(), templateType = tpType)
    if tpType == Layout:
        # Save layout tails in a separate .html file, suffixed with `_`
        engine.writeHtml(temp, c.getHtmlTails(), isTail = true)
    # if p.hasJIT:
    #     engine.writeBson(temp, c.getHtml(), p.getBaseIndent())
    #     discard engine.readBson(temp)
    # else:
    engine.writeHtml(temp, c.getHtml())

proc precompile*[T: TimEngine](engine: T, callback: proc() {.gcsafe.}, debug = false): seq[string] {.discardable.} =
    ## Pre-compile ``views`` and ``layouts``
    ## from ``.timl`` to HTML or BSON.
    ##
    ## Note that ``partials`` contents are collected on
    ## compile-time and merged within the view.
    if engine.hasAnySources:
        when not defined release:
            # Enable auto precompile when in development mode
            when requires "watchout":
                # Will use `watchout` to watch for changes in `/templates` dir
                proc watchoutCallback(file: watchout.File) {.gcsafe.} =
                    let initTime = cpuTime()
                    echo "\n✨ Watchout resolve changes"
                    echo file.getName()
                    var timlTemplate = getTemplateByPath(engine, file.getPath())
                    if timlTemplate.isPartial:
                        for dependentView in timlTemplate.getDependentViews():
                            engine.preCompileTemplate(
                                getTemplateByPath(engine, dependentView)
                            )
                    else:
                        engine.preCompileTemplate(timlTemplate)
                    echo "Done in " & $(cpuTime() - initTime)
                    callback()
                var watchFiles: seq[string]
                when compileOption("threads"):
                    for id, view in engine.getViews().mpairs():
                        engine.preCompileTemplate(view)
                        watchFiles.add view.getFilePath()
                        result.add view.getName()
                    
                    for id, partial in engine.getPartials().pairs():
                        # Watch for changes in `partials` directory.
                        watchFiles.add partial.getFilePath()

                    for id, layout in engine.getLayouts().mpairs():
                        engine.preCompileTemplate(layout)
                        watchFiles.add layout.getFilePath()
                        result.add layout.getName()

                    # Start a new Thread with Watchout watching for live changes
                    Watchout.startThread(watchoutCallback, watchFiles, 550)
                    return

        for id, view in engine.getViews().mpairs():
            engine.preCompileTemplate(view)
            result.add view.getName()

        for id, layout in engine.getLayouts().mpairs():
            engine.preCompileTemplate(layout)
            result.add layout.getName()


when isMainModule:
    let initTime = cpuTime()
    var Tim = TimEngine.init(
        source = "../examples/templates",
            # directory path to find your `.timl` files
        output = "../examples/storage/templates",
            # directory path to store Binary JSON files for JIT compiler
        minified = false,
            # Whether to minifying the final HTML output (by default enabled)
        indent = 4
            # Used to indent your HTML output (ignored when `minified` is true)
    )

    # If you're not using Tim's Command Line Interface you have to
    # to call this proc manually in main state of your app so
    # Tim can precompile ``.timl`` to either :
    # ``.html`` for static templates
    # ``.bson`` for templates requiring runtime computation,
    # like conditional statements, iterations, var assignments and so on.

    Tim.precompile()
    var data = %*{
        "name": "George Lemon"
    }
    echo Tim.render("index", data = data)
    echo "Done in " & $(cpuTime() - initTime)
