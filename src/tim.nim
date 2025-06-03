when isMainModule:
  import pkg/kapsis
  import pkg/kapsis/[runtime, cli]
  import ./tim/app/[build]
  
  commands:
    -- "Source to Source"
    # transpile `timl` code to a specific target source.
    src path(`timl`),
      string(-t),       # choose a target (default target `html`)
      string(-o),       # save output to file
      ?json(--data),    # pass data to global/local scope
      bool(--pretty),   # pretty print output HTML (still buggy)
      bool(--nocache),  # tells Tim to import modules and rebuild cache
      bool(--lib),      # wrap template as a dynamic library
      bool(--bench),    # benchmark operations
      bool("--json-errors"):
        ## Transpile `timl` to specific target source
    
    