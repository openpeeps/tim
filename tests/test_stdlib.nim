import std/[unittest, os, json, strutils, options, times]
include ../src/tim/engine/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value, resolver]
import ../src/tim/engine/[errors, parser]
import ../src/tim/engine/stdlib/[libsystem, libstrings, libarrays, libjson]
from ../src/tim/meta/initializer import declareGlobals

proc parserCallback(astProgram: var Ast, path: string, resolver: FileResolver) =
  parser.parseScript(astProgram, readFile(path), path)

proc render(code: string; localData = newJObject(); globalData = newJObject()): string =
  var astTree: Ast
  parser.parseScript(astTree, code, "test")
  var mainChunk = newChunk("test")
  var script = newScript(mainChunk)
  var module = newModule("test", some("test"))
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
  let vmm = newVM()
  result = $(vmm.interpret(script, mainChunk, localData = localData, globalData = globalData))

suite "Stdlib — libsystem":
  test "type introspection":
    check render("""p: type(42)""") == "<p>int</p>"
    check render("""p: type(1)""") == "<p>int</p>"
    check render("""p: type(true)""") == "<p>bool</p>"
    check render("""p: type("hello")""") == "<p>string</p>"

  test "math — abs":
    check render("""p: abs(-5)""") == "<p>5</p>"
    check render("""p: abs(3)""") == "<p>3</p>"
    check render("""p: abs(-3.7)""") == "<p>3.7</p>"

  test "math — min / max":
    check render("""p: min(3, 7)""") == "<p>3</p>"
    check render("""p: max(3, 7)""") == "<p>7</p>"

  test "math — round / floor / ceil":
    check render("""
var x = toFloat(37)
p: round($x)
""") == "<p>37</p>"
    check render("""
var x = floor(toFloat(37))
p: $x
""") == "<p>37</p>"
    check render("""
var x = ceil(toFloat(32))
p: $x
""") == "<p>32</p>"

  test "math — sqrt":
    check render("""
var x = sqrt(toFloat(9))
p: $x
""") == "<p>3.0</p>"

  test "converters — toBool":
    check render("""p: toBool(1)""") == "<p>true</p>"
    check render("""p: toBool(0)""") == "<p>false</p>"
    check render("""p: toBool("true")""") == "<p>true</p>"
    check render("""p: toBool("false")""") == "<p>false</p>"

  test "converters — toInt / parseInt / toFloat":
    check render("""
var x = toFloat(37)
p: toInt($x)
""") == "<p>37</p>"
    check render("""p: parseInt("42")""") == "<p>42</p>"
    check render("""p: toFloat(5)""") == "<p>5.0</p>"

  test "converters — toString":
    check render("""
var x = 42
p: toString($x)
""") == "<p>42</p>"
    check render("""p: toString(true)""") == "<p>true</p>"

  test "converters — intVal / strVal":
    var data = newJObject()
    data["x"] = %* 42
    data["y"] = %* "hello"
    check render("""p: intVal($this["x"])""", data) == "<p>42</p>"
    check render("""p: strVal($this["y"])""", data) == "<p>hello</p>"

  test "escape / unescape":
    check render("""p: escape("<hello>")""") == "<p>&lt;hello&gt;</p>"
    check render("""p: unescape("&lt;hello&gt;")""") == "<p><hello></p>"

  test "len / high":
    check render("""p: len("hello")""") == "<p>5</p>"
    check render("""var arr = [1, 2, 3]; p: len($arr)""") == "<p>3</p>"

  test "hasKey":
    var data = newJObject()
    data["obj"] = %* {"name": "Alice"}
    check render("""p: hasKey($this["obj"], "name")""", data) == "<p>true</p>"
    check render("""p: hasKey($this["obj"], "age")""", data) == "<p>false</p>"

  test "parseJSON":
    check render("""p: jsonType(parseJSON("{\"a\":1}"))""") == "<p>object</p>"

suite "Stdlib — libstrings":
  test "contains / startsWith / endsWith":
    check render("""p: contains("hello world", "world")""") == "<p>true</p>"
    check render("""p: contains("hello world", "xyz")""") == "<p>false</p>"
    check render("""p: startsWith("hello", "he")""") == "<p>true</p>"
    check render("""p: startsWith("hello", "lo")""") == "<p>false</p>"
    check render("""p: endsWith("hello", "lo")""") == "<p>true</p>"

  test "toUpper / toLower":
    check render("""p: toUpper("hello")""") == "<p>HELLO</p>"
    check render("""p: toLower("HELLO")""") == "<p>hello</p>"

  test "strip":
    check render("""p: strip("  hello  ")""") == "<p>hello</p>"

  test "split":
    check render("""
var parts = split("a,b,c", ",")
p: len($parts)
""") == "<p>3</p>"

  test "replace":
    check render("""p: replace("hello world", "world", "tim")""") == "<p>hello tim</p>"

  test "repeat":
    check render("""p: repeat("ha", 3)""") == "<p>hahaha</p>"

  test "capitalize":
    check render("""p: capitalize("hello")""") == "<p>Hello</p>"

  test "count":
    check render("""p: count("hello", "l")""") == "<p>2</p>"

  test "isAlphaNumeric / isDigit":
    check render("""p: isAlphaNumeric("abc123")""") == "<p>true</p>"
    check render("""p: isAlphaNumeric("")""") == "<p>false</p>"
    check render("""p: isDigit("123")""") == "<p>true</p>"
    check render("""p: isDigit("12a3")""") == "<p>false</p>"

  test "base64":
    check render("""p: decode(encode("hello"))""") == "<p>hello</p>"

suite "Stdlib — libarrays":
  test "add / delete / insert":
    check render("""
var arr = [1, 2, 3]
add($arr, 4)
p: len($arr)
""") == "<p>4</p>"
    check render("""
var arr = [1, 2, 3]
delete($arr, 1)
p: len($arr)
""") == "<p>2</p>"
    check render("""
var arr = [1, 3]
insert($arr, 2, 1)
p: len($arr)
""") == "<p>3</p>"

  test "contains / find":
    check render("""
var arr = ["a", "b", "c"]
p: contains($arr, "b")
""") == "<p>true</p>"
    check render("""
var arr = ["a", "b", "c"]
p: find($arr, "c")
""") == "<p>2</p>"

  test "isEmpty":
    check render("""
var arr = [1]
p: isEmpty($arr)
""") == "<p>false</p>"

  test "first / last":
    check render("""
var arr = [10, 20, 30]
p: first($arr)
""") == "<p>10</p>"
    check render("""
var arr = [10, 20, 30]
p: last($arr)
""") == "<p>30</p>"

  test "reverse":
    check render("""
var arr = [1, 2, 3]
var rev = reverse($arr)
p: first($rev)
""") == "<p>3</p>"

  test "dedup":
    check render("""
var arr = [1, 2, 1, 3, 2]
dedup($arr)
p: len($arr)
""") == "<p>3</p>"

  test "join":
    check render("""
var arr = ["a", "b", "c"]
p: join($arr)
""") == "<p>a, b, c</p>"

suite "Stdlib — libjson":
  test "keys / values":
    var data = newJObject()
    data["obj"] = %* {"a": 1, "b": 2}
    let r = render("""p: keys($this["obj"])""", data)
    check r.find("a") >= 0
    check r.find("b") >= 0

  test "pretty":
    var data = newJObject()
    data["obj"] = %* {"a": 1}
    let r = render("""p: pretty($this["obj"])""", data)
    check r.find("a") >= 0

  test "get":
    var data = newJObject()
    data["obj"] = %* {"name": "Alice"}
    data["default"] = %* "fallback"
    let r = render("""p: get($this["obj"], "name", $this["default"])""", data)
    check r != ""

  test "join (json array)":
    var data = newJObject()
    data["items"] = %* ["a", "b", "c"]
    check render("""p: join($this["items"], "|")""", data) == "<p>a|b|c</p>"
