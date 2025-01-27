# Package

version       = "0.1.3"
author        = "OpenPeeps"
description   = "A super fast template engine for cool kids!"
license       = "LGPLv3"
srcDir        = "src"
skipDirs      = @["example", "editors", "bindings"]
installExt    = @["nim"]
bin           = @["tim"]
binDir        = "bin"

# Dependencies

requires "nim >= 2.0.0"
requires "toktok#head"
requires "https://github.com/openpeeps/importer"
# requires "importer#head"
requires "watchout#head"
requires "kapsis#head"
requires "denim#head"
requires "checksums"
requires "jsony"
requires "flatty#head"
requires "nyml >= 0.1.8"
# requires "marvdown#head"
requires "urlly >= 1.1.1"
requires "semver >= 1.2.2"
requires "dotenv"
requires "genny >= 0.1.0"
requires "htmlparser"

# Required for running Tim Engine as a
# microservice frontend application
requires "httpbeast#head"

task node, "Build a NODE addon":
  exec "denim build src/tim.nim --cmake --yes"

import std/os

task examples, "build all examples":
  for e in walkDir(currentSourcePath().parentDir / "example"):
    let x = e.path.splitFile
    if x.name.startsWith("example_") and x.ext == ".nim":
      exec "nim c -d:timHotCode --threads:on -d:watchoutBrowserSync --deepcopy:on --mm:arc -o:./bin/" & x.name & " example/" & x.name & x.ext

task example, "example httpbeast + tim":
  exec "nim c -d:timHotCode -d:watchoutBrowserSync --deepcopy:on --threads:on --mm:arc -o:./bin/example_httpbeast example/example_httpbeast.nim"

task examplep, "example httpbeast + tim release":
  exec "nim c -d:timStaticBundle -d:release --threads:on --mm:arc -o:./bin/example_httpbeast example/example_httpbeast.nim"

task dev, "build a dev cli":
  exec "nimble build -d:timStandalone"

task prod, "build a prod cli":
  exec "nimble build -d:release -d:timStandalone"

task staticlib, "Build Tim Engine as Static Library":
  exec "nimble c --app:staticlib -d:release"

task swig, "Build C sources from Nim":
  exec "nimble --noMain --noLinking -d:timHotCode --threads:on -d:watchoutBrowserSync -d:timSwig --deepcopy:on --mm:arc --header:tim.h --nimcache:./bindings/_source cc -c src/tim.nim"