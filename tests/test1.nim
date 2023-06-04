import tim
import std/[unittest, json, htmlparser, xmltree, strtabs]
from std/os import getCurrentDir, dirExists, fileExists

Tim.init(
  source = "./examples/templates",
  output = "./examples/storage/templates",
  minified = false,
  indent = 2
)

Tim.setData(%*{
  "appName": "My application",
  "production": false,
  "keywords": ["template-engine", "html", "tim", "compiled", "templating"],
})

test "can init":
  check Tim.templatesExists == true
  check Tim.getIndent == 2
  check Tim.shouldMinify == false

test "can precompile":
  Tim.precompile()

test "can render (file)":
  let output = Tim.render("index").parseHtml
  for h1 in output.findAll("h1"):
    check h1.attrs.hasKey("class") == true
    check h1.attrs["class"] == "fw-bold"
    check h1.attrsLen == 1
    check h1.innerText == "This is Tim Engine!"
  for p in output.findAll("p"):
    check p.attrs.hasKey("class") == true
    check p.attrs["class"] == "lead"
    check p.attrsLen == 1
    check p.innerText == "A high-performance template engine & markup language"

test "can render (code)":
  var output = tim2html("div > span: \"Hello\"", true)
  check output == "<div><span>Hello</span></div>"

  output = tim2html("""
a.text-link href="https://openpeeps.github.io/tim/": "API Reference"
  """)
  let xmlcode = output.parseHtml
  for a in xmlcode.findAll("a"):
    check a.attrsLen == 2
    check a.attrs["class"] == "text-link"

test "can render loop (code)":
  var output = tim2html("""
for $x in $this.list:
  span: $x
  """, data = %*{
    "list": ["one", "two", "three"]
  })
  check output.parseHtml.findAll("span").len == 3

test "can render conditionals (code)":
  var output = tim2html("""
if $this.hello == "world"
  span: "Hello World"

if $this.enabled != true:
  span: "Disabled"
else:
  span: "Enabled"

if $this.counter < 120:
  span: "less than 120"
elif $this.counter >= 120:
  span: "greater or equal"
else:
  span > u: "nothing here"

  """, data = %*{
    "hello": "world",
    "enabled": true,
    "counter": 120
  })
  echo output