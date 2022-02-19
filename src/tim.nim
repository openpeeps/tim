# High-performance, compiled template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim

import tim/engine/[parser, compiler, jit, meta]
import std/[tables, json, strutils]

import bson

from tim/engine/ast import HtmlNode
from std/times import cpuTime

export parser, compiler, meta, jit

proc compile*[T: TimEngine](engine: var T, debug = false) =
    ## Parse Tim's layouts, views and partials and compile
    ## to BSON Abstract Syntax Tree

    var data = %*{
        "firstname": "George",
        "lastname": "Lemon"
    }

    if engine.hasAnySources:
        for id, layout in engine.getLayouts().pairs():
            
            # Parse each template.
            var p: Parser = engine.parse(layout, data = data)
            if p.hasError():
                raise newException(TimSyntaxError, "\n"&p.getError())
            if debug:
                # AST Nodes to BSON AST
                # BSON files are saved to provided `output` path under `bson` directory.
                # Each BSON template is named using MD5 based on its absolute path
                if p.hasJIT:
                    engine.writeBson(layout, p.getStatementsStr())
                    # RUNTIME!
                    # Now, this is supposed to be done on runtime (on request).
                    # Here we get the BSON AST and, if needed it will be sent 
                    # to the evaluator to determine what should be displayed or not
                    # TODO
                    let c = JIT.init(engine.readBson(layout), minified = false)
                    echo c.getHtml
                else:
                    echo "compile to html"
                    # Finally, compile the AST to HTML
                    let c = Compiler.init(parser = p, minified = false, asNodes = true)
                    # echo c.getHtml
            else:
                # Save the Abstract Syntax Tree of the current template as BSON
                engine.writeBson(layout, p.getStatementsStr())
    else: raise newException(TimException, "Unable to find any Timl templates")

when isMainModule:
    let time = cpuTime()
    # First, create a new Tim Engine
    var engine = TimEngine.init(
        source = "../examples/templates",             # root dir to Timl templates
        output = "../examples/storage/templates",     # dir path for storing BSON AST files 
        hotreload = true                              # automatically disabled when compiling with -d:release
    )
    engine.compile(debug = true)
    echo "✨ Done in " & $(cpuTime() - time)
