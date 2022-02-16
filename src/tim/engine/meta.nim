# High-performance, compiled template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim
import std/[tables, json]
from std/strutils import `%`, strip, split
from std/osproc import execProcess, poStdErrToStdOut, poUsePath
from std/os import getCurrentDir, normalizePath, dirExists,
                   fileExists, walkDirRec, splitPath

type 
    TimlTemplateType = enum
        Layout, View, Partial

    TimlTemplateTable = OrderedTable[string, TimlTemplate]
    TimlDirectoryTable = Table[string, TimlDirectory]

    TimlTemplate* = object
        fileName: string
        filePath: string
        fileType: TimlTemplateType                     # type of TimlTemplate, either Layout, View or Partial
        fileContents: string                           # contents of current .timl file
        fileData: JsonNode                             # JSON data exposed to TimlTemplate

    TimlDirectory = object
        path: string                                   # path on disk
        templates: TimlTemplateTable                   # table containing all TimlTemplate objects

    TimEngine* = object
        root: string                                    # root path to your Timl templates
        src: TimlDirectoryTable                         # table containing all TimlDirectory objects

    TimlException* = object of CatchableError

proc getContents*[T: TimlTemplate](t: T): string =
    ## Retrieve code contents of current TimlTemplate
    result = t.fileContents

proc getFileName*[T: TimlTemplate](t: T): string =
    ## Retrieve the file name (including extension) of the current TimlTemplate
    result = t.fileName

proc getFilePath*[T: TimlTemplate](t: T): string =
    ## Retrieve the file path of the current TimlTemplate
    result = t.filePath

proc getFileData*[T: TimlTemplate](t: T): JsonNode =
    ## Retrieve JSON data exposed to TimlTemplate
    result = t.fileData

proc getSources*[T: TimEngine](e: var T): TimlDirectoryTable =
    ## Retrieves all TimlDirectory objects as TimlDirectoryTable (Table[string, TimlDirectory])
    result = e.src

proc getSources*[T: TimEngine](e: var T, key: string): TimlDirectory =
    ## Retrieve a specific TimlDirectory object source, based on given key,
    ## where key can be either `layouts`, `views`, or `partials`
    let sources = e.getSources()
    if e.src.hasKey(key):
        result = e.src[key]
    else: raise newException(TimlException,
        "Unable to find a TimlDirectoryTable for \"$1\" key")

proc getLayouts*[T: TimEngine](e: var T): TimlDirectory =
    ## Retrieve entire table of layouts as TimlDirectory
    result = e.getSources("layouts")

proc getViews*[T: TimEngine](e: var T): TimlDirectory =
    ## Retrieve entire table of views as TimlDirectory
    result = e.getSources("views")

proc getPartials*[T: TimEngine](e: var T): TimlDirectory =
    ## Retrieve entire table of partials as TimlDirectory
    result = e.getSources("partials")

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

proc init*[T: typedesc[TimEngine]](timEngine: T, templates, storage: string, hotreload: bool): TimEngine =
    ## Initialize a new Tim Engine by providing the root path directory 
    ## to your templates (layouts, views and partials).
    ## Tim is able to auto-discover your .timl files
    var timlInOutDirs: seq[string]
    for path in @[templates, storage]:
        var tpath = getCurrentDir() & "/" & path
        tpath.normalizePath()
        if not tpath.dirExists(): raise newException(TimlException,
            "Unable to find templates directory at\n$1" % [tpath])
        timlInOutDirs.add(path)

    var e = timEngine()
    e.root = timlInOutDirs[0]
    for tdir in @["layouts", "views", "partials"]:
        let tdirpath = timlInOutDirs[0] & "/" & tdir
        if dirExists(tdirpath):
            var timlDir = TimlDirectory(path: tdirpath)
            let files = finder(findArgs = @["-type", "f", "-print"], path = tdirpath)
            if files.len != 0:
                for f in files:
                    let filename = splitPath(f)
                    var fileType: TimlTemplateType
                    case tdir:
                        of "layouts": fileType = Layout
                        of "views": fileType = View
                        of "partials": fileType = Partial
                    var timlTemplate = TimlTemplate(fileName: filename.tail, filePath: f, fileType: fileType)
                    timlDir.templates[filename.tail] = timlTemplate
                    e.src[tdir] = timlDir
    result = e

# proc addLayout*[T: TimEngine](engine: T, page: TimlPage) =
#     ## Add a new Timl layout to current Engine instance

proc add*[T: TimEngine](pageType: TimlTemplateType) =
    ## Add a new Timl layout, view or partial to current Engine instance
    discard