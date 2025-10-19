# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[strutils, tables, critbits, algorithm,
            json, options, hashes, dynlib]

import ./chunk, ./value
import pkg/libffi

type
  VMPreferences* = object
    enableHotCodeDetection*: bool
    enableHotProcDetection*: bool
    hotProcThreshold*: int = 10
    hotChunkThreshold*: int = 100

  ArgKind = enum akNone, akInt, akFloat, akString

  CachedOps = ref object
    opcodes: seq[Opcode]
    arg1: seq[int64]          ## raw storage; interpretation depends on flags
    arg2: seq[int64]
    flags: seq[int16]         ## bit-packed arg kinds
    byteOffsets: seq[int]
    jumpTargets: seq[int]     ## -1 if not a jump

  Vm* {.acyclic.} = ref object
    lvl: int
    globals*: CritBitTree[Value]
    cache: Table[string, Value]
    opCache: Table[Hash, CachedOps]
    hotCounts: Table[Chunk, int]
    hotProcCounts: Table[Proc, int]
    preferences: VMPreferences

  CallFrame = tuple
    chunk: Chunk
    pcIdx: int
    stackBottom: int
    script: Script

  Operation* = object
    opcode: Opcode
    args: seq[Value]      ## decoded arguments
    byteOffset: int       ## original byte offset (opcode position in raw chunk)

const
  VMInitialPreallocatedStackSize* {.intdefine.} = 16
  VMPreallocatedStackSize* {.intdefine.} = 4

proc newVm*(): Vm =
  result = Vm()

proc `{}`[T](x: seq[T], i: int): ptr UncheckedArray[T] =
  result = cast[ptr UncheckedArray[T]](x[i].unsafeAddr)

proc `{}`[T](x: seq[T], i: BackwardsIndex): ptr UncheckedArray[T] =
  result = x{x.len - i.int}

proc read[T](code: ptr UncheckedArray[uint8], offset: int): T =
  result = cast[ptr T](code[offset].unsafeAddr)[]

proc push(stack: var Stack, val: Value) =
  if stack.len < stack.capacity:
    stack.setLen(stack.len + 1)
    stack[stack.len - 1] = val
  else:
    stack.add(val)
  when defined(hayaVmWriteStackOps):
    echo "push ", stack

proc pop(stack: var Stack): Value =
  result = stack[^1]
  stack.setLen(stack.len - 1)
  when defined(hayaVmWriteStackOps):
    echo "pop  ", stack

proc peek(stack: Stack): Value =
  result = stack[^1]

template inc[T](p: ptr UncheckedArray[T], offset = 1) =
  p = cast[ptr UncheckedArray[T]](cast[int](p) + offset)

template dec[T](p: ptr UncheckedArray[T], offset = 1) =
  p = cast[ptr UncheckedArray[T]](cast[int](p) - offset)

# Bit helpers
template packFlags(a1, a2: ArgKind): int16 =
  (ord(a1) or (ord(a2) shl 2)).int16

template arg1Kind(f: int16): ArgKind = ArgKind((f and 0b11).int)
template arg2Kind(f: int16): ArgKind = ArgKind(((f shr 2) and 0b11).int)


#
# Forward declarations
#
proc parseChunk(chunk: Chunk): CachedOps

#
# Caching
#
proc cacheSet*(vm: Vm, key: string, value: Value) =
  vm.cache[key] = value

proc cacheGet*(vm: Vm, key: string): Option[Value] =
  if key in vm.cache: some(vm.cache[key]) else: none(Value)

proc computeForwardTarget(op: Operation, dist: int): int =
  ## Returns target raw byte offset (old encoding)
  ## operandStart = op.byteOffset + 1 (opcode) + 2 (uint16 operand) - we used (dist -1)
  let operandStart = op.byteOffset + 1
  let targetByte = operandStart + (dist - 1)
  targetByte

proc computeBackwardTarget(op: Operation, dist: int): int =
  ## targetByte = op.byteOffset - dist  (old encoding derived)
  op.byteOffset - dist

proc ffiTypeFor(typeId: TypeId): ptr Type =
  # FFI helpers
  case typeId
  of tyBool, tyInt: addr type_sint64
  of tyFloat: addr type_double
  of tyString: addr type_pointer
  of tyPointer: addr type_pointer
  else: addr type_void

# Hot code markers (stubs)
proc markHot(vm: Vm, chunk: Chunk) = discard
proc markHotProc(vm: Vm, theProc: Proc) = discard

proc parseChunk(chunk: Chunk): CachedOps =
  # Parsing raw bytecode into operations
  var pc = chunk.code{0}
  let base = cast[int](pc)
  let codeLen = chunk.code.len

  proc readArg[T](pc: var ptr UncheckedArray[uint8]): T =
    # reads an argument of type T and advances the pointer
    result = pc.read[:T](0); inc(pc, sizeof(T))

  proc seekArg[T](pc: var ptr UncheckedArray[uint8]): T =
    # reads an argument of type T without advancing the pointer
    result = pc.read[:T](0)

  var
    opcodes: seq[Opcode]
    arg1: seq[int64]
    arg2: seq[int64]
    flags: seq[int16]
    byteOffsets: seq[int]
    jumpTargets: seq[int]

  template addOp(oc: Opcode, a1: int64 = 0'i64, a2: int64 = 0'i64,
                 k1: ArgKind = akNone, k2: ArgKind = akNone) =
    opcodes.add(oc)
    arg1.add(a1)
    arg2.add(a2)
    flags.add(packFlags(k1, k2))
    byteOffsets.add(opByteOffset)
    jumpTargets.add(-1)

  while cast[int](pc) - base < codeLen:
    let opByteOffset = cast[int](pc) - base
    let oc = Opcode(pc[0])
    inc(pc)
    case oc
    of opcPushNil:
      let id = readArg[uint16](pc) # object id
      addOp(oc, id.int64, 0, akInt)
    of opcPushI:
      let v = readArg[int](pc)
      addOp(oc, v.int64, 0, akInt)
    of opcPushF:
      let v = readArg[float64](pc)
      addOp(oc, cast[int64](v), 0, akFloat)
    of opcPushS:
      let sid = readArg[uint16](pc)
      addOp(oc, sid.int64, 0, akString)
    of opcPushPointer:
      discard readArg[pointer](pc)
      addOp(oc)
    of opcPushTrue, opcPushFalse:
      addOp(oc)
    of opcPushG, opcPopG:
      let sid = readArg[uint16](pc)
      addOp(oc, sid.int64, 0, akString)
    of opcPushL, opcPopL:
      let idx = readArg[uint8](pc).int
      addOp(oc, idx.int64, 0, akInt)
    of opcJumpFwd, opcJumpFwdT, opcJumpFwdF, opcJumpBack:
      let dist = readArg[uint16](pc).int
      addOp(oc, dist.int64, 0, akInt)
    of opcCallD:
      let pid = readArg[uint16](pc).int
      addOp(oc, pid.int64, 0, akInt)
    of opcAttrClass, opcAttrId, opcBeginHtmlWithAttrs, opcBeginHtml, opcCloseHtml:
      let sid = readArg[uint16](pc)
      addOp(oc, sid.int64, 0, akString)
    of opcConstrArray, opcConstrObj:
      let cnt = readArg[uint16](pc).int
      addOp(oc, cnt.int64, 0, akInt)
    of opcDiscard:
      let n = readArg[uint8](pc).int
      addOp(oc, n.int64, 0, akInt)
    of opcGetF, opcSetF:
      let f = readArg[uint8](pc).int
      addOp(oc, f.int64, 0, akInt)
    of opcFFIGetProc:
      let sid = readArg[uint16](pc)
      let argc = readArg[uint8](pc).int
      addOp(oc, sid.int64, argc.int64, akString, akInt)
    of opcImportModule:
      let sid = readArg[uint16](pc)
      addOp(oc, sid.int64, 0, akString)
    else:
      addOp(oc)

  # Precompute jump targets
  var byteToOp: Table[int,int]
  for i, b in byteOffsets: byteToOp[b] = i
  for i, oc in opcodes:
    case oc
    of opcJumpFwd, opcJumpFwdT, opcJumpFwdF:
      let dist = arg1[i].int
      # forward target (old encoding)
      let operandStart = byteOffsets[i] + 1
      let targetByte = operandStart + (dist - 1)
      if targetByte in byteToOp: jumpTargets[i] = byteToOp[targetByte]
    of opcJumpBack:
      let dist = arg1[i].int
      let targetByte = byteOffsets[i] - dist
      if targetByte in byteToOp: jumpTargets[i] = byteToOp[targetByte]
    else: discard

  result = CachedOps(
    opcodes: opcodes,
    arg1: arg1,
    arg2: arg2,
    flags: flags,
    byteOffsets: byteOffsets,
    jumpTargets: jumpTargets
  )

#
# Cache layer uses new parse
#
proc getCachedOps(vm: Vm, chunk: Chunk): CachedOps =
  # let key = cast[pointer](chunk)
  let hashed = hash(chunk)
  if vm.opCache.contains(hashed):
    return vm.opCache[hashed] # already cached
  result = parseChunk(chunk)
  vm.opCache[hashed] = result

#
# Decoders
#
template getArg1Int(co: CachedOps, i: int): int =
  co.arg1[i].int

template getArg1Float(co: CachedOps, i: int): float64 =
  cast[float64](co.arg1[i])

template getArg1Str(co: CachedOps, i: int, chunk: Chunk): string =
  let id = co.arg1[i].uint16
  chunk.strings[id]

template pushConst(co: CachedOps, i: int, chunk: Chunk, stack: var Stack) =
  let k = co.flags[i].arg1Kind
  case k
  of akInt:
    stack.push(initValue(co.getArg1Int(i)))
  of akFloat:
    stack.push(initValue(co.getArg1Float(i)))
  of akString:
    stack.push(initValue(co.getArg1Str(i, chunk)))
  else:
    discard

proc interpret*(vm: Vm, script: Script, startChunk: Chunk,
        staticString: Option[string] = none(string),
        localData = newJObject()): string =
  ## Interpret the given chunk in the context
  ## of the given script.

  var
    stack: Stack = newSeqOfCap[Value](VMInitialPreallocatedStackSize)
    callStack: seq[CallFrame]
    script = script
    chunk  = startChunk

    cached = vm.getCachedOps(chunk)
    co = cached           # alias
    opcodes = co.opcodes

    pcIdx  = 0 # program counter (index into ops)
    stackBottom = 0 # index of first local variable in stack
    frameChanged = false # true if we switched frames

  # Inject localData as $this in globals
  vm.globals["this"] = initValue(localData)

  template unary(expr) =
    let a {.inject.} = stack.pop()
    stack.push(initValue(expr))

  template binary(someVal, op) =
    let b {.inject.} = stack.pop()
    let a {.inject.} = stack.pop()
    if a.typeId == tyInt and b.typeId == tyInt:
      stack.push(initValue(op(a.someVal, b.someVal)))
    elif a.typeId == tyFloat and b.typeId == tyFloat:
      stack.push(initValue(op(a.someVal, b.someVal)))
    elif a.typeId == tyInt and b.typeId == tyFloat:
      stack.push(initValue(op(toFloat(a.intVal), b.floatVal)))
    elif a.typeId == tyFloat and b.typeId == tyInt:
      stack.push(initValue(op(a.floatVal, toFloat(b.intVal))))
    else:
      stack.push(initValue(op(a.someVal, b.someVal)))

  template binaryInplNumber(someVal, op) =
    let b {.inject.} = stack.pop()
    let a {.inject.} = stack.pop()
    if a.typeId == tyInt and b.typeId == tyFloat:
      stack.push(initValue(`op`(toFloat(a.intVal), b.floatVal)))
    elif a.typeId == tyFloat and b.typeId == tyInt:
      stack.push(initValue(`op`(a.floatVal, toFloat(b.intVal))))
    else:
      stack.push(initValue(`op`(a.someVal, b.someVal)))

  template reloadChunk(newChunk: Chunk, newScript: Script) =
    chunk = newChunk
    script = newScript
    cached = vm.getCachedOps(chunk)
    # ops = cached.ops
    jumpTargets = cached.jumpTargets
    pcIdx = 0
    frameChanged = true

  template storeFrame() =
    callStack.add(
      (
        chunk: chunk,
        pcIdx: pcIdx,
        stackBottom: stackBottom,
        script: script
      )
    )

  template restoreFrame() =
    stack.setLen(stackBottom)
    let frame = callStack.pop()
    chunk = frame.chunk
    script = frame.script
    cached = vm.getCachedOps(chunk)
    pcIdx = frame.pcIdx
    stackBottom = frame.stackBottom

  template switchTo(newChunk: Chunk, newScript: Script) =
    reloadChunk(newChunk, newScript)

  template doCall(theProc: Proc) =
    vm.hotProcCounts.withValue(theProc, counter) do:
      inc counter[]
      if counter[] == vm.preferences.hotProcThreshold:
        vm.markHotProc(theProc)
    do:
      vm.hotProcCounts[theProc] = 1
    storeFrame()
    stackBottom = stack.len - theProc.paramCount
    case theProc.kind
    of pkNative:
      switchTo(theProc.chunk, script)
    of pkForeign:
      let callResult =
        (if theProc.paramCount > 0: theProc.foreign(stack{^theProc.paramCount})
         else: theProc.foreign(nil))
      restoreFrame()
      if theProc.hasResult: stack.push(callResult)

  proc ensureLocal(idx: int) =
    let needed = stackBottom + idx
    while stack.len <= needed:
      stack.push(initValue(0)) # placeholder

  while true:
    frameChanged = false
    if pcIdx < 0 or pcIdx >= co.opcodes.len:
      break
    let oc = co.opcodes[pcIdx]
    case oc
    # Constants / simple pushes
    of opcPushNil:
      # arg1 = object id (if you used it); produce a nil object placeholder
      stack.push(initObject(co.getArg1Int(pcIdx).uint16, nilObject))
    of opcPushI, opcPushF, opcPushS:
      co.pushConst(pcIdx, chunk, stack)
    of opcPushTrue:
      stack.push(initValue(true))
    of opcPushFalse:
      stack.push(initValue(false))
    of opcPushPointer:
      discard         # pointer literal already embedded (ignored here)
    of opcPopPointer:
      if stack.len > 0:
        discard stack.pop()
    of opcFFIGetProc:
      # FFI dynamic call: arg1= symbol string index, arg2 = argc
      let symbolName = co.getArg1Str(pcIdx, chunk)
      let argsCount  = co.arg2[pcIdx].int

      var tArgs: seq[Value]
      for _ in 0..<argsCount:
        tArgs.add(stack.pop())
      tArgs.reverse()

      if stack.len == 0:
        raise newException(ValueError, "FFI: missing library handle on stack")
      let libHandleVal = stack.pop()
      let libHandle = libHandleVal.objectVal.data
      if libHandle.isNil:
        raise newException(ValueError, "FFI: library handle is nil")

      let fnPtr = symAddr(libHandle, symbolName)
      if fnPtr.isNil:
        raise newException(ValueError, "FFI: symbol not found: " & symbolName)

      const MaxArgs = 32
      if argsCount > MaxArgs:
        raise newException(ValueError, "FFI: too many args (max " & $MaxArgs & ")")

      var
        intVals: array[MaxArgs, int64]
        floatVals: array[MaxArgs, float64]
        boolVals: array[MaxArgs, bool]
        strVals: array[MaxArgs, cstring]

      let paramsMem = alloc(sizeof(ptr Type) * argsCount)
      let argsMem   = alloc(sizeof(pointer) * argsCount)
      
      if paramsMem.isNil or argsMem.isNil:
        raise newException(ValueError, "FFI: allocation failed")

      var params = cast[ParamList](paramsMem)
      var aargs  = cast[ArgList](argsMem)

      try:
        for i in 0..<argsCount:
          let arg = tArgs[i]
          params[i] = ffiTypeFor(arg.typeId)
          case arg.typeId
          of tyString:
            strVals[i] = cstring(arg.stringVal[])
            aargs[i] = addr strVals[i]
          of tyInt:
            intVals[i] = arg.intVal
            aargs[i] = addr intVals[i]
          of tyFloat:
            floatVals[i] = arg.floatVal
            aargs[i] = addr floatVals[i]
          of tyBool:
            boolVals[i] = arg.boolVal
            aargs[i] = addr boolVals[i]
          else:
            aargs[i] = nil

        var cif: TCif
        if prep_cif(cif, DEFAULT_ABI, cuint(argsCount), addr type_pointer, params) != OK:
          raise newException(ValueError, "FFI: prep_cif failed")

        var res: pointer
        call(cif, fnPtr, addr res, aargs)
        if res != nil:
          let cstr = cast[cstring](res)
          if cstr != nil:
            result.add($cstr)
            stack.push(initValue($cstr))
          else:
            stack.push(initValue(res, symbolName))
        else:
            stack.push(initValue(res, symbolName))
      finally:
        dealloc(paramsMem)
        dealloc(argsMem)

    # Variables
    of opcPushG:
      stack.push(vm.globals[co.getArg1Str(pcIdx, chunk)])
    of opcPopG:
      vm.globals[co.getArg1Str(pcIdx, chunk)] = stack.pop()
    of opcPushL:
      let idx = co.getArg1Int(pcIdx)
      ensureLocal(idx)
      stack.push(stack[stackBottom + idx])
    of opcPopL:
      let idx = co.getArg1Int(pcIdx)
      ensureLocal(idx)
      stack[stackBottom + idx] = stack.pop()

    # HTML generation
    of opcAttrClass:
      result.add("class=\"" & co.getArg1Str(pcIdx, chunk) & "\"")
    of opcAttrId:
      result.add("id=\"" & co.getArg1Str(pcIdx, chunk) & "\"")
    of opcWSpace:
      result.add(" ")
    of opcAttrEnd:
      result.add(">")

    of opcAttr:
      # Add attribute key="value"
      result.add(stack.pop().stringVal[] & "=\"")
      let value = stack.pop()
      case value.typeId
      of tyString: result.add(value.stringVal[])
      of tyInt:    result.add($value.intVal)
      of tyFloat:  result.add($value.floatVal)
      of tyBool:   result.add($(value.boolVal))
      of tyJsonStorage:
        result.add(value.jsonVal.toString())
      else: discard
      result.add("\"")
    
    of opcAttrKey:
      # Add attribute key without `=value`
      let attr = stack.pop()
      if attr.stringVal[].len > 0:
        result.add(" ") # leading space
        result.add(attr.stringVal[])
    
    of opcBeginHtmlWithAttrs:
      # Start HTML tag with attributes
      result.add("<" & co.getArg1Str(pcIdx, chunk))
    
    of opcBeginHtml:
      # Start HTML tag
      result.add("<" & co.getArg1Str(pcIdx, chunk) & ">")
    
    of opcTextHtml:
      # Add text content
      let v = stack.pop()
      case v.typeId
      of tyString: result.add(v.stringVal[])
      of tyInt: result.add($v.intVal)
      of tyFloat: result.add($v.floatVal)
      of tyBool: result.add($(v.boolVal))
      of tyJsonStorage: result.add(v.jsonVal.toString())
      else: discard
    of opcInnerHtml:
      discard
    of opcCloseHtml:
      result.add("</" & co.getArg1Str(pcIdx, chunk) & ">")
    # Arrays / Objects
    of opcConstrArray:
      let count = co.getArg1Int(pcIdx)
      var arr = initArray(count)
      if count > 0:
        let vals = stack{^count}
        for i in 0..<count:
          arr.objectVal.fields[i] = vals[i]
        stack.setLen(stack.len - count)
      stack.push(arr)
    
    of opcGetI:
      # Expects array then index on stack
      let idxVal = stack.pop()
      let arr = stack.pop()
      stack.push(arr.objectVal.fields[idxVal.intVal])
    
    of opcSetI:
      # Set array element
      let
        val = stack.pop()
        idxVal = stack.pop()
        arr = stack.pop()
      arr.objectVal.fields[idxVal.intVal] = val
    
    of opcConstrObj:
      # Construct object with N fields (all from stack)
      let count = co.getArg1Int(pcIdx)
      var obj = initObject(14, count)
      if count > 0:
        let vals = stack{^count}
        for i in 0..<count: obj.objectVal.fields[i] = vals[i]
        stack.setLen(stack.len - count)
      stack.push(obj)
    
    of opcGetF:
      # Get field value
      let fld = co.getArg1Int(pcIdx)
      let obj = stack.pop()
      stack.push(obj.objectVal.fields[fld])
    
    of opcSetF:
      # Set field value
      let
        fld = co.getArg1Int(pcIdx)
        val = stack.pop()
        obj = stack.pop()
      obj.objectVal.fields[fld] = val

    # JSON (placeholders)
    of opcGetJ:
      # get a value from a JSON object
      let
        key = stack.pop()
        obj = stack.pop()
      var jsonValue: JsonNode # the value to be pushed onto the stack
      case key.typeId
      of tyInt:
        jsonValue = obj.jsonVal[key.intVal]
      of tyString:
        jsonValue = obj.jsonVal[key.stringVal[]]
      else: discard
      # raise newException(ValueError, "Invalid key type for JSON object: " & $key.typeId)
      stack.push(initValue(jsonValue))
    of opcSetJ:
      discard # TODO
    # Discard
    of opcDiscard:
      let n = co.getArg1Int(pcIdx)
      if n > 0 and stack.len >= n:
        stack.setLen(stack.len - n)

    # Arithmetic
    of opcNegI:
      let a = stack.pop(); stack.push(initValue(-a.intVal))
    of opcAddI, opcSubI, opcMultI, opcDivI:
      let b = stack.pop()
      let a = stack.pop()
      case oc
      of opcAddI: stack.push(initValue(a.intVal + b.intVal))
      of opcSubI: stack.push(initValue(a.intVal - b.intVal))
      of opcMultI: stack.push(initValue(a.intVal * b.intVal))
      of opcDivI: stack.push(initValue(a.intVal div b.intVal))
      else: discard
    of opcNegF:
      let a = stack.pop(); stack.push(initValue(-a.floatVal))
    of opcAddF, opcSubF, opcMultF, opcDivF:
      let b = stack.pop()
      let a = stack.pop()
      let av = if a.typeId == tyInt: a.intVal.toFloat else: a.floatVal
      let bv = if b.typeId == tyInt: b.intVal.toFloat else: b.floatVal
      case oc
        of opcAddF: stack.push(initValue(av + bv))
        of opcSubF: stack.push(initValue(av - bv))
        of opcMultF: stack.push(initValue(av * bv))
        of opcDivF: stack.push(initValue(av / bv))
        else: discard
    # Logic
    of opcInvB:
      let a = stack.pop(); stack.push(initValue(not a.boolVal))

    # Relational
    of opcEqB:
      let b = stack.pop(); let a = stack.pop(); stack.push(initValue(a.boolVal == b.boolVal))
    of opcEqI:
      let b = stack.pop(); let a = stack.pop(); stack.push(initValue(a.intVal == b.intVal))
    of opcLessI:
      let b = stack.pop(); let a = stack.pop(); stack.push(initValue(a.intVal < b.intVal))
    of opcGreaterI:
      let b = stack.pop(); let a = stack.pop(); stack.push(initValue(a.intVal > b.intVal))
    of opcEqF, opcLessF, opcGreaterF:
      let b = stack.pop(); let a = stack.pop()
      let av = if a.typeId == tyInt: a.intVal.toFloat else: a.floatVal
      let bv = if b.typeId == tyInt: b.intVal.toFloat else: b.floatVal
      case oc
      of opcEqF: stack.push(initValue(av == bv))
      of opcLessF: stack.push(initValue(av < bv))
      of opcGreaterF: stack.push(initValue(av > bv))
      else: discard

    # Modules
    of opcImportModule:
      let moduleName = co.getArg1Str(pcIdx, chunk)
      let other = script.scripts[moduleName]
      let mainScript = script
      storeFrame()
      stackBottom = if stack.len == 0: 0 else: stack.len - 1
      mainScript.procs.add(other.procsExport)
      inc(vm.lvl)
      chunk = other.mainChunk
      script = other
      cached = vm.getCachedOps(chunk)
      co = cached
      pcIdx = 0
      continue
    of opcImportModuleAlias, opcImportFromModule:
      discard

    # Control Flow
    of opcJumpFwd:
      let tgt = co.jumpTargets[pcIdx]
      if tgt >= 0: pcIdx = tgt - 1
    of opcJumpFwdT:
      if stack.peek().boolVal:
        let tgt = co.jumpTargets[pcIdx]
        if tgt >= 0: pcIdx = tgt - 1
    of opcJumpFwdF:
      if not stack.peek().boolVal:
        let tgt = co.jumpTargets[pcIdx]
        if tgt >= 0: pcIdx = tgt - 1
    of opcJumpBack:
      let tgt = co.jumpTargets[pcIdx]
      if tgt >= 0: pcIdx = tgt - 1
    of opcCallD:
      let id = co.getArg1Int(pcIdx)
      let p = script.procs[id]
      storeFrame()
      stackBottom = stack.len - p.paramCount
      case p.kind
      of pkNative:
        chunk = p.chunk
        script = script
        cached = vm.getCachedOps(chunk)
        co = cached
        pcIdx = 0
        continue
      of pkForeign:
        let callResult =
          if p.paramCount > 0:
            p.foreign(stack{^p.paramCount})
          else: p.foreign(nil)
        # restore
        stack.setLen(stackBottom)
        let frame = callStack.pop()
        chunk = frame.chunk
        script = frame.script
        cached = vm.getCachedOps(chunk)
        co = cached
        pcIdx = frame.pcIdx
        stackBottom = frame.stackBottom
        if p.hasResult: stack.push(callResult)
    of opcReturnVal:
      let rv = stack.pop()
      stack.setLen(stackBottom)
      let frame = callStack.pop()
      chunk = frame.chunk
      script = frame.script
      cached = vm.getCachedOps(chunk)
      co = cached
      pcIdx = frame.pcIdx
      stackBottom = frame.stackBottom
      stack.push(rv)
    of opcReturnVoid:
      stack.setLen(stackBottom)
      let frame = callStack.pop()
      chunk = frame.chunk
      script = frame.script
      cached = vm.getCachedOps(chunk)
      co = cached
      pcIdx = frame.pcIdx
      stackBottom = frame.stackBottom
    of opcViewLoader:
      result.add(staticString.get())
    of opcHalt:
      if stack.len > 0:
        echo "Warning: stack not empty at halt, contains ", stack.len, " items."
        echo stack[^1].typeId
      stack.setLen(0)
      if vm.lvl == 0:
        break
      else:
        if callStack.len == 0: break
        let frame = callStack.pop()
        chunk = frame.chunk
        script = frame.script
        cached = vm.getCachedOps(chunk)
        co = cached
        pcIdx = frame.pcIdx
        stackBottom = frame.stackBottom
        dec(vm.lvl)
    else:
      discard
    inc(pcIdx)