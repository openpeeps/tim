# High-performance, compiled template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim
import bson
import std/[tables, json, md5]

from std/strutils import `%`, strip, split, contains
from std/osproc import execProcess, poStdErrToStdOut, poUsePath
from std/os import getCurrentDir, normalizePath, dirExists,
                   fileExists, walkDirRec, splitPath, createDir

type 
    TimlTemplateType = enum
        Layout, View, Partial


    TimlTemplate* = object
        meta: tuple [
            name: string,                           # name of the current TimlTemplate representing file name
            template_type: TimlTemplateType         # type of TimlTemplate, either Layout, View or Partial
        ]
        paths: tuple[file, ast, html: string]
        data: JsonNode                              # JSON data exposed to TimlTemplate
        sourceCode: string
        astSource*: string
    
    TimlTemplateTable = OrderedTable[string, TimlTemplate]

    TimEngine* = object
        root: string                                # root path to your Timl templates
        output: string                              # root path for HTML and BSON AST output
        layouts: TimlTemplateTable
        views: TimlTemplateTable
        partials: TimlTemplateTable
        minified: bool
        indent: int

    TimException* = object of CatchableError        # raise errors while setup Tim
    TimSyntaxError* = object of CatchableError      # raise errors from Tim language

# proc getTemplates*[T: TimlTemplateTable](t: var T): TimlTemplateTable {.inline.} =
#     result = t.templates

# proc getTemplate*[T: TimlTemplateTable](t: var T, key: string): TimlTemplate =
#     let templates = t.getTemplates
#     if templates.hasKey(key):
#         result = templates[key]
#     else: raise newException(TimException, "Unable to find a template for \"$1\" key")

proc getIndent*[T: TimEngine](t: T): int = 
    ## Get preferred indentation size (2 or 4 spaces). Default 4
    result = t.indent

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
    ## objects stored in layouts, views or partials fields
    result = len(e.views) != 0

proc getLayouts*[T: TimEngine](e: T): TimlTemplateTable =
    ## Retrieve entire table of layouts as TimlTemplateTable
    result = e.layouts

proc hasLayout*[T: TimEngine](e: T, key: string): bool =
    let path = e.root & "/layouts/" & key & ".timl"
    result = e.layouts.hasKey(path)

proc getLayout*[T: TimEngine](e: T, key: string): TimlTemplate =
    let path = e.root & "/layouts/" & key & ".timl"
    result = e.layouts[path]

proc getViews*[T: TimEngine](e: T): TimlTemplateTable =
    ## Retrieve entire table of views as TimlTemplateTable
    result = e.views

proc getViewPath[T: TimEngine](e: T, key: string): string =
    # Get absolute path of a view based on given key.
    var tree: seq[string]
    result = e.root & "/views/$1.timl"
    if key.contains("."):
        tree = key.split(".")
        result = result % [tree.join("/")]
    else:
        result = result % [key]

proc hasView*[T: TimEngine](e: T, key: string): bool =
    ## Determine if view exists
    ## This procedure provides view access via dot-annotation
    result = e.views.hasKey(e.getViewPath(key))

proc getView*[T: TimEngine](e: T, key: string): TimlTemplate =
    ## Retrieve a view template by key.
    ## This procedure provides view access via dot-annotation
    result = e.views[e.getViewPath(key)]

proc getPartials*[T: TimEngine](e: T): TimlTemplateTable =
    ## Retrieve entire table of partials as TimlTemplateTable
    result = e.partials

proc getStoragePath*[T: TimEngine](e: var T): string =
    ## Retrieve the absolute path of TimEngine output directory
    result = e.output

proc getBsonPath*[T: TimlTemplate](e: T): string = 
    ## Get the absolute path of BSON AST file
    result = e.paths.ast

proc shouldMinify*[T: TimEngine](e: T): bool =
    ## Determine if Tim Engine should minify the final HTML
    result = e.minified

proc hashTail(input: string): string =
    ## Create a MD5 hashed version of given input string
    result = getMD5(input)

proc bsonPath(outputDir, filePath: string): string =
    ## Set the BSON AST path and return the string
    result = getCurrentDir() & "/" & outputDir & "/bson/" & hashTail(filePath) & ".ast.bson"
    normalizePath(result)

proc htmlPath(outputDir, filePath: string): string =
    ## Set the HTML output path and return the string
    result = getCurrentDir() & "/" & outputDir & "/html/" & hashTail(filePath) & ".html"
    normalizePath(result)

proc writeBson*[E: TimEngine, T: TimlTemplate](e: E, t: T, ast: string) =
    ## Write current JSON AST to BSON
    var document = newBsonDocument()
    document["ast"] = ast
    writeFile(t.paths.ast, document.bytes)

proc readBson*[E: TimENgine, T: TimlTemplate](e: E, t: T): string =
    ## Read current BSON and parse to JSON
    var document: Bson = newBsonDocument(readFile(t.paths.ast))
    result = document["ast"]

proc cmd(inputCmd: string, inputArgs: openarray[string]): auto {.discardable.} =
    ## Short hand procedure for executing shell commands via execProcess
    return execProcess(inputCmd, args=inputArgs, options={poStdErrToStdOut, poUsePath})

proc finder(findArgs: seq[string] = @[], path=""): seq[string] {.thread.} =
    ## Recursively search for files.
    ##
    ## TODO
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

proc init*[T: typedesc[TimEngine]](timEngine: T, source, output: string, hotreload: bool, minified = true, indent: int): TimEngine =
    ## Initialize a new Tim Engine by providing the root path directory 
    ## to your templates (layouts, views and partials).
    ## Tim is able to auto-discover your .timl files
    var timlInOutDirs: seq[string]
    for path in @[source, output]:
        var tpath = getCurrentDir() & "/" & path
        tpath.normalizePath()
        if not tpath.dirExists():
            # raise newException(TimException, "Unable to find Tim source directory at\n$1" % [tpath])
            createDir(tpath)

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

    var lTable, vTable, pTable: OrderedTable[string, TimlTemplate]
    for tdir in @["layouts", "views", "partials"]:
        var tdirpath = getCurrentDir() & "/" & timlInOutDirs[0] & "/" & tdir
        if dirExists(tdirpath):
            # TODO look for .timl files only
            let files = finder(findArgs = @["-type", "f", "-print"], path = tdirpath)
            if files.len != 0:
                for f in files:
                    let fname = splitPath(f)
                    var ftype: TimlTemplateType
                    var filePath = f
                    filePath.normalizePath()
                    case tdir:
                    of "layouts": ftype = Layout
                    of "views": ftype = View
                    of "partials": ftype = Partial

                    var tTemplate = TimlTemplate(
                        meta: (name: fname.tail, template_type: ftype),
                        paths: (
                            file: filePath,
                            ast: bsonPath(timlInOutDirs[1], filePath),
                            html: htmlPath(timlInOutDirs[1], filePath)
                        ),
                        sourceCode: readFile(filePath)
                    )
                    case ftype:
                    of Layout: lTable[filePath] = tTemplate
                    of View: vTable[filePath] = tTemplate
                    of Partial: vTable[filePath] = tTemplate
        else:
            createDir(tdirpath) # create `layouts`, `views`, `partials` directories

    var
        rootPath = getCurrentDir() & "/" & timlInOutDirs[0]
        outputPath = getCurrentDir() & "/" & timlInOutDirs[1]
    rootPath.normalizePath()
    outputPath.normalizePath()
    result = timEngine(
        root: rootPath,
        output: outputPath,
        layouts: lTable,
        views: vTable,
        partials: pTable,
        minified: minified,
        indent: indent
    )
