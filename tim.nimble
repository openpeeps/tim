# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "High-performance compiled template engine inspired by Emmet syntax"
license       = "MIT"
srcDir        = "src"
bin           = @["tim"]
binDir        = "bin"

# Dependencies

requires "nim >= 1.6.0"

task dev, "Compile Tim":
    echo "\n✨ Compiling..." & "\n"
    exec "nimble build --gc:arc -d:useMalloc"

task prod, "Compile Tim for release":
    echo "\n✨ Compiling..." & $version & "\n"
    exec "nimble build --gc:arc --threads:on -d:release -d:useMalloc --opt:size --spellSuggest"