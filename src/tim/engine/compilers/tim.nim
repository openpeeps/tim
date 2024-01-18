type
  TimCompiler* = object of RootObj
    ast: Ast
    tpl: TimTemplate
    nl: string = "\n"
    output, jsOutput, jsonOutput,
      yamlOutput, cssOutput: string
    start: bool
    case tplType: TimTemplateType
    of ttLayout:
      head: string
    else: discard
    logger*: Logger
    indent: int = 2
    minify, hasErrors: bool
    stickytail: bool
      # when `false` inserts a `\n` char
      # before closing the HTML element tag.
      # Does not apply to `textarea`, `button` and other
      # self closing tags (such as `submit`, `img` and so on)