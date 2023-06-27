# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "High-performance, compiled template engine inspired by Emmet syntax"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["tim"]

# Dependencies

requires "nim >= 1.6.0"
requires "pkginfo"
requires "toktok"
requires "jsony"
requires "watchout"
# requires "sass#head"
requires "nyml"
requires "kapsis"
requires "denim"
requires "msgpack4nim#head"

task tests, "Run tests":
  exec "testament p 'tests/*.nim'"

task dev, "Compile Tim":
  echo "\n✨ Compiling..." & "\n"
  exec "nim --gc:arc --out:bin/tim --hints:off -d:cli --threads:on c src/tim.nim"

task prod, "Compile Tim for release":
  echo "\n✨ Compiling..." & $version & "\n"
  exec "nim c --gc:arc --out:bin/tim --threads:on -d:release -d:danger --hints:off --opt:speed --checks:off src/tim.nim"

task emsdk, "Compile Tim with Emscripten":
  exec "nim c -d:emscripten src/tim.nim"

task napi, "Compile Tim via NAPI":
  exec "denim build src/tim.nim --cmake --release --yes"