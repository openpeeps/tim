import std/[unittest, os, htmlparser, xmltree, strtabs, sequtils]
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

proc load(x: string): string =
  readFile(currentSourcePath().parentDir / "snippets" / x & ".timl")

test "assignment var":
  const code = """
var a = 123
h1: $a
var b = {}
  """
  let x = toHtml("test_var", code)
  check x[0].hasErrors == false
  check x[1].hasErrors == false

test "invalid timl code":
  let x = toHtml("invalid", load("invalid"))
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
  span.none
  """
  assert tim.toHtml("test_if", code) ==
    """<span class="none"></span>"""

test "loops for":
  let code = """
var fruits = ["satsuma", "watermelon", "orange"]
for $fruit in $fruits:
  span data-fruit=$fruit: $fruit
  """
  assert tim.toHtml("test_loops", code) ==
    """<span data-fruit="satsuma">satsuma</span><span data-fruit="watermelon">watermelon</span><span data-fruit="orange">orange</span>"""

test "loops for + nested elements":
  let code = """
section#main > div.my-4 > ul.text-center
  for $x in ["barberbeats", "vaporwave", "aesthetic"]:
    li.d-block > span.fw-bold: $x"""
  assert tim.toHtml("test_loops_nested", code) ==
    """<section id="main"><div class="my-4"><ul class="text-center"><li class="d-block"><span class="fw-bold">barberbeats</span></li><li class="d-block"><span class="fw-bold">vaporwave</span></li><li class="d-block"><span class="fw-bold">aesthetic</span></li></ul></div></section>"""

test "loops for in range":
  let code = """
for $i in 0..4:
  i: $i"""
  assert tim.toHtml("for_inrange", code) ==
    """<i>0</i><i>1</i><i>2</i><i>3</i><i>4</i>"""

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

test "loops while block + inc break":
  let code = """
var i = 0
while true:
  if $i == 100:
    break
  inc($i)
span: "Total: " & $i.toString"""
  assert tim.toHtml("test_while_inc", code) ==
    """<span>Total: 100</span>"""

test "loops while block + dec break":
  let code = """
var i = 100
while true:
  if $i == 0:
    break
  dec($i)
span: "Remained: " & $i.toString"""
  assert tim.toHtml("test_while_dec", code) ==
    """<span>Remained: 0</span>"""

test "loops while block + dec":
  let code = """
var i = 100
while $i != 0:
  dec($i)
span: "Remained: " & $i.toString"""
  assert tim.toHtml("test_while_dec", code) ==
    """<span>Remained: 0</span>"""

test "function return string":
  let code = """
fn hello(x: string): string =
  return $x
h1: hello("Tim is awesome!")
  """
  assert tim.toHtml("test_function", code) ==
    """<h1>Tim is awesome!</h1>"""

test "function return int":
  let code = """
fn hello(x: int): int =
  return $x + 10
h1: hello(7)
  """
  assert tim.toHtml("test_function", code) ==
    """<h1>17</h1>"""

test "objects anonymous function":
  let code = """
@import "std/strings"
@import "std/os"

var x = {
  getHello:
    fn(x: string): string {
      return toUpper($x & " World")
    }
}
h1: $x.getHello("Hello")
  """
  assert tim.toHtml("anonymous_function", code) ==
    """<h1>HELLO WORLD</h1>"""

test "std/strings":
  let x = toHtml("std_strings", load("std_strings"))
  assert x[1].hasErrors == false

test "std/arrays":
  let x = toHtml("std_arrays", load("std_arrays"))
  assert x[1].hasErrors == false

test "std/objects":
  let x = toHtml("std_objects", load("std_objects"))
  assert x[1].hasErrors == false