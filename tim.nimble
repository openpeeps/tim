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
requires "toktok >= 0.1.3"
requires "jsony"
requires "https://github.com/openpeeps/importer"
requires "watchout#head"
requires "kapsis#head"
requires "denim#head"
requires "checksums"
requires "flatty#head"
requires "httpx", "websocketx"

task node, "Build a NODE addon":
  exec "denim build src/tim.nim --cmake --yes"

task example, "example httpbeast + tim":
  exec "nim c -d:timHotCode --threads:on --mm:arc -o:./bin/app example/app.nim"

task example2, "example: mummy + tim":
  exec "nim c -d:timHotCode --threads:on --mm:arc -o:./bin/app2 example/app2.nim"
