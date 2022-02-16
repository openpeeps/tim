# High-performance, compiled template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim
import bson
import std/[tables, json, md5]

from std/strutils import `%`, strip, split
from std/osproc import execProcess, poStdErrToStdOut, poUsePath
from std/os import getCurrentDir, normalizePath, dirExists,
                   fileExists, walkDirRec, splitPath, createDir

type 
    TimlTemplateType = enum
        Layout, View, Partial

    TimlTemplateTable = OrderedTable[string, TimlTemplate]
    TimlDirectoryTable = Table[string, TimlDirectory]

    TimlTemplate* = object
        meta: tuple [
            name: string,                           # name of the current TimlTemplate representing file name
            template_type: TimlTemplateType         # type of TimlTemplate, either Layout, View or Partial
        ]
        paths: tuple[
            file, ast, html: string, 
        ]
        data: JsonNode                              # JSON data exposed to TimlTemplate
        sourceCode: string
        astSource*: string

    TimlDirectory = object
        path: string                                # source path on disk
        templates: TimlTemplateTable                # table containing all TimlTemplate objects

    TimEngine* = object
        root: string                                # root path to your Timl templates
        output: string                              # root path for HTML and BSON AST output
        src: TimlDirectoryTable                     # table containing all TimlDirectory objects

    TimException* = object of CatchableError

proc getTemplates*[T: TimlDirectory](t: var T): TimlTemplateTable {.inline.} =
    result = t.templates

proc getTemplate*[T: TimlDirectory](t: var T, key: string): TimlTemplate =
    let templates = t.getTemplates
    if templates.hasKey(key):
        result = templates[key]
    else: raise newException(TimException, "Unable to find a template for \"$1\" key")

proc getContents*[T: TimlTemplate](t: T): string {.inline.} =
    ## Retrieve code contents of current TimlTemplate
    result = t.fileContents

proc getName*[T: TimlTemplate](t: T): string {.inline.} =
    ## Retrieve the file name (including extension) of the current TimlTemplate
    result = t.fileName

proc getFilePath*[T: TimlTemplate](t: T): string {.inline.} =
    ## Retrieve the file path of the current TimlTemplate
    result = t.filePath

proc getFileData*[T: TimlTemplate](t: T): JsonNode {.inline.} =
    ## Retrieve JSON data exposed to TimlTemplate
    result = t.data

proc getSourceCode*[T: TimlTemplate](t: T): string {.inline.} =
    ## Retrieve source code of current TimlTemplate object
    result = t.sourceCode

proc setAstSource*[T: TimlTemplate](t: var T, ast: string) {.inline.} =
    t.astSource = ast

proc getAstSource*[T: TimlTemplate](t: T): string {.inline.} =
    result = t.astSource

proc hasAnySources*[T: TimEngine](e: T): bool {.inline.} =
    ## Determine if current TimEngine has any TimlDirectory
    ## objects stored in TimlDirectoryTable
    result = len(e.src) != 0

proc getSources[T: TimEngine](e: var T): TimlDirectoryTable {.inline.} =
    ## Retrieves all TimlDirectory objects as TimlDirectoryTable (Table[string, TimlDirectory])
    result = e.src

proc getSources[T: TimEngine](e: var T, key: string): TimlDirectory =
    ## Retrieve a specific TimlDirectory object source, based on given key,
    ## where key can be either `layouts`, `views`, or `partials`
    let sources = e.getSources()
    if e.src.hasKey(key):
        result = e.src[key]
    else: raise newException(TimException,
        "Unable to find a TimlDirectoryTable for \"$1\" key")

proc getLayouts*[T: TimEngine](e: var T): TimlTemplateTable =
    ## Retrieve entire table of layouts as TimlTemplateTable
    result = e.getSources("layouts").templates

proc getViews*[T: TimEngine](e: var T): TimlTemplateTable =
    ## Retrieve entire table of views as TimlTemplateTable
    result = e.getSources("views").templates

proc getPartials*[T: TimEngine](e: var T): TimlTemplateTable =
    ## Retrieve entire table of partials as TimlTemplateTable
    result = e.getSources("partials").templates

proc getStoragePath*[T: TimEngine](e: var T): string =
    ## Retrieve the absolute path of TimEngine output directory
    result = e.output

proc hashTail(input: string): string =
    result = getMD5(input)

proc bsonPath(outputDir, filePath: string): string =
    ## Set the BSON AST path and return the string
    result = getCurrentDir() & "/" & outputDir & "/bson/" & hashTail(filePath) & ".ast.bson"
    normalizePath(result)

proc htmlPath(outputDir, filePath: string): string =
    ## Set the HTML output path and return the string
    result = getCurrentDir() & "/" & outputDir & "/html/" & hashTail(filePath) & ".html"
    normalizePath(result)

# proc writeBson*[E: TimEngine, T: TimlTemplate](e: var E, t: var T) =
#     echo t.ast
#     # writeFile(t.ast, bytes(@@(t.getAstSource)))

proc writeBson*[E: TimEngine, T: TimlTemplate](e: var E, t: T, ast: string) =
    writeFile(t.paths.ast, bytes(@@(ast)))

proc cmd(inputCmd: string, inputArgs: openarray[string]): auto {.discardable.} =
    ## Short hand procedure for executing shell commands via execProcess
    return execProcess(inputCmd, args=inputArgs, options={poStdErrToStdOut, poUsePath})

proc finder*(findArgs: seq[string] = @[], path=""): seq[string] {.thread.} =
    ## Recursively search for files.
    ## Optionally, you can set the maximum depth level,
    ## whether to ignore a certain types of files,
    ## by extension and/or visibility (dot files)
    ##
    ## This procedure is using `find` for Unix systems, while
    ## on Windows is making use of walkDirRec's Nim iterator and Regex module.
    when defined windows:
        var files: seq[string]
        for file in walkDirRec(getCurrentDir()):
            if file.match re".*\.timl":
                files.add(file)
        result = files
    else:
        var args: seq[string] = findArgs
        args.insert(path, 0)
        var files = cmd("find", args).strip()
        if files.len == 0: # "Unable to find any files at given location"
            result = @[]
        else:
            result = files.split("\n")

proc init*[T: typedesc[TimEngine]](timEngine: T, source, output: string, hotreload: bool): TimEngine =
    ## Initialize a new Tim Engine by providing the root path directory 
    ## to your templates (layouts, views and partials).
    ## Tim is able to auto-discover your .timl files
    var timlInOutDirs: seq[string]
    for path in @[source, output]:
        var tpath = getCurrentDir() & "/" & path
        tpath.normalizePath()
        if not tpath.dirExists(): raise newException(TimException,
            "Unable to find Tim source directory at\n$1" % [tpath])
        timlInOutDirs.add(path)
        if path == output:
            # create `bson` and `html` dirs inside `output` directory
            # where `bson` is used for saving the binary abstract syntax tree
            # for pages that requires dynamic checks, such as data assignation,
            # and conditional statementsa, and second the `html` directory,
            # for saving the final output in case the current page
            # containg nothing else than static timl code
            for inDir in @["bson", "html"]:
                let innerDir = path & "/" & inDir
                if not dirExists(innerDir): createDir(innerDir)


    var e = timEngine()
    e.root = timlInOutDirs[0]
    e.output = timlInOutDirs[1]
    for tdir in @["layouts", "views", "partials"]:
        let tdirpath = e.root & "/" & tdir
        if dirExists(tdirpath):
            var timlDirObject = TimlDirectory(path: tdirpath)
            let files = finder(findArgs = @["-type", "f", "-print"], path = tdirpath)
            if files.len != 0:
                for f in files:
                    let fname = splitPath(f)
                    var ftype: TimlTemplateType
                    case tdir:
                        of "layouts": ftype = Layout
                        of "views": ftype = View
                        of "partials": ftype = Partial

                    var timlTemplate = TimlTemplate(
                            meta: (name: fname.tail, template_type: ftype),
                            paths: (file: f, ast: bsonPath(e.output, f), html: htmlPath(e.output, f)),
                            sourceCode: readFile(f)
                        )
                    timlDirObject.templates[fname.tail] = timlTemplate
                    e.src[tdir] = timlDirObject
    result = e

proc add*[T: TimEngine](pageType: TimlTemplateType) =
    ## Add a new Timl layout, view or partial to current Engine instance
    discard