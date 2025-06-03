# Package

version       = "0.2.0"
author        = "OpenPeeps"
description   = "A super fast template engine for cool kids!"
license       = "LGPLv3"
srcDir        = "src"
skipDirs      = @["example", "editors", "bindings"]
installExt    = @["nim"]
bin           = @["tim"]
binDir        = "bin"

# Dependencies

requires "nim >= 2.2.0"

requires "toktok#head"
requires "kapsis#head"
requires "htmlparser"
requires "jsony"
requires "flatty"

# requires "microparsec"

task dev, "build a dev version":
  exec "nimble build --mm:orc -d:useMalloc"

task devlog, "build a dev version":
  exec "nimble build --mm:arc -d:hayaVmWriteStackOps -d:hayaVmWritePcFlow -d:timLogCodeGen -d:useMalloc"

task prod, "build a dev version":
  exec "nimble build --mm:arc -d:release --opt:speed -d:useMalloc"