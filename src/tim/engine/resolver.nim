# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import toktok
import std/[streams, tables, ropes]

from std/strutils import endsWith, `%`, indent
from std/os import getCurrentDir, parentDir, fileExists, normalizedPath

tokens:
    Import > '@'

type
    Importer = object
        lex: Lexer
        rope: Rope
        error: string
        currentFilePath: string
        current, next: TokenTuple
        partials: OrderedTable[int, tuple[indent: int, code: string]]

template jump[I: Importer](p: var I, offset = 1) =
    var i = 0
    while offset != i: 
        p.current = p.next
        p.next = p.lex.getToken()
        inc i

template loadPartial[T: Importer](p: var T, indent: int) =
    var filepath = p.current.value
    let dirpath = p.currentFilePath.parentDir()
    filepath = if not filepath.endsWith(".timl"): filepath & ".timl" else: filepath
    let partialPath = normalizedPath(dirpath & "/" & filepath)
    if not fileExists(partialPath):
        p.error = "File not found for \"$1\"" % [filepath]
    else:
        p.partials[p.current.line] = (indent, readFile(partialPath))

template findPartial[T: Importer](p: var T) =
    if p.current.kind == TK_UNKNOWN:
        inc p.lex
    if p.current.kind == TK_IMPORT:
        let indent = p.current.col
        if p.next.kind != TK_IDENTIFIER or p.next.value != "import":
            p.error = "Invalid import statement"
            break
        jump p
        if p.next.kind != TK_STRING:
            p.error = "Invalid import statement missing file path."
            break
        jump p
        loadPartial(p, indent)

proc resolvePartials*(viewCode: string, currentFilePath: string): string =
    ## Resolve ``@import`` statements in main view code.
    var p = Importer(lex: Lexer.init(viewCode), currentFilePath: currentFilePath)
    var partials: seq[string]
    p.current = p.lex.getToken()
    p.next = p.lex.getToken()
    while p.error.len == 0 and p.current.kind != TK_EOF:
        p.findPartial()
        jump p

    if p.error.len != 0:
        echo p.error # todo

    var codeStream = newStringStream(viewCode)
    var lineno = 1
    for line in lines(codeStream):
        if p.partials.hasKey(lineno):
            let indentSize = p.partials[lineno].indent
            p.rope.add indent(p.partials[lineno].code, p.partials[lineno].indent)
            p.rope.add "\n"
        else:
            p.rope.add line & "\n"
        inc lineno
    result = $p.rope