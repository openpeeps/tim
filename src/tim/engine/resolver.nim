# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import toktok
import std/[streams, tables, ropes]

from ./meta import TimEngine, TimlTemplateType, TimlTemplate,
                    addDependentView, getTemplateByPath, getPathDir
from std/strutils import endsWith, `%`, indent
from std/os import getCurrentDir, parentDir, fileExists, normalizedPath

import ./tokens

type
    SourcePath = string
        ## Partial Source Path
    SourceCode = string
        ## Partial Source Code
    Importer* = object
        lex: Lexer
            ## An instance of TokTok Lexer
        rope: Rope
            ## The entire view containing resolved partials
        error: string
            ## An error message to be shown
        error_line, error_column: int
            ## Error line and column
        error_trace: string
            ## A preview of a ``.timl`` code highlighting error
        currentFilePath: string
            ## The absoulte file path for ``.timl`` view
        current, next: TokenTuple
        partials: OrderedTable[int, tuple[indentSize: int, source: SourcePath]]
            ## An ``OrderedTable`` with ``int`` based key representing
            ## the line of the ``@import`` statement and a tuple-based value.
            ##      - ``indentSize`` field  to preserve indentation size from the view side
            ##      - ``source`` field pointing to an absolute path for ``.timl`` partial.
        sources: Table[SourcePath, SourceCode]
            ## A ``Table`` containing the source code of all imported partials.
        templateType: TimlTemplateType
        partialPath: string
            ## The current `partial` path

const htmlHeadElements = {TK_HEAD, TK_TITLE, TK_BASE, TK_LINK, TK_META, TK_SCRIPT, TK_BODY}

proc hasError*[I: Importer](p: var I): bool =
    result = p.error.len != 0

proc setError*[I: Importer](p: var I, msg: string, path: string) =
    p.error = msg
    p.error_line = p.current.line
    p.error_column = p.current.col
    if p.sources.hasKey(path):
        p.error_trace = p.sources[path]

proc getError*[I: Importer](p: var I): string =
    result = p.error

proc getErrorColumn*[I: Importer](p: var I): int =
    result = p.error_column

proc getErrorLine*[I: Importer](p: var I): int =
    result = p.error_line

proc getFullCode*[I: Importer](p: var I): string =
    result = $p.rope

template jump[I: Importer](p: var I, offset = 1) =
    var i = 0
    while offset != i: 
        p.current = p.next
        p.next = p.lex.getToken()
        inc i

template loadCode[T: Importer](p: var T, engine: TimEngine, indent: int) =
    ## Find ``.timl`` partials and store source contents.
    ## Once requested, a partial code is stored in a
    ## memory ``Table``, so it can be inserted in any view
    ## without calling ``readFile`` again.
    var filepath = p.current.value
    filepath = if not endsWith(filepath, ".timl"): filepath & ".timl" else: filepath
    let dirpath = parentDir(p.currentFilePath)
    let path = engine.getPathDir("partials") & "/" & filepath
    if p.sources.hasKey(path):
        # When included multiple times in a view, will get the
        # partial source code from `sources` table.
        p.partials[p.current.line] = (indent, path)
    else:
        if not fileExists(path):
            p.setError "Could not import \"$1\"" % [filepath], filepath
        else:
            if path == p.currentFilePath:
                p.setError "Cannot import itself", filepath
                break
            p.sources[path] = readFile(path)
            p.partials[p.current.line] = (indent, path)
            getTemplateByPath(engine, path).addDependentView(p.currentFilePath)

template resolveChunks(p: var Importer, engine: TimEngine) =
    if p.templateType in {View, Partial}:
        if p.current.kind in htmlHeadElements:
            p.setError "Views cannot contain Head elements. Use a layout instead", p.currentFilePath
            break
        if p.current.kind == TK_INCLUDE:
            let indent = p.current.col
            if p.next.kind != TK_STRING:
                p.setError "Invalid import statement missing file path.", p.currentFilePath
                break
            jump p
            loadCode(p, engine, indent)

proc resolve*(viewCode, currentFilePath: string,
                        engine: TimEngine, templateType: TimlTemplateType): Importer =
    ## Resolve ``@include`` statements in main view code.
    var p = Importer(lex: Lexer.init(viewCode),
                    currentFilePath: currentFilePath,
                    templateType: templateType)
    p.current = p.lex.getToken()
    p.next = p.lex.getToken()
    while p.error.len == 0 and p.current.kind != TK_EOF:
        p.resolveChunks(engine)
        jump p
    if p.error.len == 0:
        var sourceStream = newStringStream(viewCode)
        var lineno = 1
        for line in lines(sourceStream):
            if p.partials.hasKey(lineno):
                let path: SourcePath = p.partials[lineno].source
                let code: SourceCode = p.sources[path]
                let indentSize = p.partials[lineno].indentSize
                p.rope.add indent(code, indentSize)
                p.rope.add "\n"
            else:
                p.rope.add line & "\n"
            inc lineno
        sourceStream.close()
    result = p