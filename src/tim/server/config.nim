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