# A high-performance compiled template engine inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

when isMainModule:
  ## The standalone cross-language application
  ## ====================
  ## This is Tim as command line interface. It can be used for transpiling
  ## Tim sources to various programming/markup languages such as:
  ## Nim, JavaScript, Python, XML, PHP, Go, Ruby, Java, Lua.
  ## **Note**: This is work in progress
  import klymene
  import tim/commands/[initCommand, watchCommand, buildCommand]

  App:
    about:
      "A High-performance, compiled template engine & markup language"
      "Made by Humans from OpenPeep"

    commands:
      $ "init"              "Generate a new Tim config"
      $ "watch"             "Transpile and Watch for changes"
      $ "build"             "Transpile Tim to targeting language"

else:
  ## Tim as a Nimble Library
  ## ==========================
  ## Ready to be integrated with your backend. It comes with a
  ## template manager that separates your layouts and views
  ## in two types: `Static` and `Dynamic` templates.
  ## 
  ## A `layout` or a `view` is marked as dynamic when contains
  ## either variables, conditions or for loops.
  ## In this case its AST representation is converted to
  ## Binary JSON so that it can be transpiled to HTML on the fly (JIT Compilation). 
  ## 
  ## While static templates are transpiled to HTML when calling `precompile` proc.
  ## 
  ## However, both layouts and views are saved in separate files.
  include tim/engine/init