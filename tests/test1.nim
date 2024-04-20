import std/[unittest, htmlparser, xmltree, strtabs, sequtils]
import ../src/tim

var t = newTim("./app/templates", "./app/storage",
    currentSourcePath(), minify = false, indent = 2)

test "precompile":
  t.precompile(flush = true, waitThread = false)

test "render index":
  echo t.render("index")

test "check layout":
  let html = t.render("index").parseHtml
  # check `meta` tags
  let meta = html.findAll("meta").toSeq
  check meta.len == 2
  check meta[0].attrs["charset"] == "utf-8"

  check meta[1].attrsLen == 2
  check meta[1].attrs.hasKey("name")
  check meta[1].attrs.hasKey("content")


  let title = html.findAll("title").toSeq
  check title.len == 1
  check title[0].innerText == "Tim Engine is Awesome!"

import std/sequtils
import ../src/tim/engine/[logging, parser, compilers/html]

proc toHtml(id, code: string): (Parser, HtmlCompiler) =
  result[0] = parseSnippet(id, code)  
  result[1] = newCompiler(result[0].getAst, false)

test "language test var":
  const code = """
var a = 123
h1: $a
var b = {}
  """
  let x = toHtml("test_var", code)
  check x[0].hasErrors == false
  check x[1].hasErrors == false

test "language test const":
  const code = """
const x = 123
h1: $x
$x = 321
  """
  let x = toHtml("test_var", code)
  check x[0].hasErrors == false
  check x[1].hasErrors == true
  # echo x[1].logger.errors.toSeq()
