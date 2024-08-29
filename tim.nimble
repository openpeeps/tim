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
requires "jsony"
requires "https://github.com/openpeeps/importer"
requires "watchout#head"
requires "kapsis#head"
requires "denim#head"
requires "checksums"
requires "flatty#head"
requires "nyml >= 0.1.8"
requires "zmq#head"

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

task bench, "run some benchmarks":
  exec "nim c --threads:on -d:danger --opt:speed --mm:arc -o:./bin/bench example/benchmark.nim"

task dev, "build a dev cli":
  exec "nimble build -f -d:timStandalone"

task prod, "build a prod cli":
  exec "nimble build -d:release -d:timStandalone"

task fastparser, "testing a parser":
  exec "nimble --mm:arc -d:release c src/timpkg/engine/fastparser.nim -o:./bin/fastparser"

task client, "build udp client":
  exec "nimble c src/timpkg/server/client.nim"