import std/[os, strutils]
import pkg/flatty
import pkg/kapsis/[cli, runtime]
import ../engine/[parser, ast, compilers/html]

proc reprCommand*(v: Values) =
  ## Read a binary AST to target source
  let fpath = v.get("ast").getPath.path
  let c = newCompiler(flatty.fromFlatty(readFile(fpath), Ast), false)
  if likely(not c.hasErrors):
    display(c.getHtml().strip)