# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, osproc, strutils]
import pkg/[nyml, flatty]
import pkg/kapsis/[cli, runtime] 

import ../server/[app, config]
import ../engine/meta

proc newCommand*(v: Values) =
  ## Initialize a new Tim Engine configuration
  ## using current working directory
  discard

proc runCommand*(v: Values) =
  ## Runs Tim Engine as a microservice front-end application.
  let path = absolutePath(v.get("config").getPath.path)
  let config = fromYaml(path.readFile, TimConfig)
  var timEngine =
    newTim(
      config.compilation.source,
      config.compilation.output,
      path.parentDir
    )
  app.run(timEngine, config)

proc buildCommand*(v: Values) =
  ## Initialize a new Tim Engine configuration
  ## using current working directory
  discard

import ../engine/[parser, ast]
import ../engine/compilers/nimc
import ../server/dynloader
proc bundleCommand*(v: Values) =
  ## Bundle Tim templates to shared libraries
  ## for fast plug & serve.
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