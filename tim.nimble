# Package

version       = "0.2.1"
author        = "OpenPeeps"
description   = "A super fast template engine for cool kids!"
license       = "LGPL-3.0-or-later"
srcDir        = "src"
skipDirs      = @["example", "editors", "bindings"]
installExt    = @["nim"]
bin           = @["tim"]
binDir        = "bin"

# Dependencies

requires "nim >= 2.0.0"

requires "kapsis#head"
requires "vancode#head"
requires "flatty"
requires "checksums"  
requires "semver"
requires "voodoo#head"
requires "watchout"
requires "openparser#head"
# requires "marvdown#head"
# requires "supranim#head"

task dev, "build a dev version":
  exec "nimble build --mm:orc -d:useMalloc"

task napi, "build a dev version":
  exec "denim build src/tim.nim --cmake -y"

task devlog, "build a dev version":
  exec "nimble build --mm:arc -d:hayaVmWriteStackOps -d:hayaVmWritePcFlow -d:timLogCodeGen -d:useMalloc"

import std/os
task build_examples, "build examples":
  for e in walkDir(currentSourcePath().parentDir / "example"):
    let x = e.path.splitFile
    if x.name.startsWith("example_") and x.ext == ".nim" and not x.name.startsWith("!"):
      exec "nim c -d:timHotCode --threads:on --deepcopy:on --mm:arc -o:./example/" & x.name & " example/" & x.name & x.ext
