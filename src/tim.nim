# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://tim-engine.com

when isMainModule:
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