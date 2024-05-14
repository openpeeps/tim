import std/[os, strutils]
import pkg/kapsis/[cli, runtime] 
import ../engine/parser
import ../engine/logging
import ../engine/compilers/[html, nimc]

proc srcCommand*(v: Values) = 
  ## Transpiles a `.timl` file to a target source
  let
    fpath = v.get("timl").getStr
    ext = v.get("ext").getStr
    pretty = v.has("pretty")
    # enableWatcher = v.has("w")
  var
    name: string
    timlCode: string
  if v.has"code":
    timlCode = fpath
  else:
    name = fpath
    timlCode = readFile(getCurrentDir() / fpath)
  let p = parseSnippet(name, timlCode)
  if likely(not p.hasErrors):
    if ext == "html":
      let c = html.newCompiler(parser.getAst(p), pretty == false)
      if likely(not c.hasErrors):
        display c.getHtml().strip
        discard
      else:
        for err in c.logger.errors:
          display err
        displayInfo c.logger.filePath
        quit(1)
    elif ext == "nim":
      let c = nimc.newCompiler(parser.getAst(p))
      display c.exportCode()
    else:
      displayError("Unknown target `" & ext & "`")
      quit(1)
  else:
    for err in p.logger.errors:
      display(err)
    displayInfo p.logger.filePath
    quit(1)


# import std/critbits

# type
#   ViewHandle* = proc(): string
#   LayoutHandle* = proc(viewHtml: string): string
#   ViewsTree* = CritBitTree[ViewHandle]
#   LayoutsTree* = CritBitTree[LayoutHandle]

# proc getIndex(): string =
#   result = "view html"

# var views = ViewsTree()
# views["index"] = getIndex

# proc getBaseLayout(viewHtml: string): string =
#   result = "start layout"
#   add result, viewHtml
#   add result, "end layout"

# var layouts = LayoutsTree()
# layouts["base"] = getBaseLayout

# template render*(viewName: string, layoutName = "base"): untyped =
#   if likely(views.hasKey(viewName)):
#     let viewHtml = views[viewName]()
#     if likely(layouts.hasKey(layoutName)):
#       layouts[layoutName](viewHtml)
#     else: ""
#   else: ""

# echo render("index")