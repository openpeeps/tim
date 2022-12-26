# Package

version       = "0.1.2"
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
requires "klymene"

task tests, "Run tests":
    exec "testament p 'tests/*.nim'"

task dev, "Compile Tim":
    echo "\n✨ Compiling..." & "\n"
    exec "nim --gc:arc --out:bin/tim --hints:off --threads:on c src/tim.nim"

task prod, "Compile Tim for release":
    echo "\n✨ Compiling..." & $version & "\n"
    exec "nim --gc:arc --threads:on -d:release -d:danger --hints:off --opt:speed --checks:off --out:bin/tim c src/tim.nim"