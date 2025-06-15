import std/[os, tables, strutils, sequtils, options]

import pkg/libdatachannel/[bindings, websockets]
import pkg/[watchout, jsony]

import ./configurator

import ../engine/[ast, parser, codegen, chunk, vm, sym]
import ../engine/stdlib/[libsystem, libtimes, libstrings]

type
  TimTemplateType* = enum
    ## Type of the Tim template
    ttView = "view"
    ttLayout = "layout"
    ttPartial = "partial"

  TimTemplate* = ref object
    ## Object representing a Tim template
    src*: string
      ## the absolute path to the template source file
    templateType: TimTemplateType
      ## the type of the template (view, layout or partial)

  TimEngine* = ref object
    config: TimConfig
    views, layouts, partials: Table[string, TimTemplate]
      ## Tables to store templates by their source path

proc newTim*(src, output, basepath: string): TimEngine =
  let sourcePath = normalizedPath(basepath / src)
  result = TimEngine(
    config: TimConfig(
      `type`: ConfigType.typeProject,
      compilation: CompilationSettings(
        source: src,
        output: output,
        layoutsPath: sourcePath / "layouts",
        viewsPath: sourcePath / "views",
        partialsPath: sourcePath / "partials",
        target: TargetSource.tsHtml
      )
    )
  )

proc getTemplateByPath*(engine: TimEngine, path: string): TimTemplate =
  ## Get a Tim template by its source path.
  ## Returns a TimTemplate object with the template type set to `ttView`.
  if path in engine.views:
    return engine.views[path]

  if path in engine.layouts:
    return engine.layouts[path]

  if path in engine.partials:
    return engine.partials[path]

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

proc execute*(engine: TimEngine, tpl: TimTemplate) =
  ## Transpile the Tim template code.
  var astProgram: Ast
  try:
    parser.parseScript(astProgram, readFile(tpl.src))
  except TimParserError as e:
    echo "Error parsing template: ", e.msg
    return
  
  var
    mainChunk = newChunk()
    script = newScript(mainChunk)
    module = newModule(tpl.src.extractFilename, some(tpl.src))

  # load standard library modules
  let systemModule = modSystem(script)
  module.load(systemModule)

  let stringsLib = initStrings(script, systemModule)
  module.load(stringsLib)

  script.stdpos = script.procs.high

  # Init Tim Engine code generation
  var compiler = codegen.initCodeGen(script, module, mainChunk)
  compiler.genScript(astProgram,
    some(engine.config.compilation.partialsPath),
    isMainScript = true
  )
  let vmInstance = newVm()
  let output = vmInstance.interpret(script, mainChunk)
  # todo handle output

var
  browserSyncWatcher: Watchout
  wsServerConfig = initWebSocketConfig()
  hasChanges: bool

proc precompile*(engine: TimEngine, firstRun: bool = false) =
  ## Precompile Tim Engine templates.
  ## This proc is usually called before starting the development server.
  ## When the browser sync is enabled, it will watch for changes in the templates
  ## and recompile them on the fly.
  browserSyncWatcher = 
    newWatchout(@[
      engine.config.compilation.layoutsPath,
      engine.config.compilation.viewsPath,
      engine.config.compilation.partialsPath
    ], "*.timl")

  # Callback `onFound`
  proc onFound(file: watchout.File) =
    # Runs when detecting a new template.
    let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
    if tpl != nil:
      case tpl.templateType
      of ttView, ttLayout:
        engine.execute(tpl)
      else: discard
    else:
      # if the template is not registered,
      # we need to register it and compile it
      let newTpl = engine.registerTemplate(file.getPath())
      if newTpl.templateType != ttPartial:
        # partials don't need to be compiled as they
        # are included in other templates (layouts or views)
        engine.execute(newTpl)

  # Callback `onChange`
  proc onChange(file: watchout.File) =
    # Runs when detecting changes
    let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
    case tpl.templateType
    of ttView, ttLayout:
      # if the template is a view or layout, compile it
      engine.execute(tpl)
    else:
      # otherwise, we'll need to search for the templates
      # that load the current partial template and recompile them
      discard
      # engine.importsHandle.excl(file.getPath())
      # engine.resolveDependants(engine.importsHandle.dependencies(file.getPath).toSeq)
    hasChanges = true

  # Callback `onDelete`
  proc onDelete(file: watchout.File) =
    # Runs when detecting a deleted template
    let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
    if tpl != nil:
      case tpl.templateType
      of ttView:
        engine.views.del(tpl.src)
      of ttLayout:
        engine.layouts.del(tpl.src)
      of ttPartial:
        engine.partials.del(tpl.src)
  
  browserSyncWatcher.onFound = onFound
  browserSyncWatcher.onChange = onChange
  browserSyncWatcher.onDelete = onDelete
  browserSyncWatcher.start()