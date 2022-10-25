# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import bson
import std/[tables, json, md5]

from std/math import sgn
from std/strutils import `%`, strip, split, contains, join, endsWith, replace, parseInt
from std/osproc import execProcess, poStdErrToStdOut, poUsePath
from std/os import getCurrentDir, normalizePath, normalizedPath, dirExists,
                   fileExists, walkDirRec, splitPath, createDir,
                   isHidden

type 
    TimlTemplateType* = enum
        Layout, View, Partial

    TimlTemplate* = object
        case timlType: TimlTemplateType
        of Partial:
            dependents: seq[string]
                # a sequence containing all views that include this partial
        else: discard
        meta: tuple [
            name: string,                          # name of the current TimlTemplate representing file name
            templateType: TimlTemplateType         # type of TimlTemplate, either Layout, View or Partial
        ]
        paths: tuple[file, ast, html, tails: string]
        data: JsonNode                              # JSON data exposed to TimlTemplate
        astSource*: string
        jit: bool
    
    TimlTemplateTable = OrderedTableRef[string, TimlTemplate]

    HotReloadType* = enum
        None, HttpReloader, WsReloader

    TimEngine* = object
        root: string                                # root path to your Timl templates
        output: string                              # root path for HTML and BSON AST output
        layouts: TimlTemplateTable
        views: TimlTemplateTable
        partials: TimlTemplateTable
        minified: bool
        indent: int
        paths: tuple[layouts, views, partials: string]
        reloader: HotReloadType

    SyntaxError* = object of CatchableError      # raise errors from Tim language
    TimDefect* = object of CatchableError

const timVersion = "0.1.0"

# proc getTemplates*[T: TimlTemplateTable](t: var T): TimlTemplateTable =
#     result = t.templates

# proc getTemplate*[T: TimlTemplateTable](t: var T, key: string): TimlTemplate =
#     let templates = t.getTemplates
#     if templates.hasKey(key):
#         result = templates[key]
#     else: raise newException(TimException, "Unable to find a template for \"$1\" key")

proc getIndent*[T: TimEngine](t: T): int = 
    ## Get preferred indentation size (2 or 4 spaces). Default 4
    result = t.indent

proc getType*[T: TimlTemplate](t: T): TimlTemplateType =
    result = t.meta.templateType

proc getContents*[T: TimlTemplate](t: T): string =
    ## Retrieve code contents of current TimlTemplate
    result = t.fileContents

proc getName*[T: TimlTemplate](t: T): string =
    ## Retrieve the file name (including extension) of the current TimlTemplate
    result = t.meta.name

proc enableJIT*(t: var TimlTemplate) =
    t.jit = true

proc isJITEnabled*(t: TimlTemplate): bool =
    result = t.jit

proc getPathDir*[T: TimEngine](engine: T, key: string): string =
    if key == "layouts":
        result = engine.paths.layouts
    elif key == "views":
        result = engine.paths.views
    else:
        result = engine.paths.partials

proc isPartial*[T: TimlTemplate](t: T): bool =
    ## Determine if current template is a `partial`
    result = t.timlType == Partial

proc addDependentView*[T: TimlTemplate](t: var T, path: string) =
    ## Add a new view that includes the current partial.
    ## This is mainly used to auto reload (recompile) views
    ## when a partial get modified
    t.dependents.add(path)

proc getDependentViews*[T: TimlTemplate](t: var T): seq[string] =
    ## Retrieve all views that includes the current partial.
    ## Used for recompiling views when in development mode
    result = t.dependents

proc getFilePath*[T: TimlTemplate](t: T): string =
    ## Retrieve the file path of the current TimlTemplate
    result = t.paths.file

proc getFileData*[T: TimlTemplate](t: T): JsonNode =
    ## Retrieve JSON data exposed to TimlTemplate
    result = t.data

proc getSourceCode*[T: TimlTemplate](t: T): string =
    ## Retrieve source code of a TimlTemplate object
    result = readFile(t.paths.file)

proc getHtmlCode*[T: TimlTemplate](t: T): string =
    ## Retrieve the HTML code for given ``TimlTemplate`` object
    ## TODO retrieve source code from built-in memory table
    result = readFile(t.paths.html)

proc getHtmlTailsCode*[T: TimlTemplate](t: T): string =
    ## Retrieve the HTML tags for a layout
    ## TODO retrieve source code from built-in memory table
    result = readFile(t.paths.tails)

proc setAstSource*[T: TimlTemplate](t: var T, ast: string) =
    t.astSource = ast

proc getAstSource*[T: TimlTemplate](t: T): string =
    result = t.astSource

proc hasAnySources*[T: TimEngine](e: T): bool =
    ## Determine if current TimEngine has any TimlDirectory
    ## objects stored in layouts, views or partials fields
    result = len(e.views) != 0

proc getPath[T: TimEngine](e: T, key, pathType: string): string =
    ## Retrieve path key for either a partial, view or layout
    var k: string
    var tree: seq[string]
    result = e.root & "/" & pathType & "/$1"
    if key.endsWith(".timl"):
        k = key[0 .. ^6]
    else:
        k = key
    if key.contains("."):
        tree = k.split(".")
        result = result % [tree.join("/")]
    else:
        result = result % [k]
    result &= ".timl"
    result = normalizedPath(result) # normalize path for Windows

proc getLayouts*[T: TimEngine](e: T): TimlTemplateTable =
    ## Retrieve entire table of layouts as TimlTemplateTable
    result = e.layouts

proc hasLayout*[T: TimEngine](e: T, key: string): bool =
    ## Determine if specified layout exists
    ## Use dot annotation for accessing views in subdirectories
    result = e.layouts.hasKey(e.getPath(key, "layouts"))

proc getLayout*[T: TimEngine](e: T, key: string): TimlTemplate =
    ## Get a layout object as ``TimlTemplate``
    ## Use dot annotation for accessing views in subdirectories
    result = e.layouts[e.getPath(key, "layouts")]

proc getViews*[T: TimEngine](e: T): TimlTemplateTable =
    ## Retrieve entire table of views as TimlTemplateTable
    result = e.views

proc hasView*[T: TimEngine](e: T, key: string): bool =
    ## Determine if a specific view exists by name.
    ## Use dot annotation for accessing views in subdirectories
    result = e.views.hasKey(e.getPath(key, "views"))

method getView*(e: TimEngine, key: string): TimlTemplate {.base.} =
    ## Retrieve a view template by key.
    ## Use dot annotation for accessing views in subdirectories
    result = e.views[e.getPath(key, "views")]

method hasPartial*(e: TimEngine, key: string): bool {.base.} =
    ## Determine if a specific view exists by name.
    ## Use dot annotation for accessing views in subdirectories
    result = e.partials.hasKey(e.getPath(key, "partials"))

method getPartials*(e: TimEngine): TimlTemplateTable {.base.} =
    ## Retrieve entire table of partials as TimlTemplateTable
    result = e.partials

method getStoragePath*(e: var TimEngine): string {.base.} =
    ## Retrieve the absolute path of TimEngine output directory
    result = e.output

method getBsonPath*(e: TimlTemplate): string {.base.} = 
    ## Get the absolute path of BSON AST file
    result = e.paths.ast

method shouldMinify*(e: TimEngine): bool {.base.} =
    ## Determine if Tim Engine should minify the final HTML
    result = e.minified

proc hashTail(input: string): string =
    ## Create a MD5 hashed version of given input string
    result = getMD5(input)

proc bsonPath(outputDir, filePath: string): string =
    ## Set the BSON AST path and return the string
    result = outputDir & "/bson/" & hashTail(filePath) & ".ast.bson"
    normalizePath(result)

proc htmlPath(outputDir, filePath: string, isTail = false): string =
    ## Set the HTML output path and return the string
    var suffix = if isTail: "_" else: ""
    result = outputDir & "/html/" & hashTail(filePath) & suffix & ".html"
    normalizePath(result)

proc getTemplateByPath*[T: TimEngine](engine: T, filePath: string): var TimlTemplate =
    ## Return `TimlTemplate` object representation for given file `filePath`
    let fp = normalizedPath(filePath)
    if engine.views.hasKey(fp):
        result = engine.views[fp]
    elif engine.layouts.hasKey(fp):
        result = engine.layouts[fp]
    else:
        result = engine.partials[fp]

proc writeBson*[E: TimEngine, T: TimlTemplate](e: E, t: T, ast: string, baseIndent: int) =
    ## Write current JSON AST to BSON
    var document = newBsonDocument()
    document["ast"] = ast
    document["version"] = timVersion
    document["baseIndent"] = baseIndent
    writeFile(t.paths.ast, document.bytes)

proc checkDocVersion(docVersion: string): bool =
    let docv = parseInt replace(docVersion, ".", "")
    let currv = parseInt replace(timVersion, ".", "")
    result = sgn(docv - currv) != -1

method getReloadType*(engine: TimEngine): HotReloadType {.base.} =
    result = engine.reloader

proc readBson*[E: TimEngine, T: TimlTemplate](e: E, t: T): string =
    ## Read current BSON and parse to JSON
    let document: Bson = newBsonDocument(readFile(t.paths.ast))
    let docv: string = document["version"]
    if not checkDocVersion(docv):
        raise newException(TimDefect,
            "This template has been compiled with an older version ($1) of Tim Engine. Please upgrade to $2" % [docv, timVersion])
    result = document["ast"]

proc writeHtml*[E: TimEngine, T: TimlTemplate](e: E, t: T, output: string, isTail = false) =
    let filePath = if not isTail: t.paths.html else: t.paths.tails
    writeFile(filePath, output)

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
    ## on Windows is making use of walkDirRec's Nim iterator.
    when defined windows:
        var files: seq[string]
        for file in walkDirRec(path):
            if file.isHidden(): continue
            if file.endsWith(".timl"):
                files.add(file)
        result = files
    else:
        var args: seq[string] = findArgs
        args.insert(path, 0)
        var files = cmd("find", args).strip()
        if files.len == 0: # "Unable to find any files at given location"
            result = @[]
        else:
            for file in files.split("\n"):
                if file.isHidden(): continue
                result.add file

proc init*(timEngine: var TimEngine, source, output: string,
            indent: int, minified = true, reloader: HotReloadType = None) =
    ## Initialize a new Tim Engine by providing the root path directory 
    ## to your templates (layouts, views and partials).
    ## Tim is able to auto-discover your .timl files
    var timlInOutDirs: seq[string]
    for path in @[source, output]:
        var tpath = path
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

    var LayoutsTable, ViewsTable, PartialsTable = newOrderedTable[string, TimlTemplate]()
    for tdir in @["views", "layouts", "partials"]:
        var tdirpath = timlInOutDirs[0] & "/" & tdir
        if dirExists(tdirpath):
            # TODO look for .timl files only
            let files = finder(findArgs = @["-type", "f", "-print"], path = tdirpath)
            if files.len != 0:
                for f in files:
                    let fname = splitPath(f)
                    var filePath = f
                    filePath.normalizePath()
                    case tdir:
                        of "layouts":
                            LayoutsTable[filePath] = TimlTemplate(
                                timlType: Layout,
                                meta: (name: fname.tail, templateType: Layout),
                                paths: (
                                    file: filePath,
                                    ast: bsonPath(timlInOutDirs[1], filePath),
                                    html: htmlPath(timlInOutDirs[1], filePath),
                                    tails: htmlPath(timlInOutDirs[1], filePath, true)
                                )
                            )                            
                        of "views":
                            ViewsTable[filePath] = TimlTemplate(
                                timlType: View,
                                meta: (name: fname.tail, templateType: View),
                                paths: (
                                    file: filePath,
                                    ast: bsonPath(timlInOutDirs[1], filePath),
                                    html: htmlPath(timlInOutDirs[1], filePath),
                                    tails: htmlPath(timlInOutDirs[1], filePath, true)
                                )
                            )
                        of "partials":
                            PartialsTable[filePath] = TimlTemplate(
                                timlType: Partial,
                                meta: (name: fname.tail, templateType: Partial),
                                paths: (
                                    file: filePath,
                                    ast: bsonPath(timlInOutDirs[1], filePath),
                                    html: htmlPath(timlInOutDirs[1], filePath),
                                    tails: htmlPath(timlInOutDirs[1], filePath, true)
                                )
                            )
        else:
            createDir(tdirpath) # create `layouts`, `views`, `partials` directories

    var
        rootPath = timlInOutDirs[0]
        outputPath = timlInOutDirs[1]
    rootPath.normalizePath()
    outputPath.normalizePath()
    timEngine = TimEngine(
        root: rootPath,
        output: outputPath,
        layouts: LayoutsTable,
        views: ViewsTable,
        partials: PartialsTable,
        minified: minified,
        indent: indent,
        paths: (
            layouts: rootPath & "/layouts",
            views: rootPath & "/views",
            partials: rootPath & "/partials"
        )
    )

    when not defined release:
        # Enable Hot Reloader when in dev mode
        timEngine.reloader = reloader
