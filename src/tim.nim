# High-performance, compiled template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim

import std/[tables, json]
import tim/engine/[parser, compiler]

from std/times import cpuTime
from std/os import getCurrentDir

export parser, compiler

type 
    TimlPageType = enum
        Layout, View, Partial

    TimlPage = object
        id, filepath: string
        timlType: TimlPageType

    TimEngine* = object
        pages: OrderedTable[string, TimlPage]

proc init*[T: typedesc[TimEngine]](engine: T): TimEngine =
    ## Initialize Tim Engine
    var e = engine()

# proc addLayout*[T: TimEngine](engine: T, page: TimlPage) =
#     ## Add a new Timl layout to current Engine instance

proc add*[T: TimEngine](pageType: TimlPageType) =
    ## Add a new Timl layout, view or partial to current Engine instance
    discard

when isMainModule:
    let time = cpuTime()

    # Create a new Tim Engine | For development purpose
    # var engine = TimEngine.init()

    # Add a new Timl layout, view, or partial using `add` proc
    # engine.add(pageType = Layout)
    let sampleData = readFile(getCurrentDir() & "/sample.json")
    var p: Parser = parse(readFile("sample.timl"), data = parseJson(sampleData))

    if p.hasError():
        # Catch errors collected while parsing
        echo p.getError()
    else:
        # Returns the a stringified JSON representing the
        # Abstract Syntax Tree of the current timl document
        echo p.getStatements()

        # Otherwise compile timl document to html
        let c = Compiler.init(parser = p, minified = false)
        echo "✨ Done in " & $(cpuTime() - time)

        # let sample = getCurrentDir() & "/sample.html"
        # writeFile(sample, c.getHtml())
        echo c.getHtml()