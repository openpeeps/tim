# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, json, strutils]
import pkg/jsony
import pkg/kapsis/[cli, runtime] 

import ../engine/parser
import ../engine/logging
import ../engine/compilers/[html, nimc]

proc srcCommand*(v: Values) = 
  ## Transpiles a `.timl` file to a target source
  let
    fpath = $(v.get("timl").getPath)
    ext = v.get("-t").getStr
    pretty = v.has("--pretty")
    flagNoCache = v.has("--nocache")
    flagRecache = v.has("--recache")
    hasDataFlag = v.has("--data")
    hasJsonFlag = v.has("--json-errors")
    outputPath = if v.has("-o"): v.get("-o").getStr else: ""
    # enableWatcher = v.has("w")
  let jsonData: JsonNode =
    if hasDataFlag: v.get("--data").getJson
    else: nil
  let name = fpath
  let timlCode = readFile(getCurrentDir() / fpath)
  let p = parseSnippet(name, timlCode, flagNoCache, flagRecache)
  if likely(not p.hasErrors):
    if ext == "html":
      let c = html.newCompiler(
        ast = parser.getAst(p),
        minify = (pretty == false),
        data = jsonData
      )
      if likely(not c.hasErrors):
        if outputPath.len > 0:
          writeFile(outputPath, c.getHtml.strip)
        else:
          display c.getHtml().strip
      else:
        if not hasJsonFlag:
          for err in c.logger.errors:
            display err
          displayInfo c.logger.filePath
        else:
          let outputJsonErrors = newJArray()
          for err in c.logger.errorsStr:
            add outputJsonErrors, err
          display jsony.toJson(outputJsonErrors)
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