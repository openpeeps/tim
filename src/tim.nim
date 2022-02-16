# High-performance, compiled template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim

import tim/engine/[parser, compiler, meta]
import std/tables

from std/times import cpuTime
from std/strutils import `%`, strip, split
from std/osproc import execProcess, poStdErrToStdOut, poUsePath
from std/os import getCurrentDir, normalizePath, dirExists,
                   fileExists, walkDirRec, splitPath

export parser, compiler, meta

proc run*[T: TimEngine](engine: var T) =
    echo len(engine.getSources())
    discard

when isMainModule:
    let time = cpuTime()

    # First, create a new Tim Engine
    var engine = TimEngine.init(
        templates = "../examples/templates",          # root dir to Timl templates
        storage = "../examples/storage/templates"     # dir path for storing BSON AST files 
        hotreload = true                              # automatically disabled when compiling with -d:release
    )
    engine.run()
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
    #     var BSONDocument = @@(p.getStatements())
    #     writeFile(getCurrentDir() & "/sample.ast.bson", BSONDocument.bytes())

    #     # Otherwise compile timl document to html
    #     let c = Compiler.init(parser = p, minified = false)
    #     echo "✨ Done in " & $(cpuTime() - time)

    #     writeFile(getCurrentDir() & "/sample.html", c.getHtml())
    #     echo c.getHtml()