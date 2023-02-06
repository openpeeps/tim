# A high-performance compiled template engine inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

import ../engine/init
import klymene/runtime

proc runCommand*(v: Values) =
  discard Tim.precompile()