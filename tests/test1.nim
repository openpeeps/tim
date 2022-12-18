import std/[unittest, json], tim
from std/os import getCurrentDir, dirExists

Tim.init(
    source = "../examples/templates",
    output = "../examples/storage/templates",
    minified = false,
    indent = 4
)

Tim.setData(%*{
    "appName": "My application",
    "production": false,
    "keywords": ["template-engine", "html", "tim", "compiled", "templating"]
})

test "can init":
    assert dirExists("../examples/templates") == true
    assert Tim.hasAnySources == true
    assert Tim.getIndent == 4
    assert Tim.shouldMinify == false

# test "can precompile":
#     let timlFiles = Tim.precompile()
#     assert timlFiles.len != 0

# test "can render":
#     echo Tim.render("index")
