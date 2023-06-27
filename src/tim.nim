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
  import timpkg/engine/[meta, parser, compiler]

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
                        tpl = tp,
                        minify = timEngine.shouldMinify,
                        indent = timEngine.getIndent,
                        filePath = tp.getFilePath,
                        data = data,
                        viewCode = viewCode,
                        hasViewCode = hasViewCode
                      )

  init proc(module: Module) =
    proc init(source: string, output: string, indent: int, minify: bool, globals: object) {.export_napi.} =
      ## Create an instance of TimEngine.
      ## To be called in the main state of your application
      if timEngine == nil:
        timEngine.init(
          source = args[0].getStr,
          output = args[1].getStr,
          indent = args[2].getInt,
          minified = args[3].getBool
        )
        timEngine.setData(args[4].tryGetJson)
      else: assert error($errInitialized, errIdent)

    proc precompile() {.export_napi.} =
      ## Export `precompile` function.
      ## To be used in the main state of your application
      if timEngine != nil:
        for k, t in timEngine.getViews.mpairs:
          precompileCode()
        for k, t in timEngine.getLayouts.mpairs:
          precompileCode()
      else: assert error($errNotInitialized, errIdent)

    proc render(view: string, scope: object, layout: string): string {.export_napi.} =
      ## Export `render` function
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

elif defined emscripten:
  import timpkg/engine/[meta, parser, compiler, ast]

  # https://emscripten.org/docs/api_reference/emscripten.h.html
  proc emscripten_run_script(code: cstring) {.importc.}

  proc tim(code: cstring, minify: bool, indent = 2): cstring {.exportc.} =
    var p = parser.parse($code)
    if not p.hasError:
      return cstring(newCompiler(p.getStatements, true, indent, data = %*{}).getHtml)
    let jsError = "throw new Error('" & p.getError & "');"
    emscripten_run_script(cstring(jsError))    

elif isMainModule:
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
  include timpkg/engine/init
