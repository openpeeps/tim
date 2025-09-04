# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

when defined napi_build:
  # Building Tim Engine as a NAPI module
  # This allows Tim Engine to be used in Node.js/Bun.js applications

  import std/[strutils, json]
  import pkg/[denim, jsony, watchout]
  
  import ./tim/pm/initalizer
  
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

    proc render(view: string, layout: string = "base"): string {.export_napi.} =
      ## Render a Tim Engine template based on the view and layout paths
      let
        layoutPath = args.get("layout").getStr
        layout = timjs.getLayout(layoutPath)
        
        viewPath = args.get("view").getStr
        view = timjs.getView(viewPath)

      return bindings.`%*`(evaluate(view, layout))

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
      string(--ext),       # choose a target (default target `html`)
      string(-o),       # save output to file
      ?json(--data),    # pass data to global/local scope
      bool(--nocache),  # tells Tim to import modules and rebuild cache
      bool(--bench):    # benchmark operations
        ## Transpile `timl` to specific target source
    
    ast path(`timl`):
      ## Transpile timl code to AST representation

    #
    # Development commands
    # Used to manage Tim Engine packages locally
    #
    -- "Development"
    init ?string(`pkg`):
      ## Init a new package
    install string(`pkg`):
      ## Install a package from remote source
    develop string(`pkg`):
      ## Create a symlink to a package in local source
    remove string(`pkg`):
      ## Remove a package from local source

else:
  # Importing Tim Engine as a Nimble library
  # so it can be used in other Nim projects
  discard # todo