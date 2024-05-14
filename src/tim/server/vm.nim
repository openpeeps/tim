# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

## This module implements a high-performance Just-in-Time
import std/[tables, dynlib, json]
type
  DynamicTemplate = object
    name: string
    lib: LibHandle
    function: Renderer
  Renderer = proc(app, this: JsonNode = newJObject()): string {.gcsafe, stdcall.}
  DynamicTemplates* = ref object
    templates: OrderedTableRef[string, DynamicTemplate] = newOrderedTable[string, Dynamictemplate]()

when defined macosx:
  const ext = ".dylib"
elif windows:
  const ext = ".dll"
else:
  const ext = ".so"

proc load*(collection: DynamicTemplates, t: string) =
  ## Load a Dynamic template
  var tpl = DynamicTemplate(lib: loadLib(t & ext))
  tpl.function = cast[Renderer](tpl.lib.symAddr("renderTemplate"))
  collection.templates[t] = tpl

proc reload*(collection: DynamicTemplates, t: string) =
  ## Reload a Dynamic template
  discard

proc unload*(collection: DynamicTemplates, t: string) =
  ## Unload a Dynamic template
  dynlib.unloadLib(collection.templates[t].lib)
  reset(collection.templates[t])
  collection.templates.del(t)

proc render*(collection: DynamicTemplates, t: string): string =
  if likely(collection.templates.hasKey(t)):
    return collection.templates[t].function(this = %*{"x": "ola!"})
