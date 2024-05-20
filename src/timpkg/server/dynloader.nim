# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

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
elif defined windows:
  const ext = ".dll"
else:
  const ext = ".so"

proc load*(collection: DynamicTemplates, t: string) =
  ## Load a dynamic template
  var tpl = DynamicTemplate(lib: loadLib(t & ext))
  tpl.function = cast[Renderer](tpl.lib.symAddr("renderTemplate"))
  collection.templates[t] = tpl

proc reload*(collection: DynamicTemplates, t: string) =
  ## Reload a dynamic template
  discard

proc unload*(collection: DynamicTemplates, t: string) =
  ## Unload a dynamic template
  dynlib.unloadLib(collection.templates[t].lib)
  reset(collection.templates[t])
  collection.templates.del(t)

proc render*(collection: DynamicTemplates, t: string): string =
  ## Render a dynamic template
  if likely(collection.templates.hasKey(t)):
    return collection.templates[t].function(this = %*{"x": "ola!"})
