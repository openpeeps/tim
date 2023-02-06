import std/tables
import pkg/[watchout, klymene/cli]
import tim/engine/[ast, parser, meta, compiler/transpiler]

from std/os import getCurrentDir
from std/times import cpuTime

const DockType = "<!DOCTYPE html>"

var Tim*: TimEngine
const DefaultLayout = "base"

proc compileCode(engine: TimEngine, t: var TimlTemplate) =
  var p = engine.parse(t.getSourceCode(), t.getFilePath(), templateType = t.getType())
  if p.hasError():
    display p.getError()
    return
  var c = newCompiler(p.getStatements, t, engine.shouldMinify,
                      engine.getIndent, t.getFilePath)
  if c.hasError():
    display t.getFilePath
    for err in c.getErrors():
      display err

proc precompile*(engine: var TimEngine, callback: proc() {.gcsafe, nimcall.} = nil,
        debug = false): seq[string] {.discardable.} =
  ## Pre-compile ``views`` and ``layouts``
  ## from ``.timl`` to HTML or BSON.
  ##
  ## Note that ``partials`` contents are collected on
  ## compile-time and merged within the view.
  if Tim.hasAnySources:
    # Will use `watchout` to watch for changes in `/templates` dir
    display "✨ Watching for changes..."
    proc watchoutCallback(file: watchout.File) {.closure.} =
      let initTime = cpuTime()
      display "✨ Changes detected"
      display file.getName(), indent = 3
      var timlTemplate = getTemplateByPath(Tim, file.getPath())
      if timlTemplate.isPartial:
        for depView in timlTemplate.getDependentViews():
          Tim.compileCode(getTemplateByPath(Tim, depView))
      else:
        Tim.compileCode(timlTemplate)
      display("Done in " & $(cpuTime() - initTime), indent = 2)
      if callback != nil: # Run a custom callback, if available
        callback()

    var watchFiles: seq[string]
    for id, view in Tim.getViews().mpairs():
      Tim.compileCode(view)
      watchFiles.add view.getFilePath()
      result.add view.getName()
    
    for id, partial in Tim.getPartials().pairs():
      # Watch for changes in `partials` directory.
      watchFiles.add partial.getFilePath()

    for id, layout in Tim.getLayouts().mpairs():
      Tim.compileCode(layout)
      watchFiles.add layout.getFilePath()
      result.add layout.getName()

    # Start a new Thread with Watchout watching for live changes
    startThread(watchoutCallback, watchFiles, 450, shouldJoinThread = true)
  else: display("Can't find views")