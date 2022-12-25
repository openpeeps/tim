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
requires "watchout"

task tests, "Run tests":
    exec "testament p 'tests/*.nim'"

task cli, "Build Tim CLI":
    exec "nimble build c src/cli.nim --gc:arc "
    exec "nim -d:release --gc:arc --threads:on -d:useMalloc --opt:size --spellSuggest --out:bin/tim_cli c src/cli"

task dev, "Compile Tim":
    echo "\n✨ Compiling..." & "\n"
    exec "nim --gc:arc --out:bin/tim --hints:off --threads:on c src/tim.nim"

task prod, "Compile Tim for release":
    echo "\n✨ Compiling..." & $version & "\n"
    exec "nim --gc:arc --threads:on -d:release -d:danger --hints:off --opt:speed --checks:off --panics:on --out:bin/tim c src/tim.nim"