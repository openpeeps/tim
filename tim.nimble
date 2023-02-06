# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "High-performance, compiled template engine inspired by Emmet syntax"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 1.6.0"
requires "pkginfo"
requires "toktok"
requires "jsony"
requires "bson"
requires "watchout"
requires "sass#head"
requires "nyml"
requires "klymene"

from os import getHomeDir

# before install:
#   let binDir = getHomeDir() & "/.nimble/bin"
#   exec "nim c --gc:arc --threads:on -d:release -d:danger --hints:off --opt:speed --checks:off -o:" & binDir & "/tim src/tim.nim"

task tests, "Run tests":
  exec "testament p 'tests/*.nim'"

task dev, "Compile Tim":
  echo "\n✨ Compiling..." & "\n"
  exec "nim --gc:arc --skipProjCfg:on --out:bin/tim --hints:off -d:cli --threads:on c src/tim.nim"

task prod, "Compile Tim for release":
  echo "\n✨ Compiling..." & $version & "\n"
  exec "nim c --gc:arc --skipProjCfg:on --out:bin/tim --threads:on -d:release -d:danger --hints:off --opt:speed --checks:off src/tim.nim"

# task wasm, "Compile Tim to WASM": # TODO
#   echo "\n✨ Compiling..." & "\n"
#   exec "nim c --out:bin/tim.wasm src/tim/wasm.nim"
#   # exec "nlvm c --cpu:wasm32 --os:standalone -d:release --gc:none --out:bin/tim.wasm --passl:-Wl,--no-entry  src/tim/wasm.nim"