# High-performance, compiled template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim

import tim/engine/[parser, compiler, meta]
import std/[tables, json]
from std/times import cpuTime
export parser, compiler, meta

proc compile*[T: TimEngine](engine: var T) =
    if engine.hasAnySources:
        for id, layout in engine.getLayouts().pairs():
            var p: Parser = engine.parse(layout, data = %*{})
            if p.hasError():
                echo p.getError()
            else:
                # layout.setAstSource(p.getStatements())        # fix 'layout' is immutable, not 'var'
                engine.writeBson(layout, p.getStatements())
    else: raise newException(TimException, "Unable to find any Timl templates")

when isMainModule:
    let time = cpuTime()
    # First, create a new Tim Engine
    var engine = TimEngine.init(
        source = "../examples/templates",             # root dir to Timl templates
        output = "../examples/storage/templates",     # dir path for storing BSON AST files 
        hotreload = true                              # automatically disabled when compiling with -d:release
    )
    engine.compile()
    echo "✨ Done in " & $(cpuTime() - time)

    # Add a new Timl layout, view, or partial using `add` proc
    # engine.add(pageType = Layout)
    # let sampleData = readFile(getCurrentDir() & "/sample.json")
    # var p: Parser = parse(readFile("sample.timl"), data = parseJson(sampleData))

    # if p.hasError():
    #     # Catch errors collected while parsing
    #     echo p.getError()
    # else:
    #     # Returns the a stringified JSON representing the
    #     # Abstract Syntax Tree of the current timl document

    #     # Otherwise compile timl document to html
    #     let c = Compiler.init(parser = p, minified = false)
    #     echo "✨ Done in " & $(cpuTime() - time)

    #     writeFile(getCurrentDir() & "/sample.html", c.getHtml())
    #     echo c.getHtml()