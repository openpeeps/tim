import ../[chunk, codegen, ast, parser, sym, value]

proc compileCode*(script: Script, module: Module, filename, code: string) =
  ## Compile some hayago code to the given script and module.
  ## Any generated toplevel code is discarded. This should only be used for
  ## declarations of hayago-side things, eg. iterators.
  var astProgram: Ast
  parser.parseScript(astProgram, code)
  var
    codeChunk = newChunk()
    gen = initCodeGen(script, module, codeChunk)
  gen.genScript(astProgram)

const
  InlineCode* = """
iterator `..`*(min: int, max: int): int {
  var i = min
  while $i <= max {
    yield($i)
    $i = $i + 1
  }
}
  """