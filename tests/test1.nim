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