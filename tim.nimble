# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "A super fast template engine for cool kids!"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["tim"]


# Dependencies

requires "nim >= 2.0.0"
requires "toktok"
requires "jsony"
requires "https://github.com/openpeeps/importer"
requires "watchout#head"
requires "kapsis#head"
requires "denim#head"
requires "checksums"
requires "flatty"
requires "supersnappy"
# requires "httpx"
# requires "websocketx"

task node, "Build a NODE addon":
  exec "denim build src/tim.nim --cmake --yes"

task example, "Build example":
  exec "nim c -d:timHotCode --threads:on --mm:arc -o:./bin/app example/app.nim"

task pexample, "Build example":
  exec "nim c -d:timHotCode -d:danger --passC:-flto --threads:on --mm:arc -o:./bin/app example/app.nim"