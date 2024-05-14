# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/os
import pkg/flatty
import pkg/kapsis/[cli, runtime] 
import ../engine/[parser, ast, compilers/html]

proc astCommand*(v: Values) =
  ## Build binary AST from a `timl` file
  let fpath = v.get("timl").getPath.path
  let opath = normalizedPath(getCurrentDir() / v.get("output").getFilename)
  let p = parseSnippet(fpath, readFile(getCurrentDir() / fpath))
  if likely(not p.hasErrors):
    writeFile(opath, flatty.toFlatty(parser.getAst(p)))