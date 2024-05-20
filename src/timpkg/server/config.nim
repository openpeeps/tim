# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

from std/net import Port, `$`
export `$`

type
  TargetSource* = enum
    tsNim    = "nim"
    tsJS     = "js"
    tsHtml   = "html"
    tsRuby   = "rb"
    tsPython = "py"

  BrowserSync* = ref object
    port*: Port
    delay*: uint # ms

  TimConfig* = ref object
    target*: TargetSource
    source*, output*: string
    sync*: BrowserSync