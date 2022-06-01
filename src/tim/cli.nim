# High-performance, compiled template engine inspired by Emmet syntax.
# 
# This is the Command Line Interface of Tim Engine
# Built with Klymene -- https://github.com/openpeep/klymene 
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import klymene
import tim/commands/compileCommand

about:
    "A High-performance, compiled template engine inspired by Emmet syntax"
    "Made by Humans from OpenPeep"
    version "0.1.0"

commands:
    $ "init"          "Initialize Tim in your project"
    $ "compile"       "Compile your Tim templates to HTML or BSON"