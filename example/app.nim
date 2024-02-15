import ../src/tim
import std/os

var
  engine = newTim(
    src = "templates",
    output = "storage",
    basepath = currentSourcePath(),
    minify = true,
    indent = 2
  )

engine.precompile()
sleep(40)
let x = engine.render("index")
writeFile(getCurrentDir() / "example" / "preview.html", x)