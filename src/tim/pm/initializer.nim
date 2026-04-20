import std/[os, tables, net, strutils, sequtils, options]

import pkg/openparser/json
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value, resolver]
import pkg/vancode/manager/[configurator, packager]
import pkg/kapsis/interactive/prompts

import pkg/[watchout, semver, nyml, checksums/sha1]
import ../engine/parser

export value

when defined timHotCode:
  import ./websocket

#
# Standard Libraries
# 
import ../engine/stdlib/[libsystem, libffi, libtimes,
              libstrings, libarrays, libjson, inliner]

export TypeKind, StackView, Value, CodeGenError
export configurator, paramDef

type
  TimTemplateType* = enum
    ## Type of the Tim template
    ttView = "views"
    ttLayout = "layouts"
    ttPartial = "partials"

  TemplateSources* = tuple[src: string, ast: string, html: string, opcache: string]

  TimTemplate* {.acyclic.} = ref object
    ## Object representing a Tim template
    id*: string
      ## unique identifier of the template (based on path hash)
    sources*: TemplateSources
      ## the source paths related to the template, including the
      ## # original source path, the cached AST path,
    templateType*: TimTemplateType
      # the type of the template (view, layout or partial)
    script: Script
      # the compiled script of the template
    mainChunk: Chunk
      # the main chunk of the compiled script
    vmInstance: VM
      # the VM instance for evaluating the template
    dependencies*: seq[string] = @[]
      ## a sequence of source paths that the template depends on (imports/includes)

  UserScript* {.acyclic.} = ref object
    # chunk: Chunk
    # script: Script
    # module: Module
    procs: seq[(string, seq[TempParamDef], TypeKind, ForeignProc, bool)]
      ## A sequence of foreign procedures to be added to the user script
    code: string # A string to inject into the script before execution

  ThemeManifest* {.acyclic.} = object
    ## The manifest for a Tim theme, defined in `theme.yaml` in the theme directory
    name*, author*, url*, license*, description*: string
    version*: semver.Version

  Theme* {.acyclic.} = ref object
    manifest*: ThemeManifest
    path*: string # base path of the theme
    views*, layouts*, partials*: TableRef[string, TimTemplate] = newTable[string, TimTemplate]()
      ## Tables to store templates by their source path

  TimEngine* {.acyclic.} = ref object
    ## The main Tim Engine object.
    ## Holds the configuration and the templates.
    ## 
    ## It must be initialized with `newTim()`
    config*: TimConfig
      ## The configuration for the Tim Engine, including source and output paths, target source, etc.
    userScript*: UserScript
      ## A `UserScript` object that allows users to define custom foreign procedures
    globalData*: JsonNode
      ## Global data available in all templates under the `$app` variable
    depResolver*: FileResolver
      ## A `FileResolver` to manage template dependencies and hot reloading
    enableThemes*: bool
      ## Whether to enable theme support. If true, the engine will look for themes in the
      ## `themes` directory of the installation path and load the active theme's templates.
    themes*: TableRef[string, Theme] = newTable[string, Theme]()
      ## A table to store themes by their name
    activeTheme*: Theme
      ## The currently active theme, if any
    activeThemeName*: string
      ## The name of the currently active theme, used for initialization before loading themes
    views*, layouts*, partials*: TableRef[string, TimTemplate] = newTable[string, TimTemplate]()
      ## Tables to store templates by their source path
  
  TimEngineError* = object of CatchableError

let stdlibs = newTable[string, proc(script: Script, systemModule: Module): Module]()

proc parseHook(parser: var json.JsonParser, v: var semver.Version) =
  # A JSON parsing hook to parse the `version` field in the
  # theme manifest as a `semver.Version` object
  v = parseVersion(parser.curr.value)
  parser.walk()

iterator getViews*(engine: TimEngine): TimTemplate =
  ## Iterator to get all view templates
  for _, tpl in engine.views:
    yield tpl

iterator getLayouts*(engine: TimEngine): TimTemplate =
  ## Iterator to get all layout templates
  for _, tpl in engine.layouts:
    yield tpl

iterator getPartials*(engine: TimEngine): TimTemplate =
  ## Iterator to get all partial templates
  for _, tpl in engine.partials:
    yield tpl

# precompile - forward declarations
proc precompile*(engine: TimEngine) 
proc precompileTemplate*(engine: TimEngine, tpl: TimTemplate,
        pkgr: Packager, data: JsonNode = nil): bool {.discardable.}

proc getHashedPath(path: string): string =
  # Get a SHA1 hash of the given path.
  toLowerAscii($(sha1.secureHash(path)))

proc newTemplate*(id: string, templateType: TimTemplateType, sources: TemplateSources): TimTemplate =
  ## Create a half-initialized `TimTemplate` object with
  ## the given id, type and source path
  result = TimTemplate(id: id, templateType: templateType, sources: sources)

proc addProc*(userScript: UserScript, name: string, params: seq[TempParamDef] = @[],
        returnTy: TypeKind, impl: ForeignProc = nil, exportSym = true) =
  ## Add a foregin function to the `UserScript`.
  userScript.procs.add((name, params, returnTy, impl, exportSym))

proc injectScript*(userScript: UserScript, code: string) =
  ## Inject a code string into the `UserScript`.
  # userScript.script.compileCode(userScript.module, "user_script", code)

proc newTim*(src, output, basepath: string,
          target = TargetSource.tsHtml,
          globalData: JsonNode = newJObject(),
          enableThemes: static bool = false,
          activeThemeName: string = ""): TimEngine =
  ## Initialize a new Tim Engine instance.
  ## 
  ## `src`: the source directory containing the templates
  ## 
  ## `output`: the output directory where the rendered files will be saved
  ## 
  ## `basepath`: the base path to resolve the `src` and `output` paths
  ## 
  ## `target`: the target source for transpilation (default: HTML)
  let sourcePath = normalizedPath(basepath / src)
  result = TimEngine(
    userScript: UserScript(),
    globalData: globalData,
    depResolver: initResolver(),
    enableThemes: enableThemes,
    activeThemeName: activeThemeName,
    config: TimConfig(
      `type`: ConfigType.typeProject,
      compilation: CompilationSettings(
        source: sourcePath,
        output: normalizedPath(basepath / output),
        basePath: basepath,
        layoutsPath: sourcePath / "layouts",
        viewsPath: sourcePath / "views",
        partialsPath: sourcePath / "partials",
        target: target
      )
    )
  )

  stdlibs["times"] = loadTimes
  stdlibs["ffi"] = loadFFI

proc getTemplateByPath*(engine: TimEngine, path: string): TimTemplate =
  ## Get a Tim template by its source path.
  ## Returns a TimTemplate object with the template type set to `ttView`.
  if engine.enableThemes:
    # when themes are enabled, we need to look for the template in the active theme's tables
    if engine.activeTheme == nil:
      raise newException(TimEngineError, "Active theme is not set")
    let active = engine.activeTheme
    if path in active.views:
      return active.views[path]
    if path in active.layouts:
      return active.layouts[path]
    if path in active.partials:
      return active.partials[path]
  else:
    if path in engine.views:
      return engine.views[path]

    if path in engine.layouts:
      return engine.layouts[path]

    if path in engine.partials:
      return engine.partials[path]

#
# Tim Engine getters
#
proc getLayout*(engine: TimEngine, key: string): TimTemplate =
  ## Get a layout template by its name (with/without extension).
  let path = engine.config.compilation.layoutsPath / key
  if not key.endsWith(".timl"):
    return engine.layouts.getOrDefault(path & ".timl", nil)
  return engine.layouts.getOrDefault(path, nil)

proc getView*(engine: TimEngine, key: string): TimTemplate =
  ## Get a view template by its name (with/without extension).
  let path = engine.config.compilation.viewsPath / key
  if not key.endsWith(".timl"):
    return engine.views.getOrDefault(path & ".timl", nil)
  return engine.views.getOrDefault(path, nil)

proc getPartial*(engine: TimEngine, key: string): TimTemplate =
  ## Get a partial template by its name (with/without extension).
  let path = engine.config.compilation.partialsPath / key
  if not key.endsWith(".timl"):
    return engine.partials.getOrDefault(path & ".timl", nil)
  return engine.partials.getOrDefault(path, nil)

#
# Theme template getters
#
proc getThemePartial*(engine: TimEngine, key: string): TimTemplate =
  ## Get a partial template from the active theme by its name (with/without extension).
  {.gcsafe.}:
    if engine.activeTheme == nil:
      raise newException(TimEngineError, "Active theme is not set")
    let path = engine.activeTheme.path / "partials" / key
    if not key.endsWith(".timl"):
      return engine.activeTheme.partials.getOrDefault(path & ".timl", nil)
    return engine.activeTheme.partials.getOrDefault(path, nil)

proc getThemeLayout*(engine: TimEngine, key: string): TimTemplate =
  ## Get a layout template from the active theme by its name (with/without extension).
  {.gcsafe.}:
    if engine.activeTheme == nil:
      raise newException(TimEngineError, "Active theme is not set")
    let path = engine.activeTheme.path / "layouts" / key
    if not key.endsWith(".timl"):
      return engine.activeTheme.layouts.getOrDefault(path & ".timl", nil)
    result = engine.activeTheme.layouts.getOrDefault(path, nil)

proc getThemeView*(engine: TimEngine, key: string): TimTemplate =
  ## Get a view template from the active theme by its name (with/without extension).
  {.gcsafe.}:
    if engine.activeTheme == nil:
      raise newException(TimEngineError, "Active theme is not set")
    let path = engine.activeTheme.path / "views" / key
    if not key.endsWith(".timl"):
      return engine.activeTheme.views.getOrDefault(path & ".timl", nil)
    return engine.activeTheme.views.getOrDefault(path, nil)

proc registerTemplate*(engine: TimEngine, src: string): TimTemplate =
  ## Register a new Tim template by its source path.
  ## 
  ## This is used during the precompilation process to create a new Tim template
  ## and register it in the engine's tables based on its type (view, layout or partial)
  var templateType: TimTemplateType
  if src.startsWith(engine.config.compilation.viewsPath):
    templateType = ttView
  elif src.startsWith(engine.config.compilation.layoutsPath):
    templateType = ttLayout
  elif src.startsWith(engine.config.compilation.partialsPath):
    templateType = ttPartial
  let sources = (
    src: src,
    ast: engine.config.compilation.output / "ast" / getHashedPath(src) & ".json",
    html: engine.config.compilation.output / "html" / getHashedPath(src) & ".html",
    opcache: engine.config.compilation.output / "opcache" / getHashedPath(src) & ".json"
  )
  let tpl = newTemplate(getHashedPath(src), templateType, sources)
  case templateType
  of ttView:
    engine.views[src] = tpl
  of ttLayout:
    engine.layouts[src] = tpl
  of ttPartial:
    engine.partials[src] = tpl
  return tpl

proc parserCallback(astProgram: var Ast, path: string) =
  parser.parseScript(astProgram, readFile(path), path)

proc resolveDepPath(engine: TimEngine, ownerSrc, dep: string): string =
  # Resolve the path of a dependency based on the owner template's
  # source path and the engine's configuration.
  if dep.isAbsolute: return normalizedPath(dep)

  let fromOwner = normalizedPath(ownerSrc.parentDir / dep)
  if fileExists(fromOwner): return fromOwner

  let fromPartials = normalizedPath(engine.config.compilation.partialsPath / dep)
  if fileExists(fromPartials): return fromPartials
  return fromOwner

proc updateDeps(engine: TimEngine, tpl: TimTemplate, rawDeps: sink seq[string]) =
  # Update the dependencies of a template based on the raw dependency
  # paths extracted from the AST.
  var deps: seq[string] = @[]
  let owner = normalizedPath(tpl.sources.src)
  for raw in rawDeps:
    let d = engine.resolveDepPath(owner,
      engine.config.compilation.partialsPath / raw.addFileExt("timl"))
    if d != owner and d notin deps:
      deps.add(d)
  tpl.dependencies =move deps
  engine.depResolver.setDependencies(owner, tpl.dependencies)

proc parsePartial(engine: TimEngine, tpl: TimTemplate) =
  # Parse a partial template to extract its dependencies
  # and update the engine's resolver.
  var astProgram: Ast
  try:
    parser.parseScript(astProgram, readFile(tpl.sources.src), tpl.sources.src)
  except TimParserError as e:
    echo "Error parsing template: ", e.msg
    echo tpl.sources.src
    return
  engine.updateDeps(tpl, astProgram.otherPaths)

proc declareGlobals*(compiler: CodeGen) =
  # Declare global variables for the template scripts, such as `$app` and `$this`.
  let appStorage = newIdent("app")
  let thisStorage = newIdent("this")
  compiler.declareVar(appStorage, skConst, compiler.module.sym"json", isMagic = true)
  compiler.declareVar(thisStorage, skConst, compiler.module.sym"json", isMagic = true)

proc precompileTemplate*(engine: TimEngine, tpl: TimTemplate,
        pkgr: Packager, data: JsonNode = nil): bool {.discardable.} =
  ## Precompile a Tim template. This involves parsing the template to extract its dependencies,
  ## compiling the template into a script, and updating the engine's dependency resolver.
  var astProgram: Ast
  try:
    parser.parseScript(astProgram, readFile(tpl.sources.src), tpl.sources.src)
  except TimParserError as e:
    echo "Error parsing template: ", e.msg
    echo tpl.sources.src
    return

  var
    mainChunk = newChunk(tpl.sources.src)
    script = newScript(mainChunk)
    module = newModule(tpl.sources.src.extractFilename, some(tpl.sources.src))
    localData = newJObject()

  engine.updateDeps(tpl, astProgram.otherPaths)

  # load standard library modules
  let systemModule = libsystem.loadLibrary(script)
  module.load(systemModule)

  # load the user defined script
  if engine.userScript != nil:
    for procDef in engine.userScript.procs:
      script.addProc(
        module,
        procDef[0], # name
        procDef[1], # params
        procDef[2], # return type
        procDef[3], # implementation
        procDef[4]  # export symbol
      )
    # module.load(engine.userScript.module)

  script.addProc(module, "evaluate", @[paramDef("code", ttyString)], ttyAny,
    proc (args: StackView, argc: int): Value =
      ## Evaluate a string of Tim code and return the result.
      var inlineAst: Ast
      try:
        parser.parseScript(inlineAst, args[0].stringVal[], "inline")
        var inlineChunk = newChunk("inline")
        var inlineScript = newScript(inlineChunk)
        var inlineModule = newModule("inline", some("inline"))

        let systemModule = libsystem.loadLibrary(inlineScript)
        inlineModule.load(systemModule)

        var inlineCompiler = codegen.initCompiler(inlineScript, inlineModule,
                                inlineChunk, pkgr, stdlibs, parserCallback)

        inlineCompiler.declareGlobals()
        inlineCompiler.genScript(
          program = inlineAst,
          includePath = some(engine.config.compilation.partialsPath)
        )

        var vmInstance = newVM()
        let outputVM = vm.interpret(vmInstance, inlineScript, inlineChunk, localData = newJObject())
        result = initValue(outputVM)

      except TimParserError as e:
        raise newException(TimRuntime, e.msg)
    )

  let stringsLib = initStrings(script, systemModule)
  module.load(stringsLib)

  let arraysLib = initArrays(script, systemModule)
  module.load(arraysLib)

  let jsonlib = initJSON(script, systemModule)
  module.load(jsonlib)

  # module.load(stdlibs["ffi"](script, systemModule))
  # module.load(stdlibs["times"](script, systemModule))

  script.stdpos = script.procs.high
  
  var compiler =
    codegen.initCompiler(script, module, mainChunk,
                          pkgr, stdlibs, parserCallback)
  compiler.declareGlobals()
  compiler.genScript(
    program = astProgram,
    includePath = some(engine.config.compilation.partialsPath)
  )
  
  tpl.script = script
  tpl.mainChunk = mainChunk
  tpl.vmInstance = newVM()
  
  writeFile(tpl.sources.ast, toJson(astProgram))
  writeFile(tpl.sources.opcache, tpl.mainChunk.code)
  return true # marks the template as successfully precompiled

var
  browserSyncWatcher: Watchout
  browserSyncThemeWatcher: Watchout

proc eval*(view, layout: TimTemplate, localData,
        globalData: JsonNode): string {.raises: [IndexDefect, ValueError, KeyError, TimEngineError, Exception].} =
  ## Evaluate a view within a layout and return the final HTML output.
  ## 
  ## Templates are evaluated in the context of the provided `localData` and `globalData`, which are
  ## available in the templates under the `$this` and `$app` variables, respectively.
  ## 
  ## The view template is evaluated first, and its output is passed to the layout
  ## template as the content to be rendered within the layout.
  assert view.script != nil and
    layout.script != nil, "View or Layout script is not initialized"
  
  # first, evaluate the view template to get its output
  let viewOutput = view.vmInstance.interpret(view.script, view.mainChunk,
                      globalData = globalData, localData = localData)

  # then evaluate the layout template, passing the view output
  # and returning the final result
  result = view.vmInstance.interpret(layout.script, layout.mainChunk,
                    some(viewOutput), globalData = globalData, localData = localData)

proc eval*(view: TimTemplate, localData, globalData: JsonNode): string {.raises: [IndexDefect, ValueError, KeyError, TimEngineError, Exception].} =
  ## Evaluate a view without a layout and return the final HTML output. 
  ## This can be used for rendering partials or standalone views.
  assert view.script != nil, "View script is not initialized"
  result = view.vmInstance.interpret(view.script, view.mainChunk,
                globalData = globalData, localData = localData)

proc precompile*(engine: TimEngine) =
  ## Precompile Tim Engine templates.
  ## 
  ## This proc is usually called before starting the development server.
  ## It compiles all the templates and sets up the file watcher
  ## for hot reloading.

  # init the package manager and load the local packages
  let pkgr = packager.initPackageRemote()
  pkgr.loadPackages()

  if engine.enableThemes:
    # when themes are enabled, will discover themes available in the `themes` directory
    # of the installation path. Each theme should have a `theme.yaml` manifest file and its own
    # `views`, `layouts` and `partials` directories.
    #
    # The active theme is determined by the `activeTheme` field in the engine config, which should
    # match the name of one of the discovered themes. Once found, we will load and compile
    # the templates of the active theme and set up the file watcher for hot reloading
    let srcDir = engine.config.compilation.source
    for themeDir in walkDirs(srcDir / "*"):
      let yamlConfigPath = themeDir / "theme.yaml"
      let jsonConfigPath = themeDir / "theme.json"
      var themeManifest: ThemeManifest
      if fileExists(yamlConfigPath):
        try:
          themeManifest = fromYAML(readFile(yamlConfigPath), ThemeManifest)
        except YAMLException:
          displayError("Failed to parse theme manifest: " & yamlConfigPath)
      elif fileExists(jsonConfigPath):
        try:
          themeManifest = fromJson(readFile(jsonConfigPath), ThemeManifest)
        except JsonParsingError:
          displayError("Failed to parse theme manifest: " & jsonConfigPath)
      else:
        displayError("No theme manifest found for theme: " & themeDir)
      var theme = Theme(path: themeDir, manifest: themeManifest)
      engine.themes[themeManifest.name] = theme
      
      # if the theme is the active theme, load and compile its templates
      if engine.activeThemeName.len > 0 and themeManifest.name == engine.activeThemeName:
        engine.activeTheme = theme
        # load and compile the active theme's templates
        for sourceDir in [ttLayout, ttView, ttPartial]:
          let themeSourcePath = themeDir / $sourceDir
          if not dirExists(themeSourcePath):
            displayError("Missing directory $1 for theme $2: \n$3" % [$sourceDir, themeManifest.name, themeSourcePath])
            # to continue or to not continue, that's the question. we can choose to
            # skip transpiling this theme if its structure is not correct, or we can
            # raise an error and stop the app, or simply invalidate the theme
            # so it can be listed into a "broken themes" section in the dashboard
            continue
          let cachedOutputPath = engine.config.compilation.output / themeManifest.name
          discard existsOrCreateDir(cachedOutputPath) 
          discard existsOrCreateDir(cachedOutputPath / "ast")
          discard existsOrCreateDir(cachedOutputPath / "html")
          discard existsOrCreateDir(cachedOutputPath / "opcache")
          for srcPath in walkDirRec(themeSourcePath):
            let
              id = getHashedPath(srcPath) # unique id based on path
              astPath = cachedOutputPath / "ast" / id & ".ast"
              htmlPath = cachedOutputPath / "html" / id & ".html"
              opcachePath = cachedOutputPath / "opcache" / id & ".opc"
              sources = (src: srcPath, ast: astPath, html: htmlPath, opcache: opcachePath)
            case sourceDir:
            of ttLayout:
              let tpl = newTemplate(id, ttLayout, sources)
              if engine.precompileTemplate(tpl, pkgr):
                theme.layouts[srcPath] =  tpl
            of ttView:
              let tpl = newTemplate(id, ttView, sources)
              if engine.precompileTemplate(tpl, pkgr):
                theme.views[srcPath] = tpl
            of ttPartial:
              let tpl = newTemplate(id, ttPartial, sources)
              if engine.precompileTemplate(tpl, pkgr):
                theme.partials[srcPath] = tpl
          
        # set up file watcher for the active theme
        when defined timHotCode:
          browserSyncThemeWatcher = newWatchout(@[
            engine.activeTheme.path / "layouts",
            engine.activeTheme.path / "views",
            engine.activeTheme.path / "partials"
          ], some("*.timl"))

          let ws2 = startWebSocket(port = Port(9001))
          sleep(100) # wait for the websocket server

          # Callback `onFound`
          proc onFound(file: watchout.File) =
            # Runs when detecting a new template.
            let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
            if tpl != nil:
              case tpl.templateType
              of ttView, ttLayout:
                engine.precompileTemplate(tpl, pkgr)
              else: discard
            else:
              # if the template is not registered,
              # we need to register it and compile it
              let newTpl = engine.registerTemplate(file.getPath())
              if newTpl.templateType != ttPartial:
                # partials don't need to be compiled as they
                # are included in other templates (layouts or views)
                engine.precompileTemplate(newTpl, pkgr)
              else:
                # for partials, we only need to parse them to get their dependencies
                parsePartial(engine, newTpl)

          # Callback `onChange`
          proc onChange(file: watchout.File) =
            # Runs when detecting changes
            let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
            if tpl == nil: return # template not found, ignore
            case tpl.templateType
            of ttView, ttLayout:
              # if the template is a view or layout, compile it
              engine.precompileTemplate(tpl, pkgr)
              ws2.notifyAllClients()
            of ttPartial:
              # refresh changed partial dependencies first
              parsePartial(engine, tpl)
              # re-compile all recursive dependants
              for depPath in engine.depResolver.dependants(tpl.sources.src):
                let depTpl = engine.getTemplateByPath(depPath)
                if depTpl == nil: continue
                case depTpl.templateType
                of ttView, ttLayout:
                  engine.precompileTemplate(depTpl, pkgr)
                of ttPartial:
                  parsePartial(engine, depTpl)
                # clear the cached AST of the dependants to force
                # re-parsing and updating their dependencies
                codegenCache.cachedAst.del(tpl.sources.src)
              ws2.notifyAllClients()

          # Callback `onDelete`
          proc onDelete(file: watchout.File) =
            # Runs when detecting a deleted template
            let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
            if tpl != nil:
              # if the template is found, remove it from the engine tables
              # and clear its dependencies from the resolver. We also need
              # to re-compile all the dependants of the deleted template to update
              # their dependencies and remove the deleted template from their dependency list
              engine.depResolver.clearFile(normalizedPath(tpl.sources.src))

          browserSyncThemeWatcher.onFound = onFound
          browserSyncThemeWatcher.onChange = onChange
          browserSyncThemeWatcher.onDelete = onDelete
          browserSyncThemeWatcher.start()
  else:
    # for non-theme mode, we load all templates from the source directory and compile them
    discard existsOrCreateDir(engine.config.compilation.output)
    discard existsOrCreateDir(engine.config.compilation.output / "ast")
    discard existsOrCreateDir(engine.config.compilation.output / "html")
    discard existsOrCreateDir(engine.config.compilation.output / "opcache")
    let srcDir = engine.config.compilation.source
    for sourceDir in [ttLayout, ttView, ttPartial]:
      if not dirExists(srcDir / $sourceDir):
        raise newException(TimEngineError, "Missing directory $1: \n$2" % [$sourceDir, srcDir / $sourceDir])
      for srcPath in walkDirRec(srcDir / $sourceDir):
        let
          id = getHashedPath(srcPath) # unique id based on path
          astPath = engine.config.compilation.output / "ast" / id & ".ast"
          htmlPath = engine.config.compilation.output / "html" / id & ".html"
          opcachePath = engine.config.compilation.output / "opcache" / id & ".opc"
          sources = (src: srcPath, ast: astPath, html: htmlPath, opcache: opcachePath)
        case sourceDir:
          of ttLayout:
            let tpl = newTemplate(id, ttLayout, sources)
            if engine.precompileTemplate(tpl, pkgr):
              engine.layouts[srcPath] =  tpl
          of ttView:
            let tpl = newTemplate(id, ttView, sources)
            if engine.precompileTemplate(tpl, pkgr):
              engine.views[srcPath] = tpl 
          of ttPartial:
            let tpl = newTemplate(id, ttPartial, sources)
            if engine.precompileTemplate(tpl, pkgr):
              engine.partials[srcPath] = tpl
          else: discard

    when defined timHotCode:
      browserSyncWatcher = 
        newWatchout(@[
          engine.config.compilation.layoutsPath,
          engine.config.compilation.viewsPath,
          engine.config.compilation.partialsPath
        ], some("*.timl"))
      
      let ws1 = startWebSocket(port = Port(9000))
      sleep(100) # wait for the websocket server

      # Callback `onFound`
      proc onFound(file: watchout.File) =
        # Runs when detecting a new template.
        let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
        if tpl != nil:
          case tpl.templateType
          of ttView, ttLayout:
            engine.precompileTemplate(tpl, pkgr)
          else: discard
        else:
          # if the template is not registered,
          # we need to register it and compile it
          let newTpl = engine.registerTemplate(file.getPath())
          if newTpl.templateType != ttPartial:
            # partials don't need to be compiled as they
            # are included in other templates (layouts or views)
            engine.precompileTemplate(newTpl, pkgr)
          else:
            # for partials, we only need to parse them to get their dependencies
            parsePartial(engine, newTpl)

      # Callback `onChange`
      proc onChange(file: watchout.File) =
        # Runs when detecting changes
        let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
        if tpl == nil: return # template not found, ignore
        case tpl.templateType
        of ttView, ttLayout:
          # if the template is a view or layout, compile it
          engine.precompileTemplate(tpl, pkgr)
          ws1.notifyAllClients()
        of ttPartial:
          # refresh changed partial dependencies first
          parsePartial(engine, tpl)
          # re-compile all recursive dependants
          for depPath in engine.depResolver.dependants(tpl.sources.src):
            let depTpl = engine.getTemplateByPath(depPath)
            if depTpl == nil: continue
            case depTpl.templateType
            of ttView, ttLayout:
              engine.precompileTemplate(depTpl, pkgr)
            of ttPartial:
              parsePartial(engine, depTpl)
            # clear the cached AST of the dependants to force
            # re-parsing and updating their dependencies
            codegenCache.cachedAst.del(tpl.sources.src)
          ws1.notifyAllClients()

      # Callback `onDelete`
      proc onDelete(file: watchout.File) =
        # Runs when detecting a deleted template
        let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
        if tpl != nil:
          # if the template is found, remove it from the engine tables
          # and clear its dependencies from the resolver. We also need
          # to re-compile all the dependants of the deleted template to update
          # their dependencies and remove the deleted template from their dependency list
          engine.depResolver.clearFile(normalizedPath(tpl.sources.src))
          case tpl.templateType
          of ttView:
            engine.views.del(tpl.sources.src)
          of ttLayout:
            engine.layouts.del(tpl.sources.src)
          of ttPartial:
            engine.partials.del(tpl.sources.src)

      # Set up file watcher callbacks and start watching for changes
      browserSyncWatcher.onFound = onFound
      browserSyncWatcher.onChange = onChange
      browserSyncWatcher.onDelete = onDelete
      browserSyncWatcher.start()