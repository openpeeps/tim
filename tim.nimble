# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "A super fast template engine for cool kids!"
license       = "MIT"
srcDir        = "src"
skipDirs      = @["example", "editors"]
# installExt    = @["nim"]
# bin           = @["tim"]


# Dependencies

requires "nim >= 2.0.0"
requires "toktok#head"
requires "jsony"
requires "https://github.com/openpeeps/importer"
requires "watchout#head"
requires "kapsis#head"
requires "denim#head"
requires "checksums"
requires "flatty#head"
requires "nyml"
# requires "bro"
requires "httpx", "websocketx"

task node, "Build a NODE addon":
  exec "denim build src/tim.nim --cmake --yes"

import std/os

task examples, "build all examples":
  for e in walkDir(currentSourcePath().parentDir / "example"):
    let x = e.path.splitFile
    if x.name.startsWith("example_") and x.ext == ".nim":
      exec "nim c -d:timHotCode --threads:on --mm:arc -o:./bin/" & x.name & " example/" & x.name & x.ext

task example, "example httpbeast + tim":
  exec "nim c -d:timHotCode --threads:on --mm:arc -o:./bin/example_httpbeast example/example_httpbeast.nim"
