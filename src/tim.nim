# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import bson
import tim/engine/[parser, compiler, meta]
import std/[tables, json]

from std/times import cpuTime

when compileOption("threads"):
    import std/threadpool

export parser, meta, compiler

proc render*[T: TimEngine](engine: T, key: string, layout = "base", data: JsonNode = %*{}): string =
    ## Renders a template view with or without a ``JSON`` data.
    ## Note that Tim is auto discovering your .timl templates inside /views directory,
    ## so the ``key`` parameter reflects the name of the view (filename) without
    ## specifying the file extension ``.timl``.
    ##
    ## Example, for rendering ``homepage.timl`` you must specify ``homepage``.
    ## 
    ## If you want to render a ``contact.timl`` view that is stored
    ## in a sub directory like ``views/members``, then  you can use dot annotation.
    ## Example ``engine.render("members.contact")``
    if engine.hasView(key):
        var view: TimlTemplate = engine.getView(key)
        result = "<!DOCTYPE html>"
        result.add view.getHtmlCode()

proc preCompileTemplate[T: TimEngine](engine: T, view: TimlTemplate) =
    var p: Parser = engine.parse(view.getSourceCode(), view.getFilePath(), templateType = view.getType())
    if p.hasError():
        raise newException(TimSyntaxError, "\n"&p.getError())
    let c = Compiler.init(p.getStatements(), minified = engine.shouldMinify())
    engine.writeHtml(view, c.getHtml) # write HTML output without layout wrap

proc precompile*[T: TimEngine](engine: T, debug = false) =
    ## Pre compile from ``.timl`` to AST in BSON format.
    if engine.hasAnySources:
        for id, view in engine.getViews().pairs():
            # Save the Abstract Syntax Tree of the current template as BSON
            # echo p.getStatementsStr(prettyString = true) # debug
            # engine.writeBson(view, p.getStatementsStr())
            spawn engine.preCompileTemplate(view)
        sync()

        for id, layout in engine.getLayouts().pairs():
            spawn engine.preCompileTemplate(layout)
        sync()

when isMainModule:
    let initTime = cpuTime()
    var engine = TimEngine.init(
        source = "../examples/templates",
            # directory path to find your `.timl` files
        output = "../examples/storage/templates",
            # directory path to store Binary JSON files for JIT compiler
        minified = false,
            # Whether to minify the final HTML output (by default enabled)
        indent = 4
            # Used to indent your HTML output (ignored when `minified` is true)
    )

    # If you're not using Tim's Command Line Interface you have to
    # to call this proc manually in main state of your app so
    # tim can precompile ``.timl`` to either :
    # ``.html`` for static templates
    # ``.bson`` for templates requiring runtime computation,
    # like conditional statements, iterations, var assignments and so on.
    
    engine.precompile()
    # echo engine.render("index")

    echo "Done in " & $(cpuTime() - initTime)