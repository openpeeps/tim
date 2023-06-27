# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "High-performance, compiled template engine inspired by Emmet syntax"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["tim"]
binDir        = "bin"

# Dependencies

requires "nim >= 1.6.0"
requires "pkginfo"
requires "toktok"
requires "jsony"
requires "watchout"
requires "nyml"
requires "kapsis"
requires "denim"
requires "msgpack4nim#head"

task tests, "Run tests":
  exec "testament p 'tests/*.nim'"

task dev, "Dev build":
  exec "nimble build"

task prod, "Release build":
  exec "nimble build -d:release"

task emsdk, "Build a .wasm via Emscripten":
  exec "nim c -d:emscripten src/tim.nim"

task napi, "Compile Tim via NAPI":
  exec "denim build src/tim.nim --cmake --release --yes"