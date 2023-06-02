# A high-performance compiled template engine
# inspired by the Emmet syntax.
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

when defined napibuild:
  import pkg/denim
  import std/[os, tables]
  import std/json except `%*`
  import pkg/tim/engine/[meta, parser, compiler]

  type
    ErrorMessage = enum
      errInitialized = "TimEngine is already initialied"
      errInitFnArgs = "`init` function requires 4 arguments\n"
      errNotInitialized = "TimEngine is not initialized"
      errRenderFnArgs = "`render` function expect at least 1 argument\n"

  var timEngine: TimEngine

  const
    errIdent = "TimEngine"
    initFnHint = """
  /**
   * @param source {string}   Source path of your templates
   * @param output {string}   Output path for binary AST and precompiled templates
   * @param indent {int}      Indentation size (when `minify` is false)
   * @param minify {bool}     Whether to minify the final output
   */
    """
    renderFnHint = """
  /**
   * @param view {string}       The name of the view (without file extension)
   * @param scope {object}      Scope data (Optional) 
   * @param layout {string}     Name a layout to wrap the view (Optional)
   */
    """

  init proc(module: Module) =
    module.registerFn(4, "init"):
      ## Create an instance of TimEngine.
      ## To be called in the main state of your application
      if timEngine == nil:
        if args.len == 4:
          timEngine.init(
            source = args[0].getStr,
            output = args[1].getStr,
            indent = args[2].getInt,
            minified = args[3].getBool
          )
        else: assert error($errInitFnArgs & initFnHint, errIdent)
      else: assert error($errInitialized, errIdent)

    module.registerFn(0, "precompile"):
      ## Export `precompile` function.
      ## To be used in the main state of your application
      discard

    module.registerFn(3, "render"):
      ## Export `render` function
      if args.len != 0:
        if timEngine != nil:
          let viewName = args[0].getStr
          if timEngine.hasView(viewName):
            let tp: Template = timEngine.getView(viewName)
            var tParser: Parser = timEngine.parse(tp.getSourceCode(), tp.getFilePath, templateType = tp.getType())
            if not tParser.hasError:
              # echo args[1].expect(napi_object)
              var jsonData: JsonNode = newJObject()
              jsonData["scope"] = args[1].tryGetJson
              jsonData["globals"] = newJObject() # todo
              var timCompiler: Compiler = timEngine.newCompiler(tParser.getStatements(), tp,
                                            timEngine.shouldMinify, timEngine.getIndent,
                                            tp.getFilePath, data = jsonData)
              return %* timCompiler.getHtml()
            else: assert error(tParser.getError, errIdent)
        else: assert error($errNotInitialized, errIdent)
      else: assert error($errRenderFnArgs & renderFnHint, errIdent)r
else:
  when isMainModule:
    ## The standalone cross-language application
    ## ====================
    ## This is Tim as command line interface. It can be used for transpiling
    ## Tim sources to various programming/markup languages such as:
    ## Nim, JavaScript, Python, XML, PHP, Go, Ruby, Java, Lua.
    ## **Note**: This is work in progress
    import kapsis
    import tim/commands/[initCommand, watchCommand, buildCommand]

    App:
      about:
        "A High-performance, compiled template engine & markup language"
        "Made by Humans from OpenPeep"

      commands:
        $ "init":
          ? "Generate a new Tim config"
        $ "watch":
          ? "Transpile and Watch for changes"
        $ "build":
          ? "Transpile Tim to targeting language"
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
