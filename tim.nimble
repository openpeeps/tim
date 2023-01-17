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
requires "sass"

requires "nyml"
requires "klymene"

task tests, "Run tests":
    exec "testament p 'tests/*.nim'"

task dev, "Compile Tim":
    echo "\n✨ Compiling..." & "\n"
    exec "nim --gc:arc --out:bin/tim --hints:off --threads:on c src/tim.nim"

task prod, "Compile Tim for release":
    echo "\n✨ Compiling..." & $version & "\n"
    exec "nim --gc:arc --threads:on -d:release -d:danger --hints:off --opt:speed --checks:off --out:bin/tim c src/tim.nim"

task wasm, "Compile Tim to WASM":
    echo "\n✨ Compiling..." & "\n"
    exec "nlvm c --cpu:wasm32 --os:standalone -d:release --gc:none -d:useMalloc --passl:-Wl,--no-entry src/tim/wasm.nim"