# High-performance, compiled template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim

import std/tables
import std/json

type 
    Interpreter* = object
        data: JsonNode

proc hasVar*[T: Interpreter](i: T, key: string): bool =
    ## Determine if current data contains given variable key
    result = i.data.hasKey(key)

proc getVar*[T: Interpreter](i: var T, key: string): JsonNode =
    ## Retrieve a variable from current data
    if i.hasVar(key):
        result = i.data[key]
    else:
        result = newJNull()

proc init*[T: typedesc[Interpreter]](newInterpreter: T, data: JsonNode): Interpreter =
    ## Initialize a Tim Interpreter
    var i = newInterpreter(data: data)
    result = i