# High-performance, compiled template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim

import tim/engine/[parser, compiler, jit, meta]
import std/[tables, json, strutils]

import bson

from tim/engine/ast import HtmlNode
export parser, meta, jit, compiler

proc render*[T: TimEngine](engine: T, key: string, data: JsonNode = %*{}): string =
    ## Renders a template view with or without Json data
    ## Note that Tim is auto discovering your .timl templates inside /views directory,
    ## so key parameter reflects the name of the view (filename) without .timl extension.
    ## In this case for rendering `homepage.timl` you must specify `homepage`
    if engine.hasView(key):
        var responseStr = ""
        var layout: TimlTemplate = engine.getView(key)
        let c = JIT.init(engine.readBson(layout), minified = engine.shouldMinify())
        # add responseStr, """<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-1BmE4kWBq78iYhFldvKuhfTAU6auU8tT94WrHftjDbrCEXSU1oBoqyl2QvZ6jIW3" crossorigin="anonymous"></head><body>"""
        add responseStr, c.getHtml
        # add responseStr, "</body></html>"
        result = responseStr

proc precompile*[T: TimEngine](engine: T, debug = false) =
    ## Precompile Tim's views to BSON Abstract Syntax Tree
    var data = %*{
        "firstname": "George",
        "lastname": "Lemon"
    }

    if engine.hasAnySources:
        for id, view in engine.getViews().pairs():
            var p: Parser = engine.parse(view, data = data)
            if p.hasError():
                raise newException(TimSyntaxError, "\n"&p.getError())

            echo p.getStatementsStr(prettyString = true)
            # echo engine.readBson(view)
            # AST Nodes to BSON AST
            # BSON files are saved to provided `output` path under `bson` directory.
            # Each BSON template is named using MD5 based on its absolute path
            # if p.hasJIT:
                # RUNTIME!
                # Now, this is supposed to be done on runtime (on request).
                # Here we get the BSON AST and, if needed it will be sent 
                # to the evaluator to determine what should be displayed or not
                # TODO
                # let c = JIT.init(engine.readBson(view), minified = false)
                # echo c.getHtml
            # else:
                # echo "compile to html"
                # Finally, compile the AST to HTML
                # let c = Compiler.init(parser = p, minified = false, asNodes = true)
                # echo c.getHtml
            # Save the Abstract Syntax Tree of the current template as BSON
            engine.writeBson(view, p.getStatementsStr())
    else: raise newException(TimException, "Unable to find any Timl templates")


when isMainModule:
    var engine = TimEngine.init(
        source = "../examples/templates",             # root dir to Timl templates
        output = "../examples/storage/templates",     # dir path for storing BSON AST files 
        hotreload = true,                             # automatically disabled when compiling with -d:release
        minified = false,
        indent = 4
    )

    precompile(engine)

    echo engine.render("test")
