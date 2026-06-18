import std/[unittest, os, monotimes, times, json, tables, options, strutils]

include ../src/tim/engine/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value, resolver]
import ../src/tim/engine/[errors, parser]
import ../src/tim/engine/stdlib/[libsystem, libstrings, libarrays, libjson]
from ../src/tim/meta/initializer import declareGlobals

type
  Compiled = object
    script: Script
    chunk: Chunk
    localData: JsonNode
    globalData: JsonNode

proc parserCallback(astProgram: var Ast, path: string, resolver: FileResolver) =
  parser.parseScript(astProgram, readFile(path), path)

proc compile(code: string; localData = newJObject(); globalData = newJObject()): Compiled =
  var astTree: Ast
  parser.parseScript(astTree, code, "bench")

  var mainChunk = newChunk("bench")
  var script = newScript(mainChunk)
  var module = newModule("bench", some("bench"))

  let systemModule = libsystem.loadLibrary(script)
  module.load(systemModule)

  let stringsLib = initStrings(script, systemModule)
  module.load(stringsLib)
  let arraysLib = initArrays(script, systemModule)
  module.load(arraysLib)
  let jsonLib = initJSON(script, systemModule)
  module.load(jsonLib)

  script.stdpos = script.procs.high

  var compiler = codegen.initCompiler(script, module, mainChunk, nil, nil, parserCallback)
  compiler.declareGlobals()
  compiler.genScript(program = astTree, includePath = some(getCurrentDir()))

  Compiled(script: script, chunk: mainChunk, localData: localData, globalData: globalData)

template benchmark(benchName: string; iterations: int; body: untyped): void =
  for _ in 0..<5:
    body
  let start = getMonoTime()
  for _ in 0..<iterations:
    body
  let elapsed = getMonoTime() - start
  let totalNs = elapsed.inNanoseconds
  let totalMs = totalNs.float / 1_000_000.0
  let meanUs = totalNs.float / (iterations.float * 1000.0)
  let opsPerSec = iterations.float * 1_000_000_000.0 / totalNs.float
  echo alignLeft(benchName, 35) & " " & align($iterations, 8) &
    "  " & align(formatFloat(totalMs, ffDecimal, 3), 12) &
    "  " & align(formatFloat(meanUs, ffDecimal, 3), 12) &
    "  " & align(formatFloat(opsPerSec, ffDecimal, 0), 12)

suite "VM Benchmarks":
  echo "\n=== Tim Engine VM Benchmarks (pre-compiled templates) ==="
  const
    hBench = "Benchmark"
    hIter = "Iterations"
    hTotal = "Total (ms)"
    hMean = "Mean (µs)"
    hOps = "Ops/sec"
  echo alignLeft(hBench, 35) & " " & align(hIter, 8) &
    "  " & align(hTotal, 12) & "  " & align(hMean, 12) & "  " & align(hOps, 12)
  echo repeat("─", 85)

  test "VM — static HTML":
    let code = """
div.container > div.row > div.col-12
  h1: "Hello World"
  p: "This is a simple template."
  span.badge: "Note"
"""
    let compiled = compile(code)
    doAssert $(newVM().interpret(compiled.script, compiled.chunk,
      localData = compiled.localData, globalData = compiled.globalData)) != ""
    benchmark("VM — static HTML", 10_000):
      discard $(newVM().interpret(compiled.script, compiled.chunk,
        localData = compiled.localData, globalData = compiled.globalData))

  test "VM — dynamic data":
    let code = """
h1: "Hello, " & $this["name"] & "!"
p: "You are " & $this["age"] & " years old."
span: $this["role"]
"""
    var data = newJObject()
    data["name"] = newJString("Alice")
    data["age"] = newJString("30")
    data["role"] = newJString("Developer")
    let compiled = compile(code, data)
    doAssert $(newVM().interpret(compiled.script, compiled.chunk,
      localData = compiled.localData, globalData = compiled.globalData)) != ""
    benchmark("VM — dynamic data", 10_000):
      discard $(newVM().interpret(compiled.script, compiled.chunk,
        localData = compiled.localData, globalData = compiled.globalData))

  test "VM — conditionals (true)":
    let code = """
if $this["flag"] == true:
  p: "Condition is true"
else:
  p: "Condition is false"
"""
    var data = newJObject()
    data["flag"] = newJBool(true)
    let compiled = compile(code, data)
    doAssert $(newVM().interpret(compiled.script, compiled.chunk,
      localData = compiled.localData, globalData = compiled.globalData)) != ""
    benchmark("VM — conditionals (true)", 10_000):
      discard $(newVM().interpret(compiled.script, compiled.chunk,
        localData = compiled.localData, globalData = compiled.globalData))

  test "VM — conditionals (false)":
    let code = """
if $this["flag"] == true:
  p: "Condition is true"
else:
  p: "Condition is false"
"""
    var data = newJObject()
    data["flag"] = newJBool(false)
    let compiled = compile(code, data)
    doAssert $(newVM().interpret(compiled.script, compiled.chunk,
      localData = compiled.localData, globalData = compiled.globalData)) != ""
    benchmark("VM — conditionals (false)", 10_000):
      discard $(newVM().interpret(compiled.script, compiled.chunk,
        localData = compiled.localData, globalData = compiled.globalData))

  test "VM — loops (10 items)":
    let code = """
ul
  for $item in $this["items"]:
    li: $item
"""
    var data = newJObject()
    var items = newJArray()
    for i in 1..10:
      items.add(newJString("Item " & $i))
    data["items"] = items
    let compiled = compile(code, data)
    doAssert $(newVM().interpret(compiled.script, compiled.chunk,
      localData = compiled.localData, globalData = compiled.globalData)) != ""
    benchmark("VM — loops (10 items)", 10_000):
      discard $(newVM().interpret(compiled.script, compiled.chunk,
        localData = compiled.localData, globalData = compiled.globalData))

  test "VM — loops (1000 items)":
    let code = """
ul
  for $item in $this["items"]:
    li: $item
"""
    var data = newJObject()
    var items = newJArray()
    for i in 1..1000:
      items.add(newJString("Item " & $i))
    data["items"] = items
    let compiled = compile(code, data)
    doAssert $(newVM().interpret(compiled.script, compiled.chunk,
      localData = compiled.localData, globalData = compiled.globalData)) != ""
    benchmark("VM — loops (1000 items)", 1000):
      discard $(newVM().interpret(compiled.script, compiled.chunk,
        localData = compiled.localData, globalData = compiled.globalData))

  test "VM — string stdlib":
    let code = """
p: toUpper("hello world") & " " & toLower("GOODBYE WORLD")
"""
    let compiled = compile(code)
    doAssert $(newVM().interpret(compiled.script, compiled.chunk,
      localData = compiled.localData, globalData = compiled.globalData)) != ""
    benchmark("VM — string stdlib", 10_000):
      discard $(newVM().interpret(compiled.script, compiled.chunk,
        localData = compiled.localData, globalData = compiled.globalData))

  test "VM — deep nesting":
    let code = """
div > div > div > div > div > div > div > div > div > div
  div > div > div > div > div > div > div > div > div > div
    div > div > div > div > div > div > div > div > div > div
      span: "Deeply nested content"
"""
    let compiled = compile(code)
    doAssert $(newVM().interpret(compiled.script, compiled.chunk,
      localData = compiled.localData, globalData = compiled.globalData)) != ""
    benchmark("VM — deep nesting", 10_000):
      discard $(newVM().interpret(compiled.script, compiled.chunk,
        localData = compiled.localData, globalData = compiled.globalData))

  test "VM — mixed template":
    let code = """
div.container
  nav.navbar
    div.container-fluid
      a.navbar-brand href="/": "MyApp"
      ul.navbar-nav
        for $link in $this["navLinks"]:
          li.nav-item
            a.nav-link href=$link["url"]: $link["label"]
  div.content
    if $this["user"]["loggedIn"] == true:
      div.card
        div.card-body
          h5: "Welcome back, " & $this["user"]["name"] & "!"
          p: "You have " & $this["notifications"] & " new notifications."
    else:
      div.alert.alert-warning
        p: "Please log in to continue."
    div.row
      for $product in $this["products"]:
        div.col-md-4
          div.card
            img.card-img-top src=$product["image"]
            div.card-body
              h5: $product["name"]
              p: $product["description"]
              p.fw-bold: "$" & $product["price"]
"""
    var data = newJObject()
    var navLinks = newJArray()
    var homeLink = newJObject(); homeLink["url"] = newJString("/"); homeLink["label"] = newJString("Home"); navLinks.add(homeLink)
    var aboutLink = newJObject(); aboutLink["url"] = newJString("/about"); aboutLink["label"] = newJString("About"); navLinks.add(aboutLink)
    var contactLink = newJObject(); contactLink["url"] = newJString("/contact"); contactLink["label"] = newJString("Contact"); navLinks.add(contactLink)
    data["navLinks"] = navLinks
    var user = newJObject()
    user["loggedIn"] = newJBool(true)
    user["name"] = newJString("Alice")
    data["user"] = user
    data["notifications"] = newJInt(5)
    var products = newJArray()
    for i in 1..8:
      var p = newJObject()
      p["name"] = newJString("Product " & $i)
      p["description"] = newJString("Description of product " & $i)
      p["price"] = newJFloat(19.99 + i.float)
      p["image"] = newJString("/images/product" & $i & ".jpg")
      products.add(p)
    data["products"] = products
    let compiled = compile(code, data)
    doAssert $(newVM().interpret(compiled.script, compiled.chunk,
      localData = compiled.localData, globalData = compiled.globalData)) != ""
    benchmark("VM — mixed template", 5_000):
      discard $(newVM().interpret(compiled.script, compiled.chunk,
        localData = compiled.localData, globalData = compiled.globalData))

  echo repeat("─", 85)
