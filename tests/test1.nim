import std/unittest
import ../src/tim

var t = newTim("./app/templates", "./app/storage",
    currentSourcePath(), minify = false, indent = 2)

test "precompile":
  t.precompile(flush = true, waitThread = false)

test "render index":
  echo t.render("index")