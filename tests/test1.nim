import std/[unittest, json], tim
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
    "products": [
        {
            "id": "8629976",
            "name": "Riverside 900, 10-Speed Hybrid Bike",
            "price": 799.00,
            "currency": "USD",
            "composition": "100% Aluminium 6061",
            "sizes": [
                {
                    "label": "S",
                    "stock": 31
                },
                {
                    "label": "M",
                    "stock": 94
                },
                {
                    "label": "L",
                    "stock": 86
                }
            ]
        },
        {
            "id": "8219006",
            "name": "Riverside 500, 7-Speed Hybrid Bike",
            "price": 599.00,
            "currency": "USD",
            "composition": "100% Aluminium 6061",
            "sizes": [
                {
                    "label": "S",
                    "stock": 31
                },
                {
                    "label": "M",
                    "stock": 94
                },
                {
                    "label": "L",
                    "stock": 86
                }
            ]
        }
    ],
    "objects": {
        "a" : {
            "b": "ok"
        }
    }
})

test "can init":
    assert Tim.hasAnySources == true
    assert Tim.getIndent == 2
    assert Tim.shouldMinify == false

test "can precompile":
    let timlFiles = Tim.precompile()
    assert timlFiles.len != 0

test "can render":
    echo Tim.render("index")
