# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "Really lightweight template engine"
license       = "MIT"
srcDir        = "src"
bin           = @["tim"]
binDir        = "bin"

# Dependencies

requires "nim >= 1.6.0"
include ./tasks/dev