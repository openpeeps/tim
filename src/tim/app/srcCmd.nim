# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, strutils]
import pkg/kapsis/[cli, runtime] 
import ../engine/parser
import ../engine/logging
import ../engine/compilers/[html, nimc]

proc srcCommand*(v: Values) = 
  ## Transpiles a `.timl` file to a target source
  let
    fpath = v.get("timl").getStr
    ext = v.get("ext").getStr
    pretty = v.has("pretty")
    # enableWatcher = v.has("w")
  var
    name: string
    timlCode: string
  if v.has"code":
    timlCode = fpath
  else:
    name = fpath
    timlCode = readFile(getCurrentDir() / fpath)
  let p = parseSnippet(name, timlCode)
  if likely(not p.hasErrors):
    if ext == "html":
      let c = html.newCompiler(parser.getAst(p), pretty == false)
      if likely(not c.hasErrors):
        display c.getHtml().strip
        discard
      else:
        for err in c.logger.errors:
          display err
        displayInfo c.logger.filePath
        quit(1)
    elif ext == "nim":
      let c = nimc.newCompiler(parser.getAst(p))
      display c.exportCode()
    else:
      displayError("Unknown target `" & ext & "`")
      quit(1)
  else:
    for err in p.logger.errors:
      display(err)
    displayInfo p.logger.filePath
    quit(1)