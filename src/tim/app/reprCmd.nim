import std/[os, strutils]
import pkg/flatty
import pkg/kapsis/[cli, runtime]
import ../engine/[parser, ast]
import ../engine/compilers/[html, nimc]

proc reprCommand*(v: Values) =
  ## Read a binary AST to target source
  let fpath = v.get("ast").getPath.path
  let ext = v.get("ext").getStr
  let pretty = v.has("pretty")
  if ext == "html":
    let c = html.newCompiler(flatty.fromFlatty(readFile(fpath), Ast), pretty == false)
    display c.getHtml().strip
  elif ext == "nim":
    let c = nimc.newCompiler(flatty.fromFlatty(readFile(fpath), Ast))
    display c.exportCode()
  else:
    displayError("Unknown target `" & ext & "`")
    quit(1)