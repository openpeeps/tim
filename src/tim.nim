# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://tim-engine.com

when defined napi_build:
  # Importing Tim Engine as a NAPI module
  import std/[strutils, json]
  import pkg/[denim, jsony, watchout]
  
  import ./tim/pm/init
  
  var timjs: TimEngine
  init proc(module: Module) =
    proc init(src: string, output: string, basepath: string) {.export_napi.} =
      ## Initialize Tim Engine
      timjs = newTim(
        args.get("src").getStr,
        args.get("output").getStr,
        args.get("basepath").getStr
      )

      timjs.precompile(firstRun = true)

    # proc precompile(opts: object) {.export_napi.} =
    #   ## Precompile Tim Engine templates
    #   var globals: JsonNode
    #   var opts: JsoNNode = jsony.fromJson($(args.get"opts"))
      
    #   # extract optional data from opts and expose it to globals
    #   # this data will be available in the template under `$app.` object
    #   if opts.hasKey"data":
    #     globals = opts["data"]
      

elif isMainModule:
  # Building Tim Engine as a CLI application
  import pkg/kapsis
  import pkg/kapsis/[runtime, cli]
  import ./tim/app/[build, dev]
  
  commands:
    #
    # Source to Source commands
    # Used to transpile `timl` code to a specific target source
    # Planning to support: HTML, Nim, JS, PHP, Python, Ruby and more
    #
    -- "Source to Source"
    src path(`timl`),
      string(-t),       # choose a target (default target `html`)
      string(-o),       # save output to file
      ?json(--data),    # pass data to global/local scope
      bool(--nocache),  # tells Tim to import modules and rebuild cache
      bool(--lib),      # wrap template as a dynamic library
      bool(--bench),    # benchmark operations
      bool(--watch):    # enable browser sync on live changes
        ## Transpile `timl` to specific target source
    
    ast path(`timl`):
      ## Transpile timl code to AST representation

    #
    # Development commands
    # Used to manage Tim Engine packages locally
    #
    -- "Development"
    init:
      ## Initializes a new Tim Engine package
    install string(`pkg`):
      ## Install a package from remote source
    remove string(`pkg`):
      ## Remove a package from local source
else:
  # Importing Tim Engine as a Nimble library
  # so it can be used in other Nim projects
  discard # todo