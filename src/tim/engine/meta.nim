# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import bson
import std/[tables, json, md5, macros]

from std/math import sgn
from std/strutils import `%`, strip, split, contains, join, endsWith, replace, parseInt
from std/osproc import execProcess, poStdErrToStdOut, poUsePath
from std/os import getCurrentDir, normalizePath, normalizedPath, dirExists,
                   fileExists, walkDirRec, splitPath, createDir,
                   isHidden

type 
    TimlTemplateType* = enum
        Layout = "layout"
        View = "view"
        Partial = "partial"

    TimlTemplate* = object
        id: string
        jit: bool
        case timlType: TimlTemplateType
        of Partial:
            dependents: seq[string]                ## a sequence containing all views that include this partial
        else: discard
        meta: tuple[name: string, templateType: TimlTemplateType]
            ## name of the current TimlTemplate representing file name
            ## type of TimlTemplate, either Layout, View or Partial
        astSource*: string
        paths: tuple[file, ast, html, tails: string]
    
    TimlTemplateTable = OrderedTableRef[string, TimlTemplate]

    HotReloadType* = enum
        None, HttpReloader, WsReloader

    Globals* = object of RootObj

    TimBackend* = enum
        JIT, SCF

    TimEngine* = object
        case backend: TimBackend
        of JIT: globalData: JsonNode
        of SCF: globalScfData: Globals
        root: string
            ## root path to your Timl templates
        output: string
            ## root path for HTML and BSON AST output
        layouts: TimlTemplateTable
            ## a table representing `.timl` layouts
        views: TimlTemplateTable
            ## a table representing `.timl` views
        partials: TimlTemplateTable
            ## a table representing `.timl` partials
        minified: bool
            ## whether it should minify the final HTML output
        indent: int
            ## the base indentation (default to 2)
        paths: tuple[layouts, views, partials: string]
        reloader: HotReloadType

    SyntaxError* = object of CatchableError      # raise errors from Tim language
    TimDefect* = object of CatchableError

const currentVersion = "0.1.0"

proc getIndent*(t: TimEngine): int = 
    ## Get preferred indentation size (2 or 4 spaces). Default 4
    result = t.indent

proc getType*(t: TimlTemplate): TimlTemplateType =
    result = t.meta.templateType

proc getName*(t: TimlTemplate): string =
    ## Retrieve the file name (including extension)
    # of the current TimlTemplate
    result = t.meta.name

proc getTemplateId*(t: TimlTemplate): string =
    result = t.id

proc setPlaceHolderId*(t: TimlTemplate): string =
    result = "$viewHandle_" & t.id & ""

proc getPlaceholderId*(t: TimlTemplate): string =
    result = "viewHandle_" & t.id & ""

proc enableJIT*(t: var TimlTemplate) =
    t.jit = true

proc isJITEnabled*(t: TimlTemplate): bool =
    result = t.jit

proc getPathDir*(engine: TimEngine, key: string): string =
    if key == "layouts":
        result = engine.paths.layouts
    elif key == "views":
        result = engine.paths.views
    else:
        result = engine.paths.partials

proc isPartial*(t: TimlTemplate): bool =
    ## Determine if current template is a `partial`
    result = t.timlType == Partial

proc addDependentView*(t: var TimlTemplate, path: string) =
    ## Add a new view that includes the current partial.
    ## This is mainly used to auto reload (recompile) views
    ## when a partial get modified
    t.dependents.add(path)

proc getDependentViews*(t: var TimlTemplate): seq[string] =
    ## Retrieve all views included in current partial.
    result = t.dependents

proc getFilePath*(t: TimlTemplate): string =
    ## Retrieve the file path of the current TimlTemplate
    result = t.paths.file

proc getSourceCode*(t: TimlTemplate): string =
    ## Retrieve source code of a TimlTemplate object
    result = readFile(t.paths.file)

proc getHtmlCode*(t: TimlTemplate): string =
    ## Retrieve the HTML code for given ``TimlTemplate`` object
    ## TODO retrieve source code from built-in memory table
    result = readFile(t.paths.html)

proc hasAnySources*(e: TimEngine): bool =
    ## Determine if current TimEngine has any TimlDirectory
    ## objects stored in layouts, views or partials fields
    result = len(e.views) != 0

proc setData*(t: var TimEngine, data: JsonNode) =
    ## Add global data that can be accessed across templates
    t.globalData = data

proc globalDataExists*(t: TimEngine): bool =
    ## Determine if global data is available
    result = t.globalData.kind != JNull

proc getGlobalData*(t: TimEngine): JsonNode =
    ## Retrieves global data
    result = t.globalData

proc getPath(e: TimEngine, key, pathType: string): string =
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

proc getLayouts*(e: TimEngine): TimlTemplateTable =
    ## Retrieve entire table of layouts as TimlTemplateTable
    result = e.layouts

proc hasLayout*(e: TimEngine, key: string): bool =
    ## Determine if specified layout exists
    ## Use dot annotation for accessing views in subdirectories
    result = e.layouts.hasKey(e.getPath(key, "layouts"))

proc getLayout*(e: TimEngine, key: string): TimlTemplate =
    ## Get a layout object as ``TimlTemplate``
    ## Use dot annotation for accessing views in subdirectories
    result = e.layouts[e.getPath(key, "layouts")]

proc getViews*(e: TimEngine): TimlTemplateTable =
    ## Retrieve entire table of views as TimlTemplateTable
    result = e.views

proc hasView*(e: TimEngine, key: string): bool =
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

proc hashName(input: string): string =
    ## Create a MD5 hashed version of given input string
    result = getMD5(input)

proc bsonPath(outputDir, filePath: string): string =
    ## Set the BSON AST path and return the string
    result = outputDir & "/bson/" & hashName(filePath) & ".ast.bson"
    normalizePath(result)

proc htmlPath(outputDir, filePath: string, isTail = false): string =
    ## Set the HTML output path and return the string
    var suffix = if isTail: "_" else: ""
    result = outputDir & "/html/" & hashName(filePath) & suffix & ".html"
    normalizePath(result)

proc getTemplateByPath*(engine: TimEngine, filePath: string): var TimlTemplate =
    ## Return `TimlTemplate` object representation for given file `filePath`
    let fp = normalizedPath(filePath)
    if engine.views.hasKey(fp):
        result = engine.views[fp]
    elif engine.layouts.hasKey(fp):
        result = engine.layouts[fp]
    else:
        result = engine.partials[fp]

proc writeBson*(e: TimEngine, t: TimlTemplate, ast: string, baseIndent: int) =
    ## Write current JSON AST to BSON
    var document = newBsonDocument()
    document["ast"] = ast
    document["version"] = currentVersion
    document["baseIndent"] = baseIndent
    writeFile(t.paths.ast, document.bytes)

proc checkDocVersion(docVersion: string): bool =
    let docv = parseInt replace(docVersion, ".", "")
    let currv = parseInt replace(currentVersion, ".", "")
    result = sgn(docv - currv) != -1

proc getReloadType*(engine: TimEngine): HotReloadType =
    result = engine.reloader

proc readBson*(e: TimEngine, t: TimlTemplate): string =
    ## Read current BSON and parse to JSON
    let document: Bson = newBsonDocument(readFile(t.paths.ast))
    let docv: string = document["version"] # TODO use pkginfo to extract current version from nimble file
    if not checkDocVersion(docv):
        # TODO error message
        raise newException(TimDefect,
            "This template has been compiled with an older version ($1) of Tim Engine. Please upgrade to $2" % [docv, currentVersion])
    result = document["ast"]

proc writeHtml*(e: TimEngine, t: TimlTemplate, output: string, isTail = false) =
    let filePath = if not isTail: t.paths.html else: t.paths.tails
    writeFile(filePath, output)

proc cmd(inputCmd: string, inputArgs: openarray[string]): auto {.discardable.} =
    ## Short hand procedure for executing shell commands via execProcess
    return execProcess(inputCmd, args=inputArgs, options={poStdErrToStdOut, poUsePath})
    # result = staticExec(inputCmd & " " & join(inputArgs, " "))

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
        # if not tpath.dirExists():
        #     createDir(tpath)
        timlInOutDirs.add( getProjectPath() & "/" & path)
        if path == output:
            # create `bson` and `html` dirs inside `output` directory
            # where `bson` is used for saving the binary abstract syntax tree
            # for pages that requires dynamic computation,
            # such as data assignation, and conditional statements,
            # and second the `html` directory is reserved for
            # saving the final HTML output.
            for inDir in @["bson", "html"]:
                let innerDir = path & "/" & inDir
                # if not dirExists(innerDir): createDir(innerDir)

    var LayoutsTable, ViewsTable, PartialsTable = newOrderedTable[string, TimlTemplate]()
    for tdir in @["views", "layouts", "partials"]:
        var tdirpath = timlInOutDirs[0] & "/" & tdir
        # if dirExists(tdirpath):
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
                            id: hashName(filePath),
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
                            id: hashName(filePath),
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
                            id: hashName(filePath),
                            timlType: Partial,
                            meta: (name: fname.tail, templateType: Partial),
                            paths: (
                                file: filePath,
                                ast: bsonPath(timlInOutDirs[1], filePath),
                                html: htmlPath(timlInOutDirs[1], filePath),
                                tails: htmlPath(timlInOutDirs[1], filePath, true)
                            )
                        )
        # else:
            # createDir(tdirpath) # create `layouts`, `views`, `partials` directories

    var rootPath = timlInOutDirs[0]
    var outputPath = timlInOutDirs[1]
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
    when not defined release: # enable auto refresh browser for dev mode
        timEngine.reloader = reloader
