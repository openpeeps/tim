# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://tim-engine.com

import std/[strutils, tables, critbits, json, options]
import ./chunk, ./value

type
  # CachedAttributes* = CritBitTree[string]
  #   ## A tree of cached html attributes
  #   ## such as class, id, etc.

  Vm* {.acyclic.} = ref object
    globals*: CritBitTree[Value]
      ## a critbit tree of global values
    lvl: int

  CallFrame = tuple
    chunk: Chunk
    pc: ptr UncheckedArray[uint8]
    stackBottom: int
    script: Script

proc newVm*(): Vm =
  ## Create a new VM.
  result = Vm()

proc `{}`[T](x: seq[T], i: int): ptr UncheckedArray[T] =
  ## Return an unsafe view into a seq.
  result = cast[ptr UncheckedArray[T]](x[i].unsafeAddr)

proc `{}`[T](x: seq[T], i: BackwardsIndex): ptr UncheckedArray[T] =
  result = x{x.len - i.int}

proc read[T](code: ptr UncheckedArray[uint8], offset: int): T =
  ## Read a value of type ``T`` at ``offset`` in ``code``.
  result = cast[ptr T](code[offset].unsafeAddr)[]

proc push(stack: var Stack, val: Value) =
  ## Pushes ``val`` onto the stack.
  stack.add(val)
  when defined(hayaVmWriteStackOps):
    echo "push ", stack

proc pop(stack: var Stack): Value =
  ## Pops a value off the stack.
  result = stack[^1]
  stack.setLen(stack.len - 1)
  when defined(hayaVmWriteStackOps):
    echo "pop  ", stack

proc peek(stack: Stack): Value =
  ## Peek the value at the top of the stack.
  result = stack[^1]

template inc[T](point: ptr UncheckedArray[T], offset = 1) =
  point = cast[ptr UncheckedArray[T]](cast[int](point) + offset)

template dec[T](point: ptr UncheckedArray[T], offset = 1) =
  point = cast[ptr UncheckedArray[T]](cast[int](point) - offset)

proc interpret*(vm: Vm, script: Script, startChunk: Chunk): string =
  ## Interpret a chunk of code.

  # VM state
  var
    stack: Stack
    callStack: seq[CallFrame]
    script = script
    chunk  = startChunk
    pc = chunk.code{0}
    stackBottom = 0

  template unary(expr) =
    let a {.inject.} = stack.pop()
    stack.push(initValue(expr))

  template binary(someVal, op) =
    let
      b {.inject.} = stack.pop()
      a {.inject.} = stack.pop()
    if a.typeId == tyInt and b.typeId == tyInt:
      stack.push(initValue(op(a.someVal, b.someVal)))
    elif a.typeId == tyFloat and b.typeId == tyFloat:
      stack.push(initValue(op(a.someVal, b.someVal)))
    elif a.typeId == tyInt and b.typeId == tyFloat:
      var aVal = toFloat(a.intVal)
      stack.push(initValue(op(aVal, b.floatVal)))
    elif a.typeId == tyFloat and b.typeId == tyInt:
      var bVal = toFloat(b.intVal)
      stack.push(initValue(op(a.floatVal, bVal)))
    else:
      stack.push(initValue(op(a.someVal, b.someVal)))

  template binaryInplNumber(someVal, op) =
    let
      b  {.inject.} = stack.pop()
      a  {.inject.} = stack.pop()
    if a.typeId == tyInt and b.typeId == tyFloat:
      var aVal = toFloat(a.intVal)
      stack.push(initValue(`op`(aVal, b.floatVal)))
    elif a.typeId == tyFloat and b.typeId == tyInt:
      var bVal = toFloat(b.intVal)
      stack.push(initValue(`op`(a.floatVal, bVal)))
    else:
      stack.push(initValue(`op`(a.someVal, b.someVal)))

  template binaryInpl(someVal, op) =
    let b = stack.pop()
    op(stack[^1].someVal, b.someVal)

  template storeFrame() =
    when defined(hayaVmWritePcFlow):
      echo indent("↳ Store frame", 0)
    callStack.add((chunk: chunk, pc: pc, stackBottom: stackBottom, script: script))

  template restoreFrame() =
    when defined(hayaVmWritePcFlow):
      echo indent("↱ Restore frame", 0)
    # discard locals from current frame
    stack.setLen(stackBottom)
    # restore the frame
    let frame = callStack.pop()
    chunk = frame.chunk
    pc = frame.pc
    stackBottom = frame.stackBottom
    script = frame.script

  template doCall(theProc: Proc) =
    when defined(hayaVmWritePcFlow):
      echo "entering function " & theProc.name
    storeFrame()
    stackBottom = stack.len - theProc.paramCount
    case theProc.kind
    of pkNative:
      chunk = theProc.chunk
      pc = chunk.code{0}
      when defined(hayaVmWritePcFlow):
        echo "native proc; pc is now ", toHex(relPc.BiggestInt, 8)
      # the frame is restored by the return(Void|Val) opcode in the proc
    of pkForeign:
      let callResult =
        if theProc.paramCount > 0:
          theProc.foreign(stack{^theProc.paramCount})
        else:
          theProc.foreign(nil)
      restoreFrame()
      if theProc.hasResult:
        stack.push(callResult)

  template doImport(theScript, otherScript: Script) =
    # import a module
    when defined(hayaVmWritePcFlow):
      echo "importing module"
    storeFrame()
    stackBottom = if stack.len == 0: 0 else: stack.len - 1
    chunk = otherScript.mainChunk
    pc = chunk.code{0}
    script = otherScript
    theScript.procs.add(script.procsExport)
    inc(vm.lvl)

  # interpret loop
  while true:
    {.computedGoto.}
    let opcode = pc[0].Opcode
    when defined(hayaVmWritePcFlow):
      template relPc: int = cast[int](pc) - cast[int](chunk.code{0})
      echo indent("| pc: " & toHex(relPc.BiggestInt, 8) & " - " & $opcode, 0)

    inc(pc)
    case opcode
    of opcNoop: discard

    #--
    # Stack
    #--

    # literals
    of opcPushTrue:
      stack.push(initValue(true))
    of opcPushFalse:
      stack.push(initValue(false))
    of opcPushNil:
      let id = pc.read[:uint16](0).TypeId
      if id == 11:
        stack.push(initValue(newJObject())) # or maybe it should init a JNull?
      else:
        stack.push(initObject(id, nilObject))
      inc(pc, sizeof(uint16))
    of opcPushI:  # push int
      let i = pc.read[:int](0)
      stack.push(initValue(i))
      inc(pc, sizeof(float))
    of opcPushF:  # push float
      let f = pc.read[:float64](0)
      stack.push(initValue(f))
      inc(pc, sizeof(float))
    of opcPushS: # push string
      let id = pc.read[:uint16](0)
      stack.push(initValue(chunk.strings[id]))
      inc(pc, sizeof(uint16))
    #
    # Variables
    #
    of opcPushG:  # push global
      let
        id = pc.read[:uint16](0)
        name = chunk.strings[id]
      stack.push(vm.globals[name])
      inc(pc, sizeof(uint16))
    of opcPopG:  # pop to global
      let
        id = pc.read[:uint16](0)
        name = chunk.strings[id]
      vm.globals[name] = stack.pop()
      inc(pc, sizeof(uint16))
    of opcPushL:  # push local
      stack.push(stack[stackBottom + pc[0].int])
      inc(pc, sizeof(uint8))
    of opcPopL:  # pop to local
      stack[stackBottom + pc[0].int] = stack.pop()
      inc(pc, sizeof(uint8))
    of opcAttrClass:
      let
        id = pc.read[:uint16](0)
        attrValue = chunk.strings[id]
      result.add("class=\"" & attrValue & "\"")
      inc(pc, sizeof(uint16))
    of opcAttrId:
      let
        id = pc.read[:uint16](0)
        attrValue = chunk.strings[id]
      result.add("id=\"" & attrValue & "\"")
      inc(pc, sizeof(uint16))
    of opcWSpace:  result.add(" ") # add whitespace
    of opcAttrEnd: result.add(">") # end of attributes
    of opcAttr:
      # let len = pc.read[:uint8](0).int
      result.add(stack.pop().stringVal[] & "=\"") # key
      let value = stack.pop()
      case value.typeId
      of tyString:
        result.add(value.stringVal[])
      of tyInt:
        result.add($value.intVal)
      of tyFloat:
        result.add($value.floatVal)
      of tyBool:
        result.add($(value.boolVal))
      else: discard # todo?
      result.add("\"")
      # inc(pc, sizeof(uint8))
    of opcAttrKey:
      # handle an attribute key without value
      # this is used for boolean attributes like `checked`
      # or `disabled`
      result.add(stack.pop().stringVal[]) # key
    of opcBeginHtmlWithAttrs:
      # render the HTML object
      let tag = chunk.strings[pc.read[:uint16](0)]
      result.add("<"& tag)
      inc(pc, sizeof(uint16))
    of opcBeginHtml:
      # render the HTML object
      let
        # id = pc.read[:uint16](0)
        # nodesCount = pc[sizeof(uint16)].int
        tag = chunk.strings[pc.read[:uint16](0)]
      result.add("<"& tag & ">")
      inc(pc, sizeof(uint16))
    
    of opcTextHtml:
      let val = stack.pop()
      case val.typeId
      of tyString:
        result.add(val.stringVal[])
      of tyInt:
        result.add($val.intVal)
      of tyFloat:
        result.add($val.floatVal)
      of tyBool:
        result.add($(val.boolVal))
      of tyJsonStorage:
        result.add(val.jsonVal.toString())
      else: discard # todo
    of opcInnerHtml:
      discard

    of opcCloseHtml:
      # handle the closing tag
      let tag = chunk.strings[pc.read[:uint16](0)]
      result.add("</"& tag & ">")
      inc(pc, sizeof(uint16))

    #
    # Objects
    #
    of opcConstrArray:
      # construct an array object
      let itemsCount = pc.read[:uint16](0).int
      var obj: Value = initArray(itemsCount)
      if itemsCount > 0:
        let items = stack{^itemsCount}
        for i in 0..<itemsCount:
          obj.objectVal.fields[i] = items[i]
        stack.setLen(stack.len - itemsCount)
      stack.push(obj)
      inc(pc, sizeof(uint16))
    of opcGetI:
      let
        index = stack.pop()
        obj = stack.pop()
      stack.push(obj.objectVal.fields[index.intVal])
      # inc(pc, sizeof(uint8))

    of opcConstrObj:
      # construct an object
      let fieldCount = pc.read[:uint16](0).int
      var obj: Value = initObject(14, fieldCount)
      if fieldCount > 0:
        let fields = stack{^fieldCount}
        for i in 0..<fieldCount:
          obj.objectVal.fields[i] = fields[i]
        stack.setLen(stack.len - fieldCount)
      stack.push(obj)
      inc(pc, sizeof(uint16))
    of opcGetF:  # push field
      let
        field = pc[0]
        obj = stack.pop()
      stack.push(obj.objectVal.fields[field])
      inc(pc, sizeof(uint8))
    of opcSetF:  # pop to field
      let
        field = pc[0]
        value = stack.pop()
        obj = stack.pop()
      obj.objectVal.fields[field] = value
      inc(pc, sizeof(uint8))

    #
    # JSON storage
    #
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
    of opcSetJ: discard # not implemented yet
    # other
    of opcDiscard:
      let n = pc[0].int
      if stack.len > 0:
        stack.setLen(stack.len - n)
      else:
        stack.setLen(0)
      inc(pc, sizeof(uint8))

    #--
    # Arithmetic
    #--

    of opcNegI:  # negate a int
      unary(-a.intVal)
    of opcAddI:  # add two ints
      binaryInplNumber(intVal, `+`)
    of opcSubI:  # subtract two ints
      binaryInplNumber(intVal, `-`)
    of opcMultI:  # multiply two ints
      binaryInplNumber(intVal, `*`)
    of opcDivI:  # divide two ints
      let
        b = stack.pop()
        a = stack.pop()
      stack.add(initValue(a.intVal div b.intVal))
    of opcNegF:  # negate a float
      unary(-a.floatVal)
    of opcAddF:  # add two floats
      binaryInplNumber(floatVal, `+`)
    of opcSubF:  # subtract two floats
      binaryInplNumber(floatVal, `-`)
    of opcMultF:  # multiply two floats
      binaryInplNumber(floatVal, `*`)
    of opcDivF:  # divide two floats
      binaryInplNumber(floatVal, `/`)

    #--
    # Logic
    #--

    of opcInvB:  # negate a bool
      unary(not a.boolVal)

    #--
    # Relational
    #--

    of opcEqB:  # bools equal
      binary(boolVal,`==`)
    of opcEqI:  # ints equal
      binary(intVal, `==`)
    of opcLessI:  # int less than a int
      binary(intVal, `<`)
    of opcGreaterI:  # int less than or equal to int
      binary(intVal, `>`)
    of opcEqF:  # floats equal
      binary(floatVal, `==`)
    of opcLessF:  # float less than a float
      binary(floatVal, `<`)
    of opcGreaterF:  # float less than or equal to float
      binary(floatVal, `>`)
    
    # --
    # Module Handling
    # --
    of opcImportModule: 
      let id = pc.read[:uint16](0)
      let moduleName = chunk.strings[id]
      let otherScript = script.scripts[moduleName]
      inc(pc, sizeof(uint16))
      let mainScript = script
      doImport(mainScript, otherScript)
    of opcImportModuleAlias: discard
    of opcImportFromModule: discard

    #--
    # Execution
    #--

    of opcJumpFwd: # jump forward
      let n = pc.read[:uint16](0).int
      # jump n - 1, because we already advanced 1 after reading the opcode
      inc(pc, n - 1)
    of opcJumpFwdT: # jump forward if true
      if stack.peek().boolVal:
        let n = pc.read[:uint16](0).int
        inc(pc, n - 1)
      else:
        inc(pc, sizeof(uint16))
    of opcJumpFwdF: # jump forward if false
      if not stack.peek().boolVal:
        let n = pc.read[:uint16](0).int
        inc(pc, n - 1)
      else:
        inc(pc, sizeof(uint16))
    of opcJumpBack: # jump back
      let n = pc.read[:uint16](0).int
      dec(pc, n + 1)
    of opcCallD: # direct call
      let id = pc.read[:uint16](0).int
      let theProc = script.procs[id]
      inc(pc, sizeof(uint16))
      doCall(theProc)
    of opcCallI: discard
    of opcReturnVal:
      let retVal = stack.pop()
      restoreFrame()
      stack.push(retVal)
    of opcReturnVoid:
      restoreFrame()
    of opcHalt:
      assert stack.len == 0,
        "stack was not completely emptied. remaining values: " & $stack
      if vm.lvl == 0:
        break # if we are at the top level, we can exit the VM
      else:
        # otherwise, we just restore the frame
        restoreFrame()
        dec(vm.lvl)