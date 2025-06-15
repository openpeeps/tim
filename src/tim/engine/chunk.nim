# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://tim-engine.com

import std/[tables]

import value

type
  Opcode* = enum ## An opcode, used for execution.

    opcNoop = "noop"

    # stack
    opcPushTrue = "pushTrue"
    opcPushFalse = "pushFalse"
    opcPushNil = "pushNil"
    opcPushI = "pushI"            ## push int
    opcPushF = "pushF"            ## push float
    opcPushS = "pushS"            ## push string
    opcPushG = "pushG"            ## push global
    opcPopG = "popG"              ## pop global
    opcPushL = "pushL"            ## push local
    opcPopL = "popL"              ## pop local
    
    opcConstrObj = "constrObj"    ## construct object

    opcGetF = "getF"              ## push field
    opcSetF = "setF"              ## pop field
    opcConstrArray = "constrArray"  ## construct array
    opcGetI = "getI"                ## get array item
    opcDiscard = "discard"        ## discard values

    # json operations
    opcGetJ = "getJ"              ## get JSON value
    opcSetJ = "setJ"              ## set JSON value

    # arithmetic operations
    opcNegI = "negI"              ## negate int
    opcAddI = "addI"              ## add ints
    opcSubI = "subI"              ## subtract ints
    opcMultI = "multI"            ## multiply ints
    opcDivI = "divI"              ## divide ints
    opcNegF = "negF"              ## negate float
    opcAddF = "addF"              ## add floats
    opcSubF = "subF"              ## subtract floats
    opcMultF = "multF"            ## multiply floats
    opcDivF = "divF"              ## divide floats

    # logic operations
    opcInvB = "invB"              ## invert bool

    # relational operations
    opcEqB = "eqB"                ## equal bools
    opcEqI = "eqI"                ## equal ints
    opcLessI = "lessI"            ## int less than
    opcGreaterI = "greaterI"      ## int greater than
    opcEqF = "eqF"                ## equal floats
    opcLessF = "lessF"            ## float less than
    opcGreaterF = "greaterF"      ## float greater than

    # execution
    opcJumpFwd = "jumpFwd"        ## jump forward
    opcJumpFwdT = "jumpFwdT"      ## jump forward if true
    opcJumpFwdF = "jumpFwdF"      ## jump forward if false
    opcJumpBack = "jumpBack"      ## jump backward
    opcCallD = "callD"            ## call direct
    opcCallI = "callI"            ## call indirect
    opcReturnVal = "returnVal"    ## return value from proc
    opcReturnVoid = "returnVoid"  ## return void from proc
    # opcEchoCode = "echoCode"        ## echo code to stdout
    
    opcBeginHtml = "beginHtml"    ## construct HTML object
    opcBeginHtmlWithAttrs = "behinHtmlWithAttrs" ## construct HTML object with attributes
    opcAttrEnd = "attrEnd"        ## ends HTML object
    opcInnerHtml = "innerHtml"        ## ends HTML object
    opcTextHtml = "textHtml"      ## adds text to HTML object
    opcCloseHtml = "closeHtml"    ## closes HTML object

    opcAttrClass = "attrClass"    ## adds class to HTML object
    opcAttrId = "attrId"          ## adds id to HTML object
    opcAttr = "attr"
    opcWSpace = "space"           ## adds whitespace to HTML result

    opcImportModule = "importModule"  ## import a module
    opcImportModuleAlias = "importModuleAlias"  ## import a module with an alias
    opcImportFromModule = "importFromModule"  ## import a symbol from a module

    opcHalt = "halt"              ## halt the VM

  Script* = ref object
    stdpos*: int
    procs*: seq[Proc]
      ## all procs declared in this script
    procsExport*: seq[Proc]
      ## the public procs declared in this script
      ## these are the procs that can be called from
      ## other scripts
    mainChunk*: Chunk  ## the main chunk of this script
    scripts*: Table[string, Script]
      ## a table of scripts, basically reprresenting the
      ## modules the script imports
    jsOutput*: string
    typeCount*: int    ## the number of types in this script.
                       ## used for compilation

  LineInfo* = tuple
    ## Line information.
    file: string  # very inefficient! it would probably be wiser to use
                  # an int ID for this
    ln, col: int
    runLength: int

  Chunk* = ref object
    ## A chunk of bytecode.
    file*: string            ## the filename of the module this chunk belongs to
    code*: seq[uint8]        ## the raw bytecode
    ln*, col*: int           ## the current line info, used when emitting \
                             ## bytecode
    lineInfo: seq[LineInfo]  ## a list of run-length encoded line info
    strings*: seq[string]    ## seq of strings used in this chunk

  ProcKind* = enum
    pkNative   ## a native (bytecode) proc
    pkForeign  ## a foreign (Nim) proc

  Proc* = ref object
    ## A runtime procedure.
    name*: string
    case kind*: ProcKind
    of pkNative:
      chunk*: Chunk          ## the chunk of bytecode of this procedure
    of pkForeign:
      foreign*: ForeignProc  ## the foreign implementation of this procedure
    paramCount*: int         ## the number of parameters this procedure takes
    hasResult*: bool         ## flag signifying whether the proc returns a value

proc addLineInfo*(chunk: var Chunk, n: int) =
  ## Add ``n`` line info entries to the chunk.

  if chunk.lineInfo.len > 0:
    if chunk.lineInfo[^1].ln == chunk.ln and
       chunk.lineInfo[^1].col == chunk.col:
      inc(chunk.lineInfo[^1].runLength, n)
      return
  chunk.lineInfo.add((chunk.file, chunk.ln, chunk.col, n))

proc getString*(chunk: var Chunk, str: string): uint16 =
  ## Get a string ID from a chunk, adding it to the chunk's string list if it
  ## isn't already stored.
  # TODO: this is an `O(n)` operation, depending on the number of strings
  # already stored in the chunk. optimize this
  if str notin chunk.strings:
    result = chunk.strings.len.uint16
    chunk.strings.add(str)
  else:
    result = chunk.strings.find(str).uint16
  # result = chunk.strings.len.uint16
  # chunk.strings.add(str)

proc emit*(chunk: var Chunk, opc: Opcode) =
  ## Emit an opcode. This ignores noop opcodes.
  if opc != opcNoop:
    chunk.addLineInfo(1)
    chunk.code.add(opc.uint8)

proc emit*(chunk: var Chunk, u8: uint8) =
  ## Emit a `uint8`.
  chunk.addLineInfo(sizeof(uint8))
  chunk.code.add(u8)

proc emit*(chunk: var Chunk, u16: uint16) =
  ## Emit a `uint16`.
  chunk.addLineInfo(sizeof(uint16))
  chunk.code.add(cast[array[sizeof(uint16), uint8]](u16))

proc emit*(chunk: var Chunk, val: int64) =
  ## Emit an `int`.
  chunk.addLineInfo(ValueSize)
  chunk.code.add(cast[array[sizeof(int64), uint8]](val))

proc emit*(chunk: var Chunk, val: float64) =
  ## Emit a `float`.
  chunk.addLineInfo(ValueSize)
  chunk.code.add(cast[array[sizeof(float64), uint8]](val))

proc emitHole*(chunk: var Chunk, size: int): int =
  ## Emit a hole, to be filled later by ``fillHole``.
  result = chunk.code.len
  chunk.addLineInfo(size)
  for i in 1..size:
    chunk.code.add(0x00)

proc fillHole*(chunk: var Chunk, hole: int, val: uint8) =
  ## Fill a hole with an 8-bit value.
  chunk.code[hole] = val

proc fillHole*(chunk: var Chunk, hole: int, val: uint16) =
  ## Fill a hole with a 16-bit value.
  chunk.code[hole] = uint8(val and 0x00ff)
  chunk.code[hole + 1] = uint8((val and 0xff00) shr 8)

proc patchHole*(chunk: var Chunk, hole: int) =
  ## Fill a 16-bit hole with the current chunk's length + 1.

  chunk.fillHole(hole, uint16(chunk.code.len - hole + 1))

proc getOpcode*(chunk: Chunk, i: int): Opcode =
  ## Get the opcode at position ``i``.
  result = chunk.code[i].Opcode

proc getU8*(chunk: Chunk, i: int): uint8 =
  ## Gets the ``uint8`` at position ``i``.
  result = chunk.code[i]

proc getU16*(chunk: Chunk, i: int): uint16 =
  ## Get the ``uint16`` at position ``i``.
  result = chunk.code[i].uint16 or chunk.code[i + 1].uint16 shl 8

proc getInt*(chunk: Chunk, i: int): int64 =
  ## Get a constant int at position ``i``.
  var
    bytes: array[sizeof(int64), uint8]
    raw = cast[ptr UncheckedArray[uint8]](chunk.code[i].unsafeAddr)
  for i in low(bytes)..high(bytes):
    bytes[i] = raw[i]
  result = cast[int64](bytes)

proc getFloat*(chunk: Chunk, i: int): float64 =
  ## Get a constant float at position ``i``.
  var
    bytes: array[sizeof(float64), uint8]
    raw = cast[ptr UncheckedArray[uint8]](chunk.code[i].unsafeAddr)
  for i in low(bytes)..high(bytes):
    bytes[i] = raw[i]
  result = cast[float64](bytes)

proc getLineInfo*(chunk: Chunk, i: int): LineInfo =
  ## Get the line info at position ``i``. **Warning:** This is very slow,
  ## because it has to walk the entire chunk decoding the run length encoded
  ## line info!
  var n = 0
  for li in chunk.lineInfo:
    for r in 1..li.runLength:
      if n == i:
        return li
      inc(n)

proc newChunk*(): Chunk =
  ## Create a new chunk.
  result = Chunk(ln: 1, col: 0)

proc newScript*(main: Chunk): Script =
  ## Create a new script, with the given main chunk.
  result = Script(mainChunk: main)

