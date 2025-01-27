# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, json, monotimes, times, strutils]

import pkg/[jsony, flatty]
import pkg/kapsis/[cli, runtime] 

import ../engine/[parser, ast]
import ../engine/logging
import ../engine/compilers/[html, nimc]

proc srcCommand*(v: Values) = 
  ## Transpiles a `.timl` file to a target source
  let
    fpath = $(v.get("timl").getPath)
    ext = v.get("-t").getStr
    pretty = v.has("--pretty")
    flagNoCache = v.has("--nocache")
    flagRecache = v.has("--recache")
    hasDataFlag = v.has("--data")
    hasJsonFlag = v.has("--json-errors")
    outputPath = if v.has("-o"): v.get("-o").getStr else: ""
    enableBenchmark = v.has("--bench")
    # enableWatcher = v.has("w")
  let jsonData: JsonNode =
    if hasDataFlag: v.get("--data").getJson
    else: nil
  let name = fpath
  let timlCode = readFile(getCurrentDir() / fpath)
  let t = getMonotime()
  let p = parseSnippet(name, timlCode, flagNoCache, flagRecache)
  if likely(not p.hasErrors):
    if ext == "html":
      let c = html.newCompiler(
        ast = parser.getAst(p),
        minify = (pretty == false),
        data = jsonData
      )
      if likely(not c.hasErrors):
        let benchTime = getMonotime() - t
        if outputPath.len > 0:
          writeFile(outputPath, c.getHtml.strip)
        else:
          display c.getHtml().strip
        if enableBenchmark:
          displayInfo("Done in " & $benchTime)
      else:
        if not hasJsonFlag:
          for err in c.logger.errors:
            display err
          displayInfo c.logger.filePath
        else:
          let outputJsonErrors = newJArray()
          for err in c.logger.errorsStr:
            add outputJsonErrors, err
          display jsony.toJson(outputJsonErrors)
        if enableBenchmark:
          displayInfo("Done in " & $(getMonotime() - t))
        quit(1)
    elif ext == "nim":
      let c = nimc.newCompiler(parser.getAst(p))
      display c.exportCode()
      if enableBenchmark:
        displayInfo("Done in " & $(getMonotime() - t))
    else:
      displayError("Unknown target `" & ext & "`")
      if enableBenchmark:
        displayInfo("Done in " & $(getMonotime() - t))
      quit(1)
  else:
    for err in p.logger.errors:
      display(err)
    displayInfo p.logger.filePath
    if enableBenchmark:
      displayInfo("Done in " & $(getMonotime() - t))
    quit(1)

proc astCommand*(v: Values) =
  ## Build binary AST from a `timl` file
  let fpath = v.get("timl").getPath.path
  let opath = normalizedPath(getCurrentDir() / v.get("output").getFilename)
  let p = parseSnippet(fpath, readFile(getCurrentDir() / fpath))
  if likely(not p.hasErrors):
    writeFile(opath, flatty.toFlatty(parser.getAst(p)))

proc reprCommand*(v: Values) =
  ## Read a binary AST to target source
  let fpath = v.get("ast").getPath.path
  let ext = v.get("ext").getStr
  let pretty = v.has("pretty")
  if ext == "html":
    let c = html.newCompiler(flatty.fromFlatty(readFile(fpath), Ast), pretty == false)
    display c.getHtml().strip
  elif ext == "nim":
    let c = nimc.newCompiler(flatty.fromFlatty(readFile(fpath), Ast))
    display c.exportCode()
  else:
    displayError("Unknown target `" & ext & "`")
    quit(1)

import std/[xmltree, ropes, strtabs, sequtils]
import pkg/htmlparser

proc htmlCommand*(v: Values) =
  ## Transpile HTML code to Tim code
  let filepath = $(v.get("html_file").getPath)
  displayWarning("Work in progress. Unstable results")
  var indentSize = 0
  var timldoc: Rope
  var inlineNest: bool
  proc parseHtmlNode(node: XmlNode, toInlineNest: var bool = inlineNest) =
    var isEmbeddable: bool
    case node.kind
    of xnElement:
      let tag: HtmlTag = node.htmlTag()
      if not toInlineNest:
        add timldoc, indent(ast.getHtmlTag(tag), 2 * indentSize)
      else:
        add timldoc, " > " & ast.getHtmlTag(tag)
        inlineNest = false
      isEmbeddable =
        if tag in {tagScript, tagStyle}: true
        else: false
      # handle node attributes
      if node.attrsLen > 0:
        var attrs: Rope
        for k, v in node.attrs():
          if k == "class":
            add attrs, rope("." & join(v.split(), "."))
          elif k == "id":
            add attrs, rope("#" & v.strip)
          else:
            add attrs, rope(" " & k & "=\"" & v & "\"")
        add timldoc, attrs
      # handle child nodes
      let subNodes = node.items.toSeq()
      if subNodes.len > 1:
        if subNodes[0].kind == xnText:
          if subNodes[0].innerText.strip().len == 0:
            if subNodes[1].kind != xnText:
              if subNodes.len == 3:
                inlineNest = true
                for subNode in subNodes: 
                  parseHtmlNode(subNode, inlineNest)
                return
              else:
                add timldoc, "\n"
        else:
          add timldoc, "\n"
        inc indentSize
        for subNode in subNodes: 
          parseHtmlNode(subNode)
        dec indentSize
      elif subNodes.len == 1:
        let subNode = subNodes[0]
        case subNode.kind
        of xnText:
          if not isEmbeddable:
            add timlDoc, ": \"" & subNode.innerText.strip() & "\"\n"
          else:
            add timlDoc, ": \"\"\"" & subNode.innerText.strip() & "\"\"\"\n"
        else: discard
      else:
        add timldoc, "\n" # self-closing tags requires new line at the end
        inlineNest = false
    of xnText:
      let innerText = node.innerText
      if innerText.strip().len > 0:
        if not isEmbeddable:
          add timlDoc, ": \"" & innerText.strip() & "\"\n"
        else:
          add timlDoc, ": \"\"\"" & innerText.strip() & "\"\"\"\n"
    else: discard

  let htmldoc = htmlparser.loadHtml(getCurrentDir() / filepath)
  for node in htmldoc:
    case node.kind
    of xnElement:
      parseHtmlNode(node)
    else: discard

  echo timldoc
