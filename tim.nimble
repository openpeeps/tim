# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "High-performance, compiled template engine inspired by Emmet syntax"
license       = "MIT"
srcDir        = "src"
bin           = @["tim"]
binDir        = "bin"

# Dependencies

requires "nim >= 1.6.0"
# requires "toktok"
requires "watchout"                 # required for compiling Timl to AST on live changes
requires "bson"                     # required for building the AST to BSON
requires "jsony"
# requires "klymene"                # required for compiling Timl as a binary CLI


after build:
    exec "clear"

task cli, "Compile for command line":
    exec "nimble build c src/cli.nim --gc:arc "
    exec "nim -d:release --gc:arc --threads:on -d:useMalloc --opt:size --spellSuggest --out:bin/tim --opt:size c src/cli"

task dev, "Compile Tim":
    echo "\n✨ Compiling..." & "\n"
    exec "nimble build --gc:arc -d:useMalloc"

task prod, "Compile Tim for release":
    echo "\n✨ Compiling..." & $version & "\n"
    exec "nimble build --gc:arc --threads:on -d:release -d:useMalloc --opt:size --spellSuggest"