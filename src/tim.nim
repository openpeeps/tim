import tim/parser

when isMainModule:
    var p: Parser = parse(readFile("sample.txt"))
    if p.hasError(): echo p.getError()
    else: echo p.getStatements()