import unittest, tim
from std/os import getCurrentDir

proc initTimEngine(): TimEngine =
    result = TimEngine.init(
        source = "../examples/templates",
        output = "../examples/storage/templates",
        minified = false,
        indent = 4
    )

test "can init":
    var engine = initTimEngine()
    check engine.getStoragePath.len != 0


test "can prevent duplicate attrs":
    echo "todo"
