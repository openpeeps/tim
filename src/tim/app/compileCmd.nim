import std/[os, strutils]
import pkg/kapsis/[cli, runtime] 
import ../engine/[parser, compilers/html]

proc cCommand*(v: Values) = 
  ## Transpiles a `.timl` file to a target source
  let fpath = v.get("timl").getPath.path
  let p = parseSnippet(fpath, readFile(getCurrentDir() / fpath))
  if likely(not p.hasErrors):
    let c = newCompiler(parser.getAst(p), false)
    display(c.getHtml().strip)