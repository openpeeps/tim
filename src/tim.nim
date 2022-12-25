# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

# type Global = object of Globals
#     appName*: string
# var d = fromJson($data, Global)

# import std/strformat
# include "./tim/view"
# echo renderProductsView(d)

import klymene
import tim/commands/cCommand

about:
    "A High-performance, compiled template engine and markup language inspired by Emmet syntax"
    "Made by Humans from OpenPeeps"
    version "0.1.0"

commands:
    $ "c" ("nim", "js", "php", "python")       "Compile Tim to various languages":
        ? nim                                            "Compiles Tim to Nim language"
        ? js                                             "Compiles Tim to JavaScript or Node"
        ? php                                            "Compiles Tim to PHP"
        ? python                                         "Compiles Tim to Python"