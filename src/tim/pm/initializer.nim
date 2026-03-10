import std/[os, tables, net, strutils, json, sequtils, options]

# import pkg/voodoo/language/pm/manager
import pkg/voodoo/language/[ast, codegen, chunk, sym, vm, value, resolver]
import pkg/voodoo/packagemanager/[configurator, packager]

import pkg/[watchout, checksums/sha1]
import ../engine/parser

export value

when defined timHotCode:
  import ./websocket

#
# Standard Libraries
# 
import ../engine/stdlib/[libsystem, libffi,  libtimes, libstrings, inliner]


export TypeKind, StackView, Value, CodeGenError
export configurator, paramDef

type
  TimTemplateType* = enum
    ## Type of the Tim template
    ttView = "views"
    ttLayout = "layouts"
    ttPartial = "partials"

  TimTemplate* = ref object
    ## Object representing a Tim template
    id*: string
      ## unique identifier of the template (based on path hash)
    src*: string
      ## the absolute path to the template source file
    templateType*: TimTemplateType
      ## the type of the template (view, layout or partial)
    script: Script
      ## the transpiled script of the template
    mainChunk: Chunk
      ## the main chunk of the transpiled script
    dependencies*: seq[string] = @[]
      ## a sequence of source paths that the template depends on (imports/includes)

  UserScript* = ref object
    # chunk: Chunk
    # script: Script
    # module: Module
    procs: seq[(string, seq[TempParamDef], TypeKind, ForeignProc, bool)]
      ## A sequence of foreign procedures to be added to the user script
    code: string # A string to inject into the script before execution

  TimEngine* = ref object
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
    views*, layouts*, partials*: TableRef[string, TimTemplate] = newTable[string, TimTemplate]()
      ## Tables to store templates by their source path
  
  TimEngineError* = object of CatchableError

let stdlibs = newTable[string, proc(script: Script, systemModule: Module): Module]()

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

proc precompile*(engine: TimEngine) # forward declaration

proc transpile*(engine: TimEngine, tpl: TimTemplate,
        pkgr: Packager, data: JsonNode = nil): bool {.discardable.}

proc getHashedPath(path: string): string =
  ## Get a SHA1 hash of the given path.
  $(sha1.secureHash(path))

proc newTemplate*(id: string, templateType: TimTemplateType, src: string): TimTemplate =
  ## Create a new TimTemplate object.
  result = TimTemplate(
    id: id,
    src: src,
    templateType: templateType
  )

proc addProc*(userScript: UserScript, name: string, params: seq[TempParamDef] = @[],
        returnTy: TypeKind, impl: ForeignProc = nil, exportSym = true) =
  ## Add a foregin function to the `UserScript`.
  userScript.procs.add((name, params, returnTy, impl, exportSym))

proc injectScript*(userScript: UserScript, code: string) =
  ## Inject a code string into the `UserScript`.
  # userScript.script.compileCode(userScript.module, "user_script", code)

proc newTim*(src, output, basepath: string,
          target = TargetSource.tsHtml,
          globalData: JsonNode = newJObject()
  ): TimEngine =
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
    config: TimConfig(
      `type`: ConfigType.typeProject,
      compilation: CompilationSettings(
        source: sourcePath,
        output: output,
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
  if path in engine.views:
    return engine.views[path]

  if path in engine.layouts:
    return engine.layouts[path]

  if path in engine.partials:
    return engine.partials[path]

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

proc registerTemplate*(engine: TimEngine, src: string): TimTemplate =
  ## Register a new Tim template. Returns a `TimTemplate` object
  var templateType: TimTemplateType
  if src.startsWith(engine.config.compilation.viewsPath):
    templateType = ttView
  elif src.startsWith(engine.config.compilation.layoutsPath):
    templateType = ttLayout
  elif src.startsWith(engine.config.compilation.partialsPath):
    templateType = ttPartial
  let tpl = TimTemplate(src: src, templateType: templateType)
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
  if dep.isAbsolute: return normalizedPath(dep)

  let fromOwner = normalizedPath(ownerSrc.parentDir / dep)
  if fileExists(fromOwner): return fromOwner

  let fromPartials = normalizedPath(engine.config.compilation.partialsPath / dep)
  if fileExists(fromPartials): return fromPartials
  return fromOwner

proc updateDeps(engine: TimEngine, tpl: TimTemplate, rawDeps: sink seq[string]) =
  var deps: seq[string] = @[]
  let owner = normalizedPath(tpl.src)
  for raw in rawDeps:
    let d = engine.resolveDepPath(owner,
      engine.config.compilation.partialsPath / raw.addFileExt("timl"))
    if d != owner and d notin deps:
      deps.add(d)
  tpl.dependencies =move deps
  engine.depResolver.setDependencies(owner, tpl.dependencies)

proc parsePartial(engine: TimEngine, tpl: TimTemplate) =
  var astProgram: Ast
  try:
    parser.parseScript(astProgram, readFile(tpl.src), tpl.src)
  except TimParserError as e:
    echo "Error parsing template: ", e.msg
    echo tpl.src
    return
  engine.updateDeps(tpl, astProgram.otherPaths)

proc transpile*(engine: TimEngine, tpl: TimTemplate,
        pkgr: Packager, data: JsonNode = nil): bool {.discardable.} =
  ## Transpile the Tim template code.
  var astProgram: Ast
  try:
    parser.parseScript(astProgram, readFile(tpl.src), tpl.src)
  except TimParserError as e:
    echo "Error parsing template: ", e.msg
    echo tpl.src
    return

  var
    mainChunk = newChunk(tpl.src)
    script = newScript(mainChunk)
    module = newModule(tpl.src.extractFilename, some(tpl.src))
    localData = newJObject()

  engine.updateDeps(tpl, astProgram.otherPaths)

  # load standard library modules
  let systemModule = libsystem.loadLibrary(script, engine.globalData, localData)
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

  let stringsLib = initStrings(script, systemModule)
  module.load(stringsLib)

  # module.load(stdlibs["ffi"](script, systemModule))
  # module.load(stdlibs["times"](script, systemModule))

  script.stdpos = script.procs.high
  
  var compiler =
    codegen.initCompiler(script, module, mainChunk,
                    pkgr, stdlibs, parserCallback)
  compiler.genScript(
    program = astProgram,
    includePath = some(engine.config.compilation.partialsPath)
  )
  tpl.script = script
  tpl.mainChunk = mainChunk
  return true

var
  browserSyncWatcher: Watchout
  hasChanges: bool

proc eval*(view, layout: TimTemplate, localData, globalData: JsonNode): string {.raises: [IndexDefect, ValueError, KeyError, TimEngineError, Exception].} =
  ## Evaluate a view within a layout and return the final HTML output.
  assert view.script != nil and
    layout.script != nil, "View or Layout script is not initialized"
  let viewVM = newVM()
  let layoutVM = newVM()
  let viewOutput = viewVM.interpret(view.script, view.mainChunk, localData = localData)
  return layoutVM.interpret(layout.script, layout.mainChunk, some(viewOutput), localData = localData)

proc eval*(view: TimTemplate, localData, globalData: JsonNode): string {.raises: [IndexDefect, ValueError, KeyError, TimEngineError, Exception].} =
  ## Evaluate a view without a layout and return the final HTML output. 
  ## This can be used for rendering partials or standalone views.
  assert view.script != nil, "View script is not initialized"
  let viewVM = newVM()
  return viewVM.interpret(view.script, view.mainChunk, localData = localData)

proc precompile*(engine: TimEngine) =
  ## Precompile Tim Engine templates.
  ## 
  ## This proc is usually called before starting the development server.
  ## It transpiles all the templates and sets up the file watcher
  ## for hot reloading.

  # init the package manager and load the local packages
  let pkgr = packager.initPackageRemote()
  pkgr.loadPackages()

  for sourceDir in [ttLayout, ttView, ttPartial]:
    if not dirExists(engine.config.compilation.source / $sourceDir):
      raise newException(TimEngineError, "Missing directory $1: \n$2" % [$sourceDir, engine.config.compilation.source / $sourceDir])
    for srcPath in walkDirRec(engine.config.compilation.source / $sourceDir):
      let
        id = getHashedPath(srcPath) # unique id based on path
        astPath = engine.config.compilation.output / "ast" / id & ".ast"
        htmlPath = engine.config.compilation.output / "html" / id & ".html"
        sources = (src: srcPath, ast: astPath, html: htmlPath)
      case sourceDir:
        of ttLayout:
          let tpl = newTemplate(id, ttLayout, sources.src)
          if engine.transpile(tpl, pkgr):
            engine.layouts[srcPath] =  tpl
        of ttView:
          let tpl = newTemplate(id, ttView, sources.src)
          if engine.transpile(tpl, pkgr):
            engine.views[srcPath] = tpl 
        of ttPartial:
          let tpl = newTemplate(id, ttPartial, sources.src)
          if engine.transpile(tpl, pkgr):
            engine.partials[srcPath] = tpl
        else: discard

  browserSyncWatcher = 
    newWatchout(@[
      engine.config.compilation.layoutsPath,
      engine.config.compilation.viewsPath,
      engine.config.compilation.partialsPath
    ], some("*.timl"))

  # Callback `onFound`
  proc onFound(file: watchout.File) =
    # Runs when detecting a new template.
    let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
    if tpl != nil:
      case tpl.templateType
      of ttView, ttLayout:
        engine.transpile(tpl, pkgr)
      else: discard
    else:
      # if the template is not registered,
      # we need to register it and compile it
      let newTpl = engine.registerTemplate(file.getPath())
      if newTpl.templateType != ttPartial:
        # partials don't need to be compiled as they
        # are included in other templates (layouts or views)
        engine.transpile(newTpl, pkgr)
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
      engine.transpile(tpl, pkgr)
      when defined timHotCode:
        notifyAllClients()
    of ttPartial:
      # refresh changed partial dependencies first
      parsePartial(engine, tpl)
      # re-transpile all recursive dependants
      for depPath in engine.depResolver.dependants(tpl.src):
        let depTpl = engine.getTemplateByPath(depPath)
        if depTpl == nil: continue
        case depTpl.templateType
        of ttView, ttLayout:
          engine.transpile(depTpl, pkgr)
        of ttPartial:
          parsePartial(engine, depTpl)
        # clear the cached AST of the dependants to force
        # re-parsing and updating their dependencies
        codegenCache.cachedAst.del(tpl.src)
      when defined timHotCode:
        notifyAllClients()
    hasChanges = true

  # Callback `onDelete`
  proc onDelete(file: watchout.File) =
    # Runs when detecting a deleted template
    let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
    if tpl != nil:
      # if the template is found, remove it from the engine tables
      # and clear its dependencies from the resolver. We also need
      # to re-transpile all the dependants of the deleted template to update
      # their dependencies and remove the deleted template from their dependency list
      engine.depResolver.clearFile(normalizedPath(tpl.src))
      case tpl.templateType
      of ttView:
        engine.views.del(tpl.src)
      of ttLayout:
        engine.layouts.del(tpl.src)
      of ttPartial:
        engine.partials.del(tpl.src)

  when defined timHotCode:
    startWebSocket(port = Port(9000))
    sleep(100)

  browserSyncWatcher.onFound = onFound
  browserSyncWatcher.onChange = onChange
  browserSyncWatcher.onDelete = onDelete
  browserSyncWatcher.start()