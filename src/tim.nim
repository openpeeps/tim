# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import bson
import tim/engine/[parser, compiler, meta]
import std/[tables, json]

from std/times import cpuTime
from std/strutils import indent

when compileOption("threads"):
    import std/threadpool

export parser, meta, compiler

proc render*[T: TimEngine](engine: T, key: string, layoutKey = "base", data: JsonNode = %*{}): string =
    ## Renders a template view by name. Use dot-annotations
    ## for rendering views in nested directories.
    ##
    ##
    ## We handle the wrapping part on runtime. So that we prevent
    ## loading unecessary scripts (js/css), In this case,
    ## a view can change the layout anytime based on
    ## user session/conditional statements and so on.
    ##
    ## A layout wraps the view on runtime.
    ## Layouts output is separated in 2 files:
    ##  - The top side (for head elements)
    ##  - The bottom side (for ending head elements and resolving deferred scripts)
    if engine.hasView(key):
        var view: TimlTemplate = engine.getView(key)
        var layout: TimlTemplate = engine.getLayout(layoutKey)
        result = "<!DOCTYPE html>"
        result.add layout.getHtmlCode()
        result.add view.getHtmlCode()
        result.add layout.getHtmlTailsCode()

proc preCompileTemplate[T: TimEngine](engine: T, temp: TimlTemplate) =
    let templateType = temp.getType()
    var p: Parser = engine.parse(temp.getSourceCode(), temp.getFilePath(), templateType = templateType)
    if p.hasError():
        raise newException(TimSyntaxError, "\n"&p.getError())
    let c = Compiler.init(p.getStatements(), minified = engine.shouldMinify(), templateType = templateType)

    if templateType == Layout:
        # Save layout tails in a separate .html file, suffixed with `_`
        engine.writeHtml(temp, c.getHtmlTails(), isTail = true)
    engine.writeHtml(temp, c.getHtml())

proc precompile*[T: TimEngine](engine: T, debug = false) =
    ## Pre-compile ``views`` and ``layouts``
    ## from ``.timl`` to HTML or BSON.
    ##
    ## Note that ``partials`` code is collected on
    ## compile-time and merged within the view.
    if engine.hasAnySources:
        echo "Tim Engine precompiles:"
        for id, view in engine.getViews().pairs():
            # Save the Abstract Syntax Tree of the current template as BSON
            # echo p.getStatementsStr(prettyString = true) # debug
            # engine.writeBson(view, p.getStatementsStr())
            echo indent(view.getName(), 2)
            spawn engine.preCompileTemplate(view)
        sync()

        for id, layout in engine.getLayouts().pairs():
            echo indent(layout.getName(), 2)
            spawn engine.preCompileTemplate(layout)
        sync()

when isMainModule:
    let initTime = cpuTime()
    var engine = TimEngine.init(
        source = "../examples/templates",
            # directory path to find your `.timl` files
        output = "../examples/storage/templates",
            # directory path to store Binary JSON files for JIT compiler
        minified = true,
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
    echo engine.render("index")
    echo "Done in " & $(cpuTime() - initTime)