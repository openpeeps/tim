# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[osproc, os]
import pkg/flatty
import pkg/kapsis/[runtime, cli]

import ../engine/[parser, ast]
import ../engine/compilers/nimc
import ../server/dynloader

proc binCommand*(v: Values) =
  ## Execute Just-in-Time compilation of the specifie
  let
    cachedPath = v.get("ast").getPath.path
    cachedAst = readFile(cachedPath)
    c = nimc.newCompiler(fromFlatty(cachedAst, Ast), true)
  var
    genFilepath = cachedPath.changeFileExt(".nim")
    genFilepathTuple = genFilepath.splitFile()
  # nim requires that module name starts with a letter
  genFilepathTuple.name = "r_" & genFilepathTuple.name
  genFilepath = genFilepathTuple.dir / genFilepathTuple.name & genFilepathTuple.ext
  let dynlibPath = cachedPath.changeFileExt(".dylib")
  writeFile(genFilepath, c.exportCode())
  # if not dynlibPath.fileExists:
  let status = execCmdEx("nim c --mm:arc -d:danger --opt:speed --app:lib --noMain -o:" & dynlibPath & " " & genFilePath)
  if status.exitCode > 0:
    return # nim compilation error  
  removeFile(genFilepath)
  var collection = DynamicTemplates()
  let hashedName = cachedPath.splitFile.name
  collection.load(hashedName)
  echo collection.render(hashedName)
  collection.unload(hashedName)