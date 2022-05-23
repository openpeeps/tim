# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import toktok
import std/[streams, tables, ropes]

from std/strutils import endsWith, `%`, indent
from std/os import getCurrentDir, parentDir, fileExists, normalizedPath

import ./tokens

type
    SourcePath = string
    SourceCode = string
    Importer = object
        lex: Lexer
        rope: Rope
        error: string
        currentFilePath: string
        current, next: TokenTuple
        partials: OrderedTable[int, tuple[indentSize: int, source: SourcePath]]
        sources: Table[string, SourceCode]

template jump[I: Importer](p: var I, offset = 1) =
    var i = 0
    while offset != i: 
        p.current = p.next
        p.next = p.lex.getToken()
        inc i

template loadCode[T: Importer](p: var T, indent: int) =
    ## Find ``.timl`` partials and store source contents.
    ## Once requested, a partial code is stored in a
    ## memory ``Table``, so it can be inserted in any view
    ## without calling ``readFile`` again.
    var filepath = p.current.value
    filepath = if not endsWith(filepath, ".timl"): filepath & ".timl" else: filepath
    let dirpath = parentDir(p.currentFilePath)
    let path = normalizedPath(dirpath & "/" & filepath)
    if p.sources.hasKey(path):
        p.partials[p.current.line] = (indent, path)
    else:
        if not fileExists(path):
            p.error = "File not found for \"$1\"" % [filepath]
        else:
            p.sources[path] = readFile(path)
            p.partials[p.current.line] = (indent, path)

template parsePartial[T: Importer](p: var T) =
    ## Look for all ``TK_IMPORT`` tokens and try
    ## to load partial file contents inside of the main view
    if p.current.kind == TK_IMPORT:
        let indent = p.current.col
        if p.next.kind != TK_STRING:
            p.error = "Invalid import statement missing file path."
            break
        jump p
        loadCode(p, indent)

proc resolvePartials*(viewCode: string, currentFilePath: string): string =
    ## Resolve ``@import`` statements in main view code.
    var p = Importer(lex: Lexer.init(viewCode), currentFilePath: currentFilePath)
    p.current = p.lex.getToken()
    p.next = p.lex.getToken()
    while p.error.len == 0 and p.current.kind != TK_EOF:
        p.parsePartial()
        jump p
    if p.error.len != 0:
        echo p.error # todo

    var codeStream = newStringStream(viewCode)
    var lineno = 1
    for line in lines(codeStream):
        if p.partials.hasKey(lineno):
            let path: SourcePath = p.partials[lineno].source
            let code: SourceCode = p.sources[path]
            let indentSize = p.partials[lineno].indentSize
            p.rope.add indent(code, indentSize)
            p.rope.add "\n"
        else:
            p.rope.add line & "\n"
        inc lineno
    result = $p.rope
    # echo $p.rope