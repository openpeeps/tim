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
      errDefaultLayoutNotFound = "`base.timl` layout is missing from your `/layouts` directory"

  var timEngine: TimEngine

  const
    errIdent = "TimEngine"
    initFnHint = """
  /**
   * @param source {string}   Source path of your templates
   * @param output {string}   Output path for binary AST and precompiled templates
   * @param indent {int}      Indentation size (when `minify` is false)
   * @param minify {bool}     Whether to minify the final output
   * @param global {object}   Global data
   */
    """
    renderFnHint = """
  /**
   * @param view {string}       Name a view to render (`timl` file name without extension)
   * @param scope {object}      Scope data (Optional) 
   * @param layout {string}     Name a layout to wrap the view (Optional)
   */
    """
    docktype = "<!DOCTYPE html>"
    defaultLayoutName = "base"

  template precompileCode() =
    var p = timEngine.parse(t.getSourceCode, t.getFilePath, templateType = t.getType)
    if p.hasError:
      assert error(p.getError, errIdent)
      return
    if p.hasJit:
      t.enableJIT
      timEngine.writeAst(t, p.getStatements, timEngine.getIndent)
    else:
      var c = newCompiler(timEngine, p.getStatements, t, timEngine.shouldMinify, timEngine.getIndent, t.getFilePath)
      if not c.hasError:
        timEngine.writeHtml(t, c.getHtml)

  proc newJITCompilation(tp: Template, data: JsonNode, viewCode = "", hasViewCode = false): Compiler =
    result = newCompiler(timEngine, timEngine.readAst(tp),
                        `template` = tp,
                        minify = timEngine.shouldMinify,
                        indent = timEngine.getIndent,
                        filePath = tp.getFilePath,
                        data = data,
                        viewCode = viewCode,
                        hasViewCode = hasViewCode
                      )

  init proc(module: Module) =
    module.registerFn(5, "init"):
      ## Create an instance of TimEngine.
      ## To be called in the main state of your application
      if timEngine == nil:
        if not Env.expect(args, errIdent,
            ("source", napi_string), ("output", napi_string),
            ("indent", napi_number), ("minified", napi_boolean),
            ("globals", napi_object)): return
        if args.len == 5:
          timEngine.init(
            source = args[0].getStr,
            output = args[1].getStr,
            indent = args[2].getInt,
            minified = args[3].getBool
          )
          timEngine.setData(args[4].tryGetJson)
        else: assert error($errInitFnArgs & initFnHint, errIdent)
      else: assert error($errInitialized, errIdent)

    module.registerFn(0, "precompile"):
      ## Export `precompile` function.
      ## To be used in the main state of your application
      if timEngine != nil:
        for k, t in timEngine.getViews.mpairs:
          precompileCode()
        for k, t in timEngine.getLayouts.mpairs:
          precompileCode()
      else: assert error($errNotInitialized, errIdent)

    module.registerFn(3, "render"):
      ## Export `render` function
      if args.len != 0:
        if timEngine != nil:
          let
            viewName = args[0].getStr
            layoutName =
              if args.len == 3:
                if timEngine.hasLayout(args[2].getStr):
                  args[2].getStr
                else: defaultLayoutName
              else: defaultLayoutName
          if layoutName == defaultLayoutName:
            if not timEngine.hasLayout(defaultLayoutName):
              assert error($errDefaultLayoutNotFound, errIdent)

          # echo args[1].expect(napi_object)
          if timEngine.hasView(viewName):
            var tpv, tpl: Template
            # create a JsonNode to expose available data
            var jsonData = newJObject()
            jsonData["scope"] =
              if args.len >= 2:
                args[1].tryGetJson
              else: newJObject()
            tpv = timEngine.getView(viewName)
            tpl = timEngine.getLayout(layoutName)
            if tpv.isJitEnabled:
              # when enabled, compiles timl code to HTML on the fly
              var cview = newJITCompilation(tpv, jsonData)
              var clayout = newJITCompilation(tpl, jsonData, cview.getHtml, hasViewCode = true)
            # todo handle compiler warnings
              return %*(docktype & clayout.getHtml)
        else: assert error($errNotInitialized, errIdent)
      else: assert error($errRenderFnArgs & renderFnHint, errIdent)
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
