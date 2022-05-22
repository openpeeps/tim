# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "High-performance, compiled template engine inspired by Emmet syntax"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 1.6.0"
requires "toktok"
requires "bson"
requires "jsony"
requires "emitter"

task tests, "Run tests":
    exec "testament p 'tests/*.nim'"

task cli, "Compile for command line":
    exec "nimble build c src/cli.nim --gc:arc "
    exec "nim -d:release --gc:arc --threads:on -d:useMalloc --opt:size --spellSuggest --out:bin/tim_cli c src/cli"

task dev, "Compile Tim":
    echo "\n✨ Compiling..." & "\n"
    exec "nim --gc:arc -d:useMalloc --out:bin/tim --hints:off c src/tim.nim"

task prod, "Compile Tim for release":
    echo "\n✨ Compiling..." & $version & "\n"
    exec "nim --gc:arc --threads:on -d:release -d:useMalloc --hints:off --opt:size --spellSuggest --out:bin/tim cpp src/tim.nim"