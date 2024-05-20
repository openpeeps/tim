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
import ../src/timpkg/engine/[logging, parser, compilers/html]

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
  let code = """
const x = 123
h1: $x
$x = 321
  """
  let x = toHtml("test_var", code)
  check x[0].hasErrors == false
  check x[1].hasErrors == true

test "conditions if":
  let code = """
if 0 == 0:
  span: "looks true to me""""
  assert tim.toHtml("test_if", code) ==
    """<span>looks true to me</span>"""

test "conditions if/else":
  let code = """
if 1 != 1:
  span: "looks true to me"
else:
  span.just-some-basic-stuff: "this is basic""""
  assert tim.toHtml("test_if", code) ==
    """<span class="just-some-basic-stuff">this is basic</span>"""

test "conditions if/elif":
  let code = """
if 1 != 1:
  span: "looks true to me"
elif 1 == 1:
  span.just-some-basic-stuff: "this is basic""""
  assert tim.toHtml("test_if", code) ==
    """<span class="just-some-basic-stuff">this is basic</span>"""

test "conditions if/elif/else":
  let code = """
if 1 != 1:
  span: "looks true to me"
elif 1 > 1:
  span.just-some-basic-stuff: "this is basic"
else:
  span"""
  assert tim.toHtml("test_if", code) ==
    """<span></span>"""

test "loops for":
  let code = """
var fruits = ["satsuma", "watermelon", "orange"]
for $fruit in $fruits:
  span data-fruit=$fruit: $fruit
  """
  assert tim.toHtml("test_loops", code) ==
    """<span data-fruit="satsuma">satsuma</span><span data-fruit="watermelon">watermelon</span><span data-fruit="orange">orange</span>"""

test "loops using * multiplier":
  let code = """
const items = ["keyboard", "speakers", "mug"]
li * 3: $i + 1 & " - " & $items[$i]"""
  assert tim.toHtml("test_multiplier", code) ==
    """<li>1 - keyboard</li><li>2 - speakers</li><li>3 - mug</li>"""

test "loops using * var multiplier":
  let code = """
const x = 3
const items = ["keyboard", "speakers", "mug"]
li * $x: $items[$i]"""
  assert tim.toHtml("test_multiplier", code) ==
    """<li>keyboard</li><li>speakers</li><li>mug</li>"""
