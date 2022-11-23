# High-performance, compiled template engine inspired by Emmet syntax.
# 
# MIT License
# Copyright (c) 2022 George Lemon from OpenPeep
# https://github.com/openpeep/tim

import std/tables
import std/json
import std/macros

type 
    Data* = object
        data: JsonNode

macro `?`*(a: bool, body: untyped): untyped =
    let b = body[1]
    let c = body[2]
    result = quote:
        if `a`: `b` else: `c`

macro isEqualBool*(a, b: bool): untyped =
    result = quote:
        `a` == `b`

macro isNotEqualBool*(a, b: bool): untyped =
    result = quote:
        `a` != `b`

macro isEqualInt*(a, b: int): untyped =
    result = quote:
        `a` == `b`

macro isNotEqualInt*(a, b: int): untyped =
    result = quote:
        `a` != `b`

macro isGreaterInt*(a, b: int): untyped =
    result = quote:
        `a` > `b`

macro isGreaterEqualInt*(a, b: int): untyped =
    result = quote:
        `a` >= `b`

macro isLessInt*(a, b: int): untyped =
    result = quote:
        `a` < `b`

macro isLessEqualInt*(a, b: int): untyped =
    result = quote:
        `a` <= `b`

macro isEqualFloat*(a, b: float64): untyped =
    result = quote:
        `a` == `b`

macro isNotEqualFloat*(a, b: float64): untyped =
    result = quote:
        `a` != `b`

macro isEqualString*(a, b: string): untyped =
    result = quote:
        `a` == `b`

macro isNotEqualString*(a, b: string): untyped =
    result = quote:
        `a` != `b`

proc hasVar*[T: Data](i: T, key: string): bool =
    ## Determine if current data contains given variable key
    result = i.data.hasKey(key)

proc getVar*[T: Data](i: var T, key: string): JsonNode =
    ## Retrieve a variable from current data
    if i.hasVar(key): result = i.data[key]
    else: result = newJNull()

proc evaluate*[T: Data](i: var T) =
    ## Procedure for evulating conditional statements, data assignment,
    ## iteration statements and other dynamic things.

proc init*[T: typedesc[Data]](newData: T, data: JsonNode): Data =
    ## Initialize a Tim Data instance
    var i = newData(data: data)
    result = i