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
include ./tasks/dev