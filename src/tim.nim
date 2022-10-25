# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import pkginfo, jsony
import tim/engine/[ast, parser, meta]
import std/[tables, json]
from std/strutils import `%`, indent

when requires "watchout":
    import watchout
    from std/times import cpuTime

when requires "emitter":
    import emitter

export parser
export meta except TimEngine

const DockType = "<!DOCTYPE html>"
const EndHtmlDocument = "</body></html>"

var Tim* {.global.}: TimEngine

proc compileCode(engine: TimEngine, temp: var TimlTemplate) =
    let tpType = temp.getType()
    var p: Parser = engine.parse(temp.getSourceCode(), temp.getFilePath(), templateType = tpType)
    
    if p.hasError():
        raise newException(SyntaxError, "\n"&p.getError())
    
    echo p.getStatementsStr(true)

    # if p.hasJIT() or tpType == Layout:
    # First, check if current template has enabled JIT compilation.
    # Note that layouts are always saved in BSON format
    # temp.enableJIT()
    # engine.writeBson(temp, p.getStatementsStr(), engine.getIndent())
    
    # else:
    #     let c = Compiler.init(
    #         p.getStatements(),
    #         minified = engine.shouldMinify(),
    #         templateType = tpType,
    #         baseIndent = engine.getIndent()
    #     )
    #     # if tpType == Layout:
    #     #     # Save layout tails in a separate .html file, suffixed with `_`
    #     #     engine.writeHtml(temp, c.getHtmlTails(), isTail = true)
    #     engine.writeHtml(temp, c.getHtml())

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
        indent = 2,
        minified = false
    )
    let timTemplates = Tim.precompile()
    # echo Tim.render("index",
    #     data = %*{
    #         "app_name": "My application",
    #         "name": "George Lemon",
    #         "rows": ["apple", "peanuts", "socks", "coke"]
    #     }
    # )