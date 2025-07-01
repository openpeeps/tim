# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://tim-engine.com

import std/[macros, options, os, hashes,
        sequtils, strutils, ropes, tables]

import ./[ast, chunk, errors, sym, value]

type
  ContextAllocator {.acyclic.} = ref object
    ## a context allocator. shared between codegen instances.
    occupied: seq[Context]

  FlowBlockKind = enum
    fbLoopOuter  # outer loop flow block, used by ``break``
    fbLoopIter   # iteration loop flow block, used by ``continue``

  FlowBlock {.acyclic.} = ref object
    kind: FlowBlockKind
    breaks: seq[int]
    bottomScope: int
    context: Context

  GenKind = enum
    gkToplevel
    gkProc
    gkBlockProc
    gkIterator
  
  # CachedChunks* = CritBitTree[string]
    ## A tree of cached html attributes
    ## such as class, id, etc.
  
  CodeGen* {.acyclic.} = object
    ## a code generator for a module or proc.
    includePath: Option[string]
      ## the base path for including partials
    script: Script              # the script all procs go into
    module: Module              # the global scope
    chunk: Chunk                # the chunk of code we're generating
    scopes: seq[Scope]          # local scopes
    flowBlocks: seq[FlowBlock]
    ctxAllocator: ContextAllocator
    context: Context
      # the codegen's scope context. this is used to achieve \
      # scope hygiene with iterators
    case kind: GenKind          # what this generator generates
    of gkToplevel: discard
    of gkProc, gkBlockProc:
      procReturnTy: Sym         # the proc's return type
    of gkIterator:
      iter: Sym                 # the symbol representing the iterator
      iterForBody: Node         # the for loop's body
      iterForVar: Node          # the for loop variable's name
      iterForCtx: Context       # the for loop's context
    counter: uint16

  TempParamDef* = tuple
    pName: string
    pKind: TypeKind
    pKindIdent: string
    # pImplVal: Value
    pImplSym: Sym
    isMut, isOpt: bool

proc error*(node: Node, msg: string) =
  ## Raise a compile error on the given node.
  raise (ref TimCompileError)(
          # file: node.file,
          ln: node.ln,
          col: node.col,
          msg: ErrorFmt % ["", $node.ln, $node.col, msg]
        )

import std/terminal
proc warn(node: Node, msg: string) =
  # Output a warning message on the given node.
  stdout.styledWriteLine(fgYellow, styleBright, "Warning ",
      resetStyle, fgDefault, ErrorFmt % ["", $node.ln, $node.col, msg])

proc allocCtx*(allocator: ContextAllocator): Context =
  ## Allocate a new context
  while result in allocator.occupied:
    result = Context(result.int + 1)
  allocator.occupied.add(result)

proc freeCtx*(allocator: ContextAllocator, ctx: Context) =
  ## Free a context
  let index = allocator.occupied.find(ctx)
  assert index != -1, "freeCtx called on a context more than one time"
  allocator.occupied.del(index)

proc initCodeGen*(script: Script, module: Module, chunk: Chunk,
        kind = gkToplevel, ctxAllocator: ContextAllocator = nil): CodeGen =
  result = CodeGen(script: script, module: module,
                    chunk: chunk, kind: kind)
  if ctxAllocator == nil:
    result.ctxAllocator = ContextAllocator()
    result.context = result.ctxAllocator.allocCtx()
  # else:
  #   result.ctxAllocator = ctxAllocator
  #   result.context = ctxAllocator.allocCtx()

proc clone(gen: CodeGen, kind: GenKind): CodeGen =
  ## Clone a code generator, using a different kind for the new one.
  result = CodeGen(script: gen.script, module: gen.module, chunk: gen.chunk,
                   scopes: gen.scopes, flowBlocks: gen.flowBlocks,
                   ctxAllocator: gen.ctxAllocator, context: gen.context,
                   kind: kind)

template genGuard(body) =
  ## Wraps ``body`` in a "guard" used for code generation. The guard sets the
  ## line information in the target chunk. This is a helper used by {.codegen.}.
  when declared(node):
    let
      oldFile = gen.chunk.file
      oldLn = gen.chunk.ln
      oldCol = gen.chunk.col
    # gen.chunk.file = node.file
    gen.chunk.ln = node.ln
    gen.chunk.col = node.col
  body
  when declared(node):
    gen.chunk.file = oldFile
    gen.chunk.ln = oldLn
    gen.chunk.col = oldCol

macro codegen(theProc: untyped): untyped =
  ## Wrap ``theProc``'s body in a call to ``genGuard``.
  theProc.params.insert(1,
    newIdentDefs(ident"gen", nnkVarTy.newTree(ident"CodeGen")))
  if theProc[6].kind != nnkEmpty:
    theProc[6] = newCall("genGuard", theProc[6])
  result = theProc

let callBuiltinEcho = ast.newCall(ast.newIdent"echo")

proc varCount(scope: Scope): int =
  ## Count the number of variables in a scope.
  for _, sym in scope.variables:
    if sym.kind in skVars:
      inc(result)
  # scope.variables.len

proc varCount(gen: CodeGen, bottom = 0): int =
  ## Count the number of variables in all of the codegen's scopes.
  for scope in gen.scopes[bottom..^1]:
    result += scope.varCount
    # result += scope.variables.len

proc currentScope(gen: CodeGen): Scope =
  ## Returns the current scope.
  result = gen.scopes[^1]

proc pushScope(gen: var CodeGen) =
  ## Push a new scope.
  gen.scopes.add(Scope(context: gen.context))

proc popScope(gen: var CodeGen) =
  ## Pop the top scope, discarding its variables.
  if gen.currentScope.varCount > 0:
    gen.chunk.emit(opcDiscard)
    gen.chunk.emit(gen.currentScope.varCount.uint8)
  discard gen.scopes.pop()

proc scope(gen: CodeGen, index: int): Scope =
  ## Gets the local scope at level ``index``.
  ## This treats -1 as the global scope.
  result =
    if index == -1: gen.module # returns the global scope
    else: gen.scopes[index] # returns the local scope at index

proc addSym(gen: var CodeGen, sym: Sym,
        lookupName: Node = nil, scopeOffset = 0) =
  ## Add a symbol to a scope. If ``name.len != 0``, ``$name`` is used as the
  ## symbol's lookup name instead of ``$sym.name``.
  let name: Node =
    if lookupName != nil: lookupName
    else: sym.name
  if gen.scopes.len > 0:
    # local sym
    if not gen.scope(gen.scopes.high - scopeOffset).add(sym, name):
      name.error(ErrLocalRedeclaration % [$name])
  else:
    # global sym
    if not gen.module.add(sym, name):
      name.error(ErrGlobalRedeclaration % [$name])

proc newProc*(script: Script, name, impl: Node,
        params: seq[ProcParam], returnTy: Sym,
        kind: ProcKind, exported = false,
        genKind: GenKind = gkToplevel): (Sym, Proc) =
  ## Creates a procedure for the given script. Returns its symbol and Proc
  ## object. This does not add the procedure to the script!
  var
    exported = exported
    name =
      if name.kind == nkIdent: name
      else:
        exported = true; # marks the proc as exported
        assert name.kind == nkPostfix, "Invalid postfix node for function identifier"
        name[1] # returns the function ident name
  if name.ident.len > 0:
    name.ident = name.ident[0] & name.ident[1..^1].toLowerAscii()
  
  if genKind != gkToplevel and exported:
    # if the proc is not a top-level proc, it cannot be exported
    name.error(ErrExportOnlyTopLevel)
    
  let
    id = script.procs.len.uint16
    strName =
      if name.kind == nkEmpty: ":anonymous"
      else: name.ident
    hasReturnType =
      if returnTy.kind == skType:
        returnTy.tyKind != tyVoid
      else:
        returnTy.kind == skGenericParam
    theProc =
      Proc(
        name: strName, kind: kind,
        paramCount: params.len,
        hasResult: hasReturnType
      )
    sym = newSym(skProc, name, impl)
  sym.procId = id
  sym.procParams = params
  sym.procReturnTy = returnTy
  sym.procExport = exported
  result = (sym, theProc)

const currentContext = Context(high(uint16))

proc pushFlowBlock(gen: var CodeGen, kind: FlowBlockKind,
                   context = currentContext) =
  ## Push a new flow block. This creates a new scope for the flow block.
  let fblock = FlowBlock(kind: kind,
                         bottomScope: gen.scopes.len)
  if context == currentContext:
    fblock.context = gen.context
  else:
    fblock.context = context
  gen.flowBlocks.add(fblock)
  gen.pushScope()

proc breakFlowBlock(gen: var CodeGen, fblock: FlowBlock) =
  ## Break a code block. This discards the flow block's scope's variables *and*
  ## generates a jump past the block.
  ## This does not remove the flow block from the stack, it only jumps past it
  ## and discards any already declared variables.
  gen.chunk.emit(opcDiscard)
  gen.chunk.emit(gen.varCount(fblock.bottomScope).uint8)
  gen.chunk.emit(opcJumpFwd)
  fblock.breaks.add(gen.chunk.emitHole(2))

proc popFlowBlock(gen: var CodeGen) =
  ## Pop the topmost flow block, popping its scope and filling in any breaks.
  gen.popScope()
  for brk in gen.flowBlocks[^1].breaks:
    gen.chunk.patchHole(brk)
  discard gen.flowBlocks.pop()

proc findFlowBlock(gen: var CodeGen, kinds: set[FlowBlockKind]): FlowBlock =
  ## Find the topmost flow block, with the given kind, and defined in the same
  ## context as ``gen``'s current context.
  ## Returns ``nil`` if a matching flow block can't be found.
  for i in countdown(gen.flowBlocks.len - 1, 0):
    let fblock = gen.flowBlocks[i]
    if fblock.context == gen.context and fblock.kind in kinds:
      return fblock

proc declareVar(gen: var CodeGen, name: Node, kind: SymKind, ty: Sym,
                isMagic = false, varExport = false): Sym {.discardable.} =
  ## Declare a new variable with the given ``name``, of the given ``kind``, with
  ## the given type ``ty``.
  ## If ``isMagic == true``, this will disable some error checks related to
  ## magic variables (eg. shadowing ``result``).

  # check if the variable's name is not ``result`` when in a non-void proc
  if not isMagic and gen.kind == gkProc and gen.procReturnTy.tyKind != tyVoid:
    if name.ident == "result":
      name.error(ErrShadowResult)

  # create the symbol for the variable
  assert kind in skVars, "Got " & $(kind) & " expected " & $(skVars)
  name.ident = 
    if name.ident.len > 1:
      name.ident[0] & name.ident[1..^1].toLowerAscii()
    else:
      name.ident
  result = newSym(kind, name)
  result.varTy = ty
  result.varSet = false
  result.varLocal =
    if gen.scopes.len > 0:
      result.varStackPos = gen.varCount;
      true
    else: false
  if not result.varLocal:
    result.varExport = varExport
  gen.addSym(result) # add the symbol to the current scope

proc lookup(gen: var CodeGen, symName: Node, quiet = false): Sym

proc genScript*(program: Ast, includePath: Option[string], isMainScript: static bool = false) {.codegen.}
proc genExpr(node: Node): Sym {.codegen.}

proc genBlock(node: Node, isStmt: bool): Sym {.codegen.}
proc genStmt(node: Node) {.codegen.}
proc genProc(node: Node, isInstantiation = false): Sym {.codegen.}
proc genMacro(node: Node, isInstantiation = false): Sym {.codegen.}
proc genIterator(node: Node, isInstantiation = false): Sym {.codegen.}
# proc genObject(node: Node, isInstantiation = false): Sym {.codegen.}
proc genObjectStorage(node: Node, isInstantiation = false): Sym {.codegen.}
proc genArray(node: Node, isInstantiation = false): Sym {.codegen.}
proc genTypeDef(node: Node): Sym {.codegen.}
proc htmlConstr(node: Node): Sym {.codegen.}

proc instantiate(gen: var CodeGen, sym: Sym, args: seq[Sym],
                 errorNode: Node): Sym =
  ## Instantiate a generic symbol using the given ``params``.
  assert sym.genericParams.isSome, "symbol must be generic"

  # we need to handle some special cases when dealing with generic generic
  # arguments, more on that below
  let hasGenericGenericArgs = args.anyIt(it.isGeneric)

  # if an instantiation has already been made, return it
  if not hasGenericGenericArgs and args in sym.genericInstCache:
    result = sym.genericInstCache[args]
  # otherwise, we need to create the instantiation from scratch
  else:
    # we need to create a temporary scope for the
    # resulting instantiation and the generic arguments
    gen.pushScope()
    # and of course, in that scope, we add those generic arguments
    if args.len != sym.genericParams.get.len:
      errorNode.error(ErrGenericArgLenMismatch %
                      [$args.len, $sym.genericParams.get.len])
    for i, param in sym.genericParams.get:
      gen.addSym(args[i], lookupName = param.name)

    case sym.kind
    of skType:
      # instantiations are only special for object types,
      # if we don't have any generic generic args
      if not hasGenericGenericArgs and sym.tyKind == tyObject:
        # result = gen.genObject(sym.impl, isInstantiation = true)
        result = gen.genObjectStorage(sym.impl, isInstantiation = true)
      # anything else creates a copy that makes a given
      # type distinct for the given generic arguments
      else:
        result = sym.clone()
        result.genericInstCache.clear()
    of skProc:
      result = gen.genProc(sym.impl, isInstantiation = true)
    of skIterator:
      result = gen.genIterator(sym.impl, isInstantiation = true)
    else:
      errorNode.error(ErrNotGeneric % $errorNode)
    # after we're done, we can remove the instantiation scope
    gen.popScope()
  result.genericInstArgs = some(args)
  result.genericBase = some(sym)

proc inferGenericArgs(gen: var CodeGen, sym: Sym,
                      argTypes: seq[Sym], callNode: Node): seq[Option[Sym]] =
  ## Use a simple recursive algorithm to infer the generic arguments for an
  ## expression. ``sym`` is the generic symbol, and ``argTypes`` are the types
  ## of arguments in a procedure or iterator call. The resulting sequence are
  ## the inferred generic argument types. If a type could not be inferred,
  ## it will be ``None``.
  assert sym.isGeneric, "symbol must be generic for type inference"

  proc walkType(types: var Table[Sym, Sym], procTy, callTy: Sym) =
    # this procedure walks through the given type and
    # fills in the ``types`` table with the appropriate types.

    # generic parameters are our main point of interest:
    # we take the call type and bind it to the type in the proc signature.
    # if the type is already bound, we compare the two and see if there's a type
    # mismatch.
    if procTy.kind == skGenericParam:
      if procTy notin types:
        types[procTy] = callTy
      else:
        if types[procTy] != callTy:
          callNode.error(ErrTypeMismatch % [$callTy, $types[procTy]])

    # as for generic types: we take all their arguments and recursively walk
    # through them. we know that ``callTy`` is compatible with this, because
    # overload resolution is done before generic param inference.
    elif procTy.genericInstArgs.isSome:
      for i, procArg in procTy.genericInstArgs.get:
        let callArg = callTy.genericInstArgs.get[i]
        walkType(types, procArg, callArg)

    # we don't care about any other types, as they're not related to generic
    # types inference.

  # to infer the generic parameters, we're going to call walkType with the
  # 'root' type pairs. those are the types in the proc's signature and the types
  # passed in through ``argTypes``.
  var types: Table[Sym, Sym]
  for i, procParam in sym.params:
    let
      procTy = procParam.ty
      callTy = argTypes[i]
    walkType(types, procTy, callTy)

  # after we walk the types, we'll collect them into our resulting seq.
  for genericParam in sym.genericParams.get:
    result.add(if genericParam in types: some(types[genericParam])
               else: Sym.none)

proc varLookup(gen: var CodeGen, id: string): Sym =
  # Look up the symbol with the given `name`.
  if gen.scopes.len > 0:
    for i in countdown(gen.scopes.high, 0):
      if gen.scopes[i].context == gen.context and id in gen.scopes[i].variables:
        return gen.scopes[i].variables[id]

  # try to find a global symbol if no local symbol was found
  if result == nil and id in gen.module.variables:
    return gen.module.variables[id]

proc funcLookup(gen: var CodeGen, id: string): Sym =
  # Look up the symbol with the given `name`.
  if gen.scopes.len > 0:
    for i in countdown(gen.scopes.high, 0):
      if gen.scopes[i].context == gen.context and id in gen.scopes[i].functions:
        return gen.scopes[i].functions[id]

  # try to find a global symbol if no local symbol was found
  if result == nil and id in gen.module.functions:
    return gen.module.functions[id]

proc typeLookup(gen: var CodeGen, id: string): Sym =
  # Look up the symbol with the given `name`.
  if gen.scopes.len > 0:
    for i in countdown(gen.scopes.high, 0):
      if gen.scopes[i].context == gen.context and
         id in gen.scopes[i].typeDefs:
        return gen.scopes[i].typeDefs[id]

  # try to find a global symbol if no local symbol was found
  if result == nil and id in gen.module.typeDefs:
    return gen.module.typeDefs[id]

proc lookup(gen: var CodeGen, symName: Node, quiet = false): Sym =
  ## Look up the symbol with the given ``name``.
  ## If ``quiet`` is true, an error will not be
  ## raised on undefined reference.
  
  # find out the symbol's name
  var name: Node
  case symName.kind
  of nkIdent: name = symName     # regular ident
  of nkVarTy: name = symName.varType
  of nkIndex:
    if symName[0].kind == nkIndex:
      # todo handle deeply nested generic instantiation
      return gen.lookup(symName[0], quiet)  # generic instantiation
    name = symName[0]  # generic instantiation
  else: discard
  if name == nil or name.kind != nkIdent:
    symName.error(ErrInvalidSymName % symName.render)
  let id = 
    if name.ident.len > 1:
      name.ident[0] & name.ident[1..^1].toLowerAscii()
    else:
      name.ident

  result = gen.typeLookup(id)
  
  # try find the symbol in the variables table
  if result == nil:
    result = gen.varLookup(id)
  
  # try find the symbol in the functions table
  if result == nil:
    result = gen.funcLookup(id)

  if result == nil:
    if not quiet:
      name.error(ErrUndefinedReference % $name)

  if symName.kind == nkIndex:
    if result.isGeneric:
      var genericParams: seq[Sym]
      if symName.kind == nkIndex:
        for param in symName[1..^1]:
          genericParams.add(gen.lookup(param))
      result = gen.instantiate(result, genericParams, errorNode = name)
    else:
      name.error(ErrNotGeneric % name.render)

proc popVar(gen: var CodeGen, name: Node) =
  # Pop the value at the top of the stack to the variable ``name``.
  let id = 
    if name.ident.len > 1:
      name.ident[0] & name.ident[1..^1].toLowerAscii()
    else:
      name.ident
  let sym: Sym = gen.varLookup(id)
  assert sym != nil
  
  if sym.varLocal:
    # if it's a local and it's already been set,
    # use `popL`, otherwise, just leave the variable on the stack
    if sym.varSet:
      gen.chunk.emit(opcPopL)
      gen.chunk.emit(sym.varStackPos.uint8)
  else:
    # if it's a global, always use popG
    gen.chunk.emit(opcPopG)
    gen.chunk.emit(gen.chunk.getString(id))
  # mark the variable as set
  sym.varSet = true

proc pushVar(gen: var CodeGen, sym: Sym) =
  ## Push the variable represented by ``sym`` to the top of the stack.
  assert sym.kind in skVars, "The symbol must represent a variable. Got " & $sym.kind
  if sym.varLocal:
    # if the variable is a local, use pushL
    gen.chunk.emit(opcPushL)
    gen.chunk.emit(sym.varStackPos.uint8)
  else:
    # if it's a global, use pushG
    gen.chunk.emit(opcPushG)
    gen.chunk.emit(gen.chunk.getString(sym.name.ident))

proc pushDefault(gen: var CodeGen, ty: Sym) =
  ## Push the default value for the type ``ty`` onto the stack.
  assert ty.kind == skType, "Only types have default values"
  assert ty.tyKind notin tyMeta, "meta-types do not represent a value"
  case ty.tyKind
  of tyBool:
    gen.chunk.emit(opcPushFalse)
  of tyInt:
    gen.chunk.emit(opcPushI)
    gen.chunk.emit(0'i64)
  of tyFloat:
    gen.chunk.emit(opcPushF)
    gen.chunk.emit(0'f64)
  of tyString:
    gen.chunk.emit(opcPushS)
    gen.chunk.emit(gen.chunk.getString(""))
  of tyObject:
    gen.chunk.emit(opcPushNil)
    gen.chunk.emit(uint16(tyFirstObject + ty.objectId))
  of tyJson:
    gen.chunk.emit(opcPushNil)
    gen.chunk.emit(uint16(tyJsonStorage))
  # of tyNil:
  #   gen.chunk.emit(opcNoop)
  else: discard  # unreachable

proc getDefaultSym*(gen: var CodeGen, kind: NodeKind): Sym =
  ## Returns the default type for the given node kind.
  case kind
  of nkBool:   result = gen.module.sym"bool"
  of nkInt:    result = gen.module.sym"int"
  of nkFloat:  result = gen.module.sym"float"
  of nkString: result = gen.module.sym"string"
  of nkArray:  result = gen.module.sym"array"
  of nkObject: result = gen.module.sym"object"
  else: discard

proc pushConst(node: Node): Sym {.codegen.} =
  ## Generate a push instruction for a constant value.
  case node.kind
  of nkBool:
    # bools - use pushTrue and pushFalse
    if node.boolVal == true:
      gen.chunk.emit(opcPushTrue)
    else:
      gen.chunk.emit(opcPushFalse)
    result = gen.module.sym"bool"
  of nkInt:
    # ints - use pushI with an int Value
    gen.chunk.emit(opcPushI)
    gen.chunk.emit(node.intVal)
    result = gen.module.sym"int"
  of nkFloat:
    # floats - use pushF with a float Value
    gen.chunk.emit(opcPushF)
    gen.chunk.emit(node.floatVal)
    result = gen.module.sym"float"
  of nkString:
    # strings - use pushS with a string ID
    gen.chunk.emit(opcPushS)
    gen.chunk.emit(gen.chunk.getString(node.stringVal))
    result = gen.module.sym"string"
  else: discard

proc findOverload(sym: Sym, args: seq[Sym],
          errorNode: Node = nil, quiet = false): Sym {.codegen.} =
  ## Finds the correct overload for ``sym``, given the parameter types.
  if sym.kind in skCallable:
    # if we don't have multiple choices, we just
    # check if the param lists are compatible
    result =
      if sym.procType == ProcType.procTypeMacro:
        if sym.sameParams(args[0..^2]): sym
        else: nil
      else:
        if sym.sameParams(args): sym
        else: nil
  elif sym.kind == skChoice:
    # otherwise, we find a matching overload by iterating through the list of
    # choices. this isn't the most efficient solution and can be optimized to use
    # a table for O(1) lookups, but time will tell if that's necessary.
    for choice in sym.choices:
      if choice.procType == ProcType.procTypeMacro:
        if choice.kind in skCallable and choice.sameParams(args[0..^2]):
          result = choice
          break
      else:
        if choice.kind in skCallable and choice.sameParams(args):
          result = choice
          break

  # if we failed to find an appropriate overload,
  # we give a nice error message to the user
  if (errorNode != nil and result == nil) and quiet == false:
    # <T, U, ...>
    var paramList = args.join(", ")
    # possible overloads
    var overloadList: string
    let overloads =
      if sym.kind == skChoice: sym.choices
      else: @[sym]
    for overload in overloads:
      if overload.kind in skCallable:
        overloadList.add("\n  " & $overload)
    # the error
    errorNode.error(ErrTypeMismatchChoice % [paramList, overloadList])

proc splitCall(ast: Node): tuple[callee: Sym, args: seq[Node]] {.codegen.} =
  ## Splits any call node (prefix, infix, call, dot access, dot call) into a
  ## callee (the thing being called) and parameters. The callee is resolved to a
  ## symbol.
  var
    callee: Node
    args: seq[Node]
  assert ast.kind in {nkPrefix, nkInfix,
            nkCall, nkDot, nkIdent, nkString, nkArray}
  case ast.kind
  of nkPrefix:
    callee = ast[0]
    args = @[ast[1]]
  of nkInfix:
    callee = ast[0]
    args = ast[1..2]
  of nkCall:
    if ast[0].kind == nkDot:
      let lhs = ast[0]
      callee = lhs[1]
      args = @[lhs[0]]
      args.add(ast[1..^1])
    else:
      callee = ast[0]
      args = ast[1..^1]
  of nkDot:
    callee = ast[1]
    args = @[ast[0]]
  of nkString:
    callee = ast
  of nkIdent:
    callee = newIdent("items") # the built-in items() iterator
    args = @[ast]
  of nkArray:
    return (gen.genExpr(ast), @[])
  else: discard
  assert callee != nil
  result = (gen.lookup(callee), args)

proc resolveGenerics*(gen: var CodeGen, callable: var Sym,
                      callArgTypes: seq[Sym], errorNode: Node) =
  ## Helper used to resolve generic parameters via inference.
  if callable.isGeneric:
    let genericArgs =
      gen.inferGenericArgs(callable, callArgTypes, errorNode).mapIt do:
        if it.isSome: it.get
        else:
          errorNode.error(ErrCouldNotInferGeneric % errorNode.render)
          nil
    callable = gen.instantiate(callable, genericArgs, errorNode)

proc callProc(procSym: Sym, argTypes: seq[Sym],
              errorNode: Node = nil): Sym {.codegen.} =
  ## Generate code that calls a procedure. ``errorNode``
  ## is used for error reporting.
  if procSym.kind in {skProc, skChoice}:
    # find the overload
    var theProc = gen.findOverload(procSym, argTypes, errorNode)
    if theProc.kind != skProc:
      errorNode.error(ErrSymKindMismatch % [$skProc, $theProc.kind])
  
    # resolve generic params
    gen.resolveGenerics(theProc, argTypes, errorNode)
    
    # call the proc
    gen.chunk.emit(opcCallD)
    gen.chunk.emit(theProc.procId)
    result = theProc.procReturnTy
  elif procSym.kind in skVars:
    discard # TODO: call through reference in variable
  # elif procSym.kind == skHtmlType:
  #   var theProc = gen.findOverload(procSym, argTypes, errorNode)
  #   gen.chunk.emit(opcCallD)
  #   gen.chunk.emit(theProc.procId)
  #   result = theProc.procReturnTy
  else:
    # anything that is not a proc cannot be called
    if errorNode != nil: errorNode.error(ErrNotAProc % $procSym.name)

proc prefix(node: Node): Sym {.codegen.} =
  ## Generate instructions for a prefix operator.
  # TODO: see infix()
  var noBuiltin = false # is no builtin operator available?
  let ty = gen.genExpr(node[1]) # generate the operand's code
  if ty in [gen.module.sym"int", gen.module.sym"float"]:
    # number operators
    let isFloat = ty == gen.module.sym"float"
    case node[0].ident
    of "+": discard # + is a noop
    of "-": gen.chunk.emit(if isFloat: opcNegF else: opcNegI)
    else: noBuiltin = true # non-builtin operator
    result = ty
  elif ty == gen.module.sym"bool":
    # bool operators
    case node[0].ident
    of "not": gen.chunk.emit(opcInvB)
    else: noBuiltin = true # non-builtin operator
    result = ty
  else: noBuiltin = true
  if noBuiltin:
    let procSym = gen.lookup(node[0])
    result = gen.callProc(procSym, argTypes = @[ty], node)

proc infix(node: Node): Sym {.codegen.} =
  ## Generate instructions for an infix operator.

  # TODO: split this behemoth into compiler magic procs that deal with this
  # instead of keeping all the built-in operators here

  if node[0].ident notin ["=", "or", "and"]:
    # primitive operators
    var noBuiltin: bool # is there no built-in operator available?
    let
      aTy = gen.genExpr(node[1]) # generate the left operand's code
      bTy = gen.genExpr(node[2]) # generate the right operand's code
    let numOp = [gen.module.sym"float", gen.module.sym"int"]
    if (aTy in numOp and bTy in numOp):
      # number operators
      let areFloats =
        aTy == gen.module.sym"float" or bTy == gen.module.sym"float"
      case node[0].ident
      # arithmetic
      of "+": gen.chunk.emit(if areFloats: opcAddF else: opcAddI)
      of "-": gen.chunk.emit(if areFloats: opcSubF else: opcSubI)
      of "*": gen.chunk.emit(if areFloats: opcMultF else: opcMultI)
      of "/": gen.chunk.emit(if areFloats: opcDivF else: opcDivI)
      # relational
      of "==": gen.chunk.emit(if areFloats: opcEqF else: opcEqI)
      of "!=":
        gen.chunk.emit(if areFloats: opcEqF else: opcEqI)
        gen.chunk.emit(opcInvB)
      of "<": gen.chunk.emit(if areFloats: opcLessF else: opcLessI)
      of "<=":
        gen.chunk.emit(if areFloats: opcGreaterF else: opcGreaterI)
        gen.chunk.emit(opcInvB)
      of ">": gen.chunk.emit(if areFloats: opcGreaterF else: opcGreaterI)
      of ">=":
        gen.chunk.emit(if areFloats: opcLessF else: opcLessI)
        gen.chunk.emit(opcInvB)
      else: noBuiltin = true # unknown operator
      result =
        case node[0].ident
        # arithmetic operators return numbers.
        of "+", "-", "*", "/":
          if areFloats: gen.module.sym"float"
          else: gen.module.sym"int"
        # relational operators return bools
        of "==", "!=", "<", "<=", ">", ">=":
          gen.module.sym"bool"
        else: nil # type mismatch; we don't care
    elif aTy == bTy and aTy == gen.module.sym"bool":
      # bool operators
      case node[0].ident
      # relational
      of "==": gen.chunk.emit(opcEqB)
      of "!=": gen.chunk.emit(opcEqB); gen.chunk.emit(opcInvB)
      else: noBuiltin = true
      # bool operators return bools (duh.)
      result = gen.module.sym"bool"
    else: noBuiltin = true # no optimized operators for given type
    if noBuiltin:
      let procSym = gen.lookup(node[0])
      result = gen.callProc(procSym, argTypes = @[aTy, bTy], node)
  else:
    case node[0].ident
    # assignment is special
    of "=":
      let
        receiver = node[1]
        value = node[2]
      case receiver.kind
      of nkIdent: # to a variable
        let
          sym = gen.lookup(receiver) # look the variable up
          valTy = gen.genExpr(value) # generate the value
        if valTy == sym.varTy:
          # if the variable's type matches the type of the value, we're ok
          gen.popVar(receiver)
        else:
          node.error(ErrTypeMismatch % [$valTy.name, $sym.varTy.name])
      of nkDot: # to an object field
        if receiver[1].kind != nkIdent:
          # object fields are always identifiers
          receiver[1].error(ErrInvalidField % $node[1][1])
        let
          typeSym = gen.genExpr(receiver[0]) # generate the receiver's code
          fieldName = receiver[1].ident
          valTy = gen.genExpr(value) # generate the value's code
        if typeSym.tyKind == tyObject and fieldName in typeSym.objectFields:
          # assign the field if it's valid, using popF
          let field = typeSym.objectFields[fieldName]
          if valTy != field.ty:
            node[2].error(ErrTypeMismatch % [$field.ty.name, $valTy.name])
          gen.chunk.emit(opcSetF)
          gen.chunk.emit(field.id.uint8)
        else:
          # otherwise, try to find a matching setter
          let setter = gen.lookup(newIdent(fieldName & '='))
          if setter == nil:
            receiver.error(ErrNonExistentField % [fieldName, $typeSym])
          result = gen.callProc(setter, argTypes = @[typeSym, valTy],
                                errorNode = node)
      else: node.error(ErrInvalidAssignment % $node)
      # assignment doesn't return anything (in most cases, setters can be
      # declared to return a value, albeit it's not that useful)
      if result == nil:
        result = gen.module.sym"void"
    # ``or`` and ``and`` are special, because they're short-circuiting.
    # that's why they need a little more special care.
    of "or": # ``or``
      let
        lhs = node[1]
        rhs = node[2]
      let aTy = gen.genExpr(lhs) # generate the left-hand side
      # if it's ``true``, jump over the rest of the expression
      gen.chunk.emit(opcJumpFwdT)
      let hole = gen.chunk.emitHole(2)
      # otherwise, check the right-hand side
      gen.chunk.emit(opcDiscard)
      gen.chunk.emit(1'u8)
      let bTy = gen.genExpr(rhs) # generate the right-hand side
      if aTy.tyKind != tyBool: lhs.error(ErrTypeMismatch % [$aTy, "bool"])
      if bTy.tyKind != tyBool: rhs.error(ErrTypeMismatch % [$bTy, "bool"])
      gen.chunk.patchHole(hole)
      result = gen.module.sym"bool"
    of "and": # ``and``
      let
        lhs = node[1]
        rhs = node[2]
      let aTy = gen.genExpr(lhs) # generate the left-hand side
      # if it's ``false``, jump over the rest of the expression
      gen.chunk.emit(opcJumpFwdF)
      let hole = gen.chunk.emitHole(2)
      # otherwise, check the right-hand side
      gen.chunk.emit(opcDiscard)
      gen.chunk.emit(1'u8)
      let bTy = gen.genExpr(rhs) # generate the right-hand side
      if aTy.tyKind != tyBool: lhs.error(ErrTypeMismatch % [$aTy, "bool"])
      if bTy.tyKind != tyBool: rhs.error(ErrTypeMismatch % [$bTy, "bool"])
      gen.chunk.patchHole(hole)
      result = gen.module.sym"bool"
    of "&":
      # string concatenation
      let
        lhs = node[1]
        rhs = node[2]
      let aTy = gen.genExpr(lhs) # generate the left-hand side
      let bTy = gen.genExpr(rhs) # generate the right-hand side 
      if aTy.tyKind != tyString:
        lhs.error(ErrTypeMismatch % [$aTy, "string"])
      if bTy.tyKind != tyString:
        rhs.error(ErrTypeMismatch % [$bTy, "string"])
      let procSym = gen.lookup(node[0])
      result = gen.callProc(procSym, @[aTy, bTy], errorNode = node)
      # result = gen.procCall(node[0], sym)
    else: discard

proc objConstr(node: Node, ty: Sym, constructFromIdent = false): Sym {.codegen.} =
  ## Generate code for an object constructor.

  # find the object type that's being constructed
  result =
    if not constructFromIdent: 
      gen.lookup(node[0])
    else:
      gen.lookup(node)

  if result.tyKind != tyObject:
    node.error(ErrTypeIsNotAnObject % $result.name)

  # currently, hayago doesn't allow the user to omit fields
  # TODO: allow the user to not initialize some fields, and set them to their
  # corresponding types' default values instead.
  # if node.len - 1 != result.objectFields.len:
    # node.error(ErrObjectFieldsMustBeInitialized)
  # for i in 0..result.objectFields.high:

  # collect the initialized fields into a seq with their values and the fields
  # themselves
  var fields: seq[tuple[node: Node, field: ObjectField]]

  if not constructFromIdent:
    fields.setLen(result.objectFields.len)

  # for f in node[1..^1]:
  #   # all fields are initialized using the a: b syntax, no exceptions
  #   # if f.kind != nkColon:
  #   #   f.error(ErrFieldInitMustBeAColonExpr)

  #   # we make sure the field actually exists
  #   let name = f[0].ident
  #   if name notin result.objectFields:
  #     f[0].error(ErrNonExistentField % [name, $result])

  #   # then we assign the field a value.
  #   let field = result.objectFields[name]
  #   fields[field.id] = (node: f[1], field: field)

  if not constructFromIdent:
    var explicitFields: Table[string, Node]
    for f in node[1..^1]:
      explicitFields[f[0].ident] = f[1]
    
    for k, v in result.objectFields:
      if explicitFields.hasKey(k):
        discard
      else:
        fields[v.id] = (node: v.name, field: v)

  # iterate the fields and values, and push them onto the stack.
  # for (value, field) in fields:
    # let ty = gen.genExpr(value)
    # if ty != field.ty:
    #   node.error(ErrTypeMismatch % [$ty, $field])

  # construct the object
  gen.chunk.emit(opcConstrObj)
  gen.chunk.emit(uint16(tyFirstObject + ty.objectId))
  gen.chunk.emit(uint8(fields.len))

proc procCall(node: Node, procSym: Sym): Sym {.codegen.} =
  ## Generate code for a procedure call.
  # we simply push all the arguments onto the stack
  var argTypes: seq[Sym]
  # if node[^1].kind in {nkHtmlElement, nkIf, nkFor, nkCall}:
  #   # if the last argument is an HTML element
  #   # it is a macro call, so we need to
  #   # push the HTML element onto the stack
  #   for arg in node[1..^2]:
  #     let argSym: Sym = gen.genExpr(arg)
  #     assert argSym != nil, "Expression must return a symbol"
  #     argTypes.add(argSym)
  #   # the last argument is a HTML element, so we need to
  #   # create a symbol for it and add it to the argument types
  #   let anyStmt = gen.module.sym"stmt" # gen.genExpr(node[^1])
  #   anyStmt.impl = node[^1]
  #   argTypes.add(anyStmt)
  # else:
  for arg in node[1..^1]:
    let argSym: Sym = gen.genExpr(arg)
    assert argSym != nil, "Expression must return a symbol"
    argTypes.add(argSym)
  # ...and delegate the call to callProc
  result = gen.callProc(procSym, argTypes, errorNode = node)

proc call(node: Node): Sym {.codegen.} =
  ## Generates code for an nkCall (proc call or object constructor).
  ## TODO: Indirect calls
  case node[0].kind
  of nkIdent:
    # the call is direct or from a variable
    let sym = gen.lookup(node[0])  # lookup the left-hand side
    case sym.kind
    of skType: # object construction
      result = gen.objConstr(node, sym)
    else: # procedure call
      result = gen.procCall(node, sym)
  of nkDot:
    # the call is an indirect call or a method call
    let
      lhs = node[0]
      callee = gen.lookup(lhs[1], quiet = true)
    if callee == nil:
      assert false, "indirect calls are not implemented yet: " & node.render
    else:
      var argTypes = @[gen.genExpr(lhs[0])]
      for arg in node[1..^1]:
        argTypes.add(gen.genExpr(arg))
      result = gen.callProc(callee, argTypes, errorNode = node)
  else:
    # the call is an indirect call
    assert false, "indirect calls are not implemented yet: " & node.render

proc genGetField(node: Node): Sym {.codegen.} =
  # Generate code for field access.

  # all fields must be idents, so we check for that.
  if node[1].kind != nkIdent:
    node[1].error(ErrInvalidField % $node[1])

  let
    typeSym = gen.genExpr(node[0])  # generate the left-hand side
    fieldName = node[1].ident       # get the field's name
  # only objects have fields. we also check if the given object *does* have the
  # field in question, and generate an error if not
  if typeSym.tyKind == tyObject and fieldName in typeSym.objectFields:
    # we use the getF opcode to push fields onto the stack.
    let field = typeSym.objectFields[fieldName]
    result = field.ty
    gen.chunk.emit(opcGetF)
    gen.chunk.emit(field.id.uint8)
  else:
    # if the field doesn't actually exist, we find
    # an appropriate proc that will retrieve it for us
    let getter = gen.lookup(node[1])
    if getter == nil:
      node[1].error(ErrNonExistentField % [fieldName, $typeSym])
    result = gen.callProc(getter, argTypes = @[typeSym], errorNode = node)

proc genArrayAccess(node: Node): Sym {.codegen.} =
  # Generate code for array access.
  # This is used for both arrays and JSON nodes (json arrays and objects)
  let
    valty = gen.genExpr(node[0])
    indexTy = gen.genExpr(node[1])

  # check if the array is actually an array
  if valty.tyKind notin {tyArray, tyObject, tyJson}:
    node[0].error(ErrTypeMismatch % [$valty.name, "array"])
  
  case valty.tyKind
  of tyJson:
    # generate the code for accessing a JSON array
    if indexTy.tyKind notin {tyInt, tyString}:
      # check if the index is actually an int or a string
      # because both JSON arrays and objects can be accessed
      # using the bracket notation
      node[1].error(ErrTypeMismatch % [$indexTy.name, "int|string"])
    gen.chunk.emit(opcGetJ)
    result = valty
  of tyObject:
    if indexTy.tyKind != tyString:
      # check if the index is actually an int
      node[1].error(ErrTypeMismatch % [$indexTy.name, "string"])
    # todo support getting fields from objects using the bracket notation
    # this is not supported yet, so we just raise an error
    echo "not implemented yet: accessing object fields using the bracket notation"
    result = valty
  of tyArray:
    # generate the code to access the array
    if indexTy.tyKind != tyInt:
      # check if the index is actually an int
      node[1].error(ErrTypeMismatch % [$indexTy.name, "int"])
    
    # if valty.arrayItems.len > 0:
      # todo maybe we can handle multi type arrays?
      # valty.arrayTy = valty.arrayItems[0]
    
    # todo raise an error if the index is out of bounds
    # node[1].error(ErrTypeMismatch % [$indexTy.name, "int"])
    gen.chunk.emit(opcGetI)
    result = valty.arrayTy
    # result = gen.module.sym"int" # TODO: fix this, we need to know the type of the array items
  else: discard # todo error?

proc genIf(node: Node, isStmt: bool): Sym {.codegen.} =
  ## Generate code for an if expression/statement.

  # get some properties about the statement
  let
    hasElse = node.len mod 2 == 1
    branches =
      # separate the else branch from the rest of branches and conditions
      if hasElse: node[0..^2]
      else: node.children

  # then, we compile all the branches
  var jumpsToEnd: seq[int]
  for i in countup(0, branches.len - 1, 2):
    # if there was a previous branch, discard its condition
    if i != 0:
      gen.chunk.emit(opcDiscard)
      gen.chunk.emit(1'u8)

    # first, we compile the condition and check its type
    let
      cond = branches[i]
      condTy = gen.genExpr(cond)
    if condTy.tyKind != tyBool:
      cond.error(ErrTypeMismatch % [$condTy.name, "bool"])

    # if the condition is false, jump past the branch
    gen.chunk.emit(opcJumpFwdF)
    let afterBranch = gen.chunk.emitHole(2)

    # otherwise, discard the condition's value and execute the body
    gen.chunk.emit(opcDiscard)
    gen.chunk.emit(1'u8)
    let
      branch = branches[i + 1]
      branchTy = gen.genBlock(branch, isStmt)

    # if the ``if`` is an expression, check its type
    if not isStmt:
      if result == nil: result = branchTy
      else:
        if branchTy != result:
          branch.error(ErrTypeMismatch % [$branchTy.name, $result.name])


    # after the block is done, jump to the end of the whole statement
    gen.chunk.emit(opcJumpFwd)
    jumpsToEnd.add(gen.chunk.emitHole(2))

    # we also need to fill the previously created jump after the branch
    gen.chunk.patchHole(afterBranch)
    # after the branch, there's another branch or the end of the if statement

  # discard the last branch's condition
  gen.chunk.emit(opcDiscard)
  gen.chunk.emit(1'u8)

  # if we have an else branch, we need to compile it, too
  if hasElse:
    let
      elseBranch = node[^1]
      elseTy = gen.genBlock(elseBranch, isStmt)
    # check its type
    if not isStmt and elseTy != result:
      elseBranch.error(ErrTypeMismatch % [$elseTy.name, $result.name])
  else:
    if not isStmt:
      # raise an error if the if statement is an expression and
      # the else branch is missing
      node.error(ErrTypeMismatch % ["void", "expression"])

  # finally, fill all the jump gaps
  for jmp in jumpsToEnd:
    gen.chunk.patchHole(jmp)

  # if the 'if' is a statement, its type is void
  if isStmt:
    result = gen.module.sym"void"

proc storeJavaScript(node: Node): Sym {.codegen.} =
  ## Store a JavaScript snippet into the current module.
  gen.script.jsOutput.add(node.snippetCode)

proc genParam(name: Node, ty: Sym, sym: Sym = nil,
              isMut, isOpt = false): ProcParam =
  (name, ty, sym, isMut, isOpt)

proc collectParams(formalParams: Node): seq[ProcParam] {.codegen.} =
  # Helper used to collect parameters from an
  # `nkFormalParams` to a `seq[ProcParam]`
  for defs in formalParams[1..^1]:
    var implSym: Sym
    if defs[^1].kind == nkEmpty:
      implSym = nil
    else:
      let n = defs[^1]
      case n.kind
      of nkBool, nkInt, nkFloat, nkString:
        implSym = gen.getDefaultSym(n.kind)
        implSym.impl = n
      else:
        implSym = gen.lookup(n)
    let ty: Sym =
      if implSym == nil: gen.lookup(defs[^2])
      else: implSym
    for name in defs[0..^3]:
      case ty.tyKind
      of tyArray:
        if ty.arrayTy == nil and defs[^2].kind == nkIndex:
          # if the array type is known
          let identSym: Sym = gen.typeLookup(defs[^2][1].ident)
          let genericParam: Sym = newSym(skGenericParam, defs[^2][1], nil)
          genericParam.constraint = identSym
          ty.arrayTy = identSym
        if implSym != nil:
          # otherwise, we assume the array is of
          # the same type as the implementation symbol
          ty.arrayTy = implSym
        elif ty.arrayTy == nil:
          # well, we don't know the type of the array.
          # so we emit an error that the array type is not concrete
          name.error(ErrTypeNotConcrete % ["array"])
        result.add(genParam(name, ty, implSym,
            # determine if the parameter is marked as `var` mutable
            isMut = defs[^2].kind == nkVarTy,
            # implicit values marks the parameter as optional
            isOpt = defs[^1].kind != nkEmpty
          )
        )
      else:
        result.add(genParam(name, ty, implSym,
            # determine if the parameter is marked as `var` mutable
            isMut = defs[^2].kind == nkVarTy,
            # implicit values marks the parameter as optional
            isOpt = defs[^1].kind != nkEmpty
          )
        )

proc collectGenericParams(genericParams: Node): Option[seq[Sym]] {.codegen.} =
  # Helper used to collect and declare
  # generic parameters from an nkGenericParams.
  if genericParams.kind == nkEmpty: return
  result = some[seq[Sym]](@[])
  for defs in genericParams:
    let constraint =
      if defs[^2].kind == nkEmpty: gen.module.sym"any"
      else: gen.lookup(defs[^2])
    for name in defs[0..^3]:
      let sym = newSym(skGenericParam, name, impl = name)
      sym.constraint = constraint
      gen.addSym(sym)
      result.get.add(sym)

proc genProc(node: Node, isInstantiation = false): Sym {.codegen.} =
  # Process and compile a procedure.
  # push a new scope for generic parameters, if any
  if not isInstantiation and node[1].kind != nkEmpty:
    gen.pushScope()
  # get some basic metadata
  let
    name = node[0]
    formalParams = node[2]
    body = node[3]
    genericParams =
      if not isInstantiation:
        gen.collectGenericParams(node[1])
      else:
        seq[Sym].none
    params = gen.collectParams(formalParams)
    returnTy = # empty return type == void
      if formalParams[0].kind != nkEmpty:
        gen.lookup(formalParams[0])
      else:
        gen.module.sym"void"
  # create a new proc
  var (sym, theProc) =
    newProc(gen.script, name, impl = node,
              params, returnTy, kind = pkNative,
              genKind = gen.kind)
  sym.genericParams = genericParams
  # add the proc into the declaration scope
  # we need to do this here, otherwise recursive
  # calls will be broken
  gen.addSym(sym, scopeOffset = ord(sym.genericParams.isSome))
  # if we're in an instantiation or the proc is
  # not generic, generate its code
  if not sym.isGeneric or isInstantiation:
    var
      chunk = newChunk()
      procGen = initCodeGen(gen.script, gen.module, chunk, gkProc,
        ctxAllocator =
          if gen.kind == gkToplevel: nil
          else: gen.ctxAllocator
      )
    theProc.chunk = chunk
    chunk.file = gen.chunk.file
    procGen.procReturnTy = returnTy

    # add the proc's parameters as locals
    # TODO: closures and upvalues
    if params.len > 0:
      procGen.pushScope()
      for (name, ty, implSym, isMut, isOpt) in params:
        var varType =
          if isMut: skVar # value is mutable
          else: skLet # value is immutable
        let param = procGen.declareVar(name, varType, ty)
        # if the parameter has an implementation value,
        # we need to push it onto the stack
        if implSym != nil:
          if implSym.impl != nil:
            discard gen.genExpr(implSym.impl)
        param.varSet = true  # arguments are not assignable

    # declare ``result`` if applicable
    if returnTy.tyKind != tyVoid:
      let res = newIdent("result")
      procGen.declareVar(res, skVar, returnTy, isMagic = true)
      procGen.pushDefault(returnTy)
      procGen.popVar(res)
  
    # add the proc into the script
    gen.script.procs.add(theProc)
    if sym.procExport:
      gen.script.procsExport.add(theProc)

    # compile the proc's body
    discard procGen.genBlock(body, isStmt = true)

    # finally, return ``result`` if applicable
    if returnTy.tyKind != tyVoid:
      let resultSym = procGen.lookup(newIdent("result"))
      procGen.chunk.emit(opcPushL)
      procGen.chunk.emit(resultSym.varStackPos.uint8)
      procGen.chunk.emit(opcReturnVal)
    else:
      procGen.chunk.emit(opcReturnVoid)
  else:
    # add the proc into the script
    gen.script.procs.add(theProc)

  # pop the generic declaration scope
  # if not isInstantiation and node[1].kind != nkEmpty:
  if not isInstantiation and sym.isGeneric:
    gen.popScope()
  result = sym

proc genMacro(node: Node, isInstantiation = false): Sym {.codegen.} =
  ## Generates code for a block of code that contains a procedure.
  if not isInstantiation and node[1].kind != nkEmpty:
    gen.pushScope()
  # get some basic metadata
  let
    name = node[0]
    formalParams = node[2]
    body = node[3]
    genericParams =
      if not isInstantiation: gen.collectGenericParams(node[1])
      else: seq[Sym].none
    params = gen.collectParams(formalParams)
    returnTy = # empty return type == void
      if formalParams[0].kind != nkEmpty:
        gen.lookup(formalParams[0])
      else:
        gen.module.sym"void"
  # create a new proc
  var (sym, theProc) =
        gen.script.newProc(name, impl = node,
                    params, returnTy, kind = pkNative)
  sym.genericParams = genericParams
  sym.procType = ProcType.procTypeMacro
  
  # add the proc into the declaration scope
  # we need to do this here, otherwise recursive calls will be broken
  gen.addSym(sym, scopeOffset = ord(sym.genericParams.isSome))

  # if we're in an instantiation or the proc is not generic, generate its code
  if not sym.isGeneric or isInstantiation:
    var
      chunk = newChunk()
      procGen = initCodeGen(gen.script, gen.module, chunk, gkBlockProc)
    theProc.chunk = chunk
    chunk.file = gen.chunk.file
    procGen.procReturnTy = returnTy

    # add the proc's parameters as locals
    # TODO: closures and upvalues
    procGen.pushScope()
    for (name, ty, implValTy, isMut, isOpt) in params:
      var varType = if isMut: skVar else: skLet
      let param = procGen.declareVar(name, varType, ty)
      param.varSet = true  # arguments are not assignable
    
    # todo
    # let stmtVar = procGen.declareVar(ast.newIdent("stmt"), skLet, gen.module.sym"any")
    # stmtVar.varSet = true
    # procGen.pushDefault(gen.module.sym"string")
    
    # define the default `blockAttributes` variable
    # this is used to store the attributes of the block.
    let blockAttributes = newIdent("blockAttributes")
    procGen.declareVar(blockAttributes, skVar, gen.module.sym"string", isMagic = true)
    procGen.pushDefault(gen.module.sym"string")
    procGen.popVar(blockAttributes)
    
    # defines the default `blockStmt` variable
    # this is used to store any additional statements
    # provided at call time
    let blockStmt = newIdent("blockStmt")
    procGen.declareVar(blockStmt, skVar, gen.module.sym"any", isMagic = true)
    procGen.popVar(blockStmt)

    # add the proc into the script
    gen.script.procs.add(theProc)
    if sym.procExport:
      gen.script.procsExport.add(theProc)

    # compile the proc's body
    discard procGen.genBlock(body, isStmt = true)

    # if the macro has any deferred code to be executed,
    # we need to emit it now.
    # procGen.chunk.emit(opcLoadDeferred)

    # finally, return ``result`` if applicable
    if returnTy.tyKind != tyVoid:
      let resultSym = procGen.lookup(newIdent("result"))
      procGen.chunk.emit(opcPushL)
      procGen.chunk.emit(resultSym.varStackPos.uint8)
      procGen.chunk.emit(opcReturnVal)
    else:
      procGen.chunk.emit(opcReturnVoid)

  # pop the generic declaration scope
  if not isInstantiation and sym.isGeneric:
    gen.popScope()
  result = sym

proc genTypeDef(node: Node): Sym {.codegen.} =
  # Generates code for a type definition
  discard

proc htmlConstr(node: Node): Sym {.codegen.} =
  # Constructs a new HTML element from Html object
  if gen.kind == gkProc:
    node.error(ErrOnlyUsableInAMacro % "HTML")
  let tag = node.getTag()
  let tagIdent = ast.newIdent(tag & "_" & $(gen.counter))
  let tagPos = gen.chunk.getString(tag)
  result = Sym(
    name: tagIdent,
    kind: skHtmlType,
    isVoidElement: node.tag in voidHtmlElements
  )
  if node.attributes.len > 0:
    gen.chunk.emit(opcBeginHtmlWithAttrs)
    gen.chunk.emit(tagPos)
    var classAttributes: seq[string]
    for attr in node.attributes:
      case attr.attrType:
      of htmlAttrClass:
        classAttributes.add(attr.attrNode.stringVal)
      of htmlAttrId:
        gen.chunk.emit(opcWSpace)
        gen.chunk.emit(opcAttrId)
        gen.chunk.emit(gen.chunk.getString(attr.attrNode.stringVal))
      of htmlAttr:
        assert attr.attrNode.kind == nkInfix, "attribute node must be an infix. Got " & $(attr.attrNode.kind)
        gen.chunk.emit(opcWSpace) # add a space before the attribute
        discard gen.genExpr(attr.attrNode[2]) # value
        discard gen.genExpr(attr.attrNode[1]) # key
        gen.chunk.emit(opcAttr) # emit the attribute opcode
      else: discard
    if classAttributes.len > 0:
      # if there are any classes, we emit them as a single attribute
      gen.chunk.emit(opcWSpace)
      gen.chunk.emit(opcAttrClass)
      gen.chunk.emit(gen.chunk.getString(classAttributes.join(" ")))
    gen.chunk.emit(opcAttrEnd)
  else:
    gen.chunk.emit(opcBeginHtml)
    gen.chunk.emit(tagPos)

  # gen.addSym(result)
  inc(gen.counter)

  # if the node has any subnodes, we need to
  # generate code for them and push them onto the stack
  if node.childElements.len > 0:
    gen.pushScope()
    for subNode in node.childElements:
      case subNode.kind
      of nkBool, nkInt, nkFloat, nkString:
        discard gen.pushConst(subNode)
        gen.chunk.emit(opcTextHtml)
      of nkIdent, nkCall, nkDot, nkInfix:
        discard gen.genExpr(subNode)
        gen.chunk.emit(opcTextHtml)
      else:
        gen.chunk.emit(opcInnerHtml)
        gen.genStmt(subNode)
    gen.popScope()
  
  # add the generated symbol to the module
  gen.chunk.emit(opcCloseHtml)
  gen.chunk.emit(tagPos)

proc genExpr(node: Node): Sym {.codegen.} =
  # Generates code for an expression.
  case node.kind
  of nkBool, nkInt, nkFloat, nkString:  # constants
    result = gen.pushConst(node)
  of nkHtmlElement:
    result = gen.htmlConstr(node)
  of nkIdent:                     # variables
    var symNode = gen.lookup(node)
    case symNode.kind:
    of skType:
      case symNode.tyKind
      of tyObject:
        return gen.objConstr(node, symNode, constructFromIdent = true)
      else: discard
    else: discard
    gen.pushVar(symNode)
    return symNode.varTy
  of nkPrefix:                    # prefix operators
    result = gen.prefix(node)
  of nkInfix:                     # infix operators
    result = gen.infix(node)
  of nkDot:
    # generate code for object/class field access
    result = gen.genGetField(node)
  of nkBracket:
    # handle array access using square brackets `$a[0]`
    result = gen.genArrayAccess(node)
  of nkCall:                      # calls and object construction
    result = gen.call(node)
  of nkIf:                        # if expressions
    result = gen.genIf(node, isStmt = false)
  of nkArray:
    result = gen.genArray(node)        # array declaration
  of nkObject:
    result = gen.genObjectStorage(node)
    # result = gen.objConstr(node, gen.lookup(node[0]), constructFromIdent = true)
  else:
    node.error(ErrValueIsVoid)

proc genWhile(node: Node) {.codegen.} =
  ## Generates code for a while loop.

  # we'll need some stuff before generating any code
  var
    isWhileTrue = false  # an optimization for while true loops
    afterLoop: int       # a hole pointer to the end of the loop
  let beforeLoop = gen.chunk.code.len

  # begin a new loop by pushing the outer flow control block
  gen.pushFlowBlock(fbLoopOuter)

  # literal bool conditions are optimized
  case node[0].kind
  of nkBool:
    if node[0].boolVal == true:
      # 'while true' is optimized: the condition is not evaluated at all, so
      # there's only one jump
      isWhileTrue = true
    else:
      # 'while false' is optimized out completely, because it's a no-op.
      # first we must pop the flow block, otherwise stuff would go haywire
      gen.popFlowBlock()
      return
  else: discard

  if not isWhileTrue:
    # if it's not a while true loop, execute the condition
    let condTy = gen.genExpr(node[0])
    if condTy.tyKind != tyBool:
      node[0].error(ErrTypeMismatch % [$condTy.name, "bool"])

    # if it's false, jump over the loop's body
    gen.chunk.emit(opcJumpFwdF)
    afterLoop = gen.chunk.emitHole(2)

    # otherwise, discard the condition, and execute the body
    gen.chunk.emit(opcDiscard)
    gen.chunk.emit(1'u8)

  # generate the body. we don't care about its type, because while loops are not
  # expressions. this also creates the `iteration` flow block used by
  # ``continue`` statements
  # XXX: creating a flow block here creates a scope without any unique
  # variables, then genBlock creates another scope. optimize this
  gen.pushFlowBlock(fbLoopIter)
  discard gen.genBlock(node[1], isStmt = true)
  gen.popFlowBlock()

  # after the body's done, jump back to reevaluate the condition
  gen.chunk.emit(opcJumpBack)
  gen.chunk.emit(uint16(gen.chunk.code.len - beforeLoop - 1))
  if not isWhileTrue:
    # if it wasn't a while true, we need to fill in the hole after the loop
    gen.chunk.patchHole(afterLoop)
    # ...and pop the condition off the stack after the loop is done
    gen.chunk.emit(opcDiscard)
    gen.chunk.emit(1'u8)

  # finish the loop by popping its outer flow block.
  gen.popFlowBlock()

proc genFor(node: Node) {.codegen.} =
  ## Generate code for a ``for`` loop.
  ##
  ## Actually, a for loop isn't really a `loop`. It can be, if the iterator
  ## actually does use a loop, but it doesn't have to.
  ## All a ``for`` loop does is it walks the body of the iterator and replaces
  ## any ``yield``s with the for loop's body.

  # this is some really fragile stuff, I wouldn't be surprised if it contains
  # like, a million bugs

  # as of now, only one loop variable is supported
  # this will be changed when tuples are introduced
  let
    loopVarName = node[0]
    (iterSym, iterParams) = gen.splitCall(node[1])
    body = node[2]

  # create a new code generator for the iterator with a separated context
  var iterGen = gen.clone(gkIterator)
  iterGen.iterForBody = body
  iterGen.iterForVar = loopVarName
  iterGen.iterForCtx = gen.context
  iterGen.context = gen.ctxAllocator.allocCtx()

  # generate the arguments passed to the iterator
  # the context is switched only *after* the loop's outer flow block is pushed,
  # so that the loop can be ``break`` properly
  iterGen.pushFlowBlock(fbLoopOuter, gen.context)
  var argTypes: seq[Sym]
  for arg in iterParams:
    argTypes.add(iterGen.genExpr(arg))
  # resolve the iterator's overload
  var theIter = gen.findOverload(iterSym, argTypes, node[1], quiet = true)

  if theIter.kind != skIterator:
    node[1].error(ErrSymKindMismatch % [$skIterator, $theIter.kind])
  gen.resolveGenerics(theIter, argTypes, node[1])
  iterGen.iter = theIter

  # declare all the variables passed as the iterator's arguments
  for (name, ty, implSym, isMut, isOpt) in theIter.iterParams:
    var varType = if isMut: skVar else: skLet
    var arg = iterGen.declareVar(name, varType, ty)
    arg.varSet = true

  # iterate
  discard iterGen.genBlock(theIter.impl[3], isStmt = true)

  # clean up the argument scope and free the scope context
  iterGen.popFlowBlock()
  gen.ctxAllocator.freeCtx(iterGen.context)

proc genBreak(node: Node) {.codegen.} =
  ## Generate code for a ``break`` statement.

  # break from the current loop's outer flow block
  let fblock = gen.findFlowBlock({fbLoopOuter})
  if fblock == nil:
    node.error(ErrOnlyUsableInABlock % "break")
  gen.breakFlowBlock(fblock)

proc genContinue(node: Node) {.codegen.} =
  ## Generate code for a ``continue`` statement.

  # break from the current loop's iteration flow block
  let fblock = gen.findFlowBlock({fbLoopIter})
  if fblock == nil:
    node.error(ErrOnlyUsableInALoop % "continue")
  gen.breakFlowBlock(fblock)

proc genReturn(node: Node) {.codegen.} =
  ## Generate code for a ``return`` statement.

  # return is only valid in procedures, of course
  if gen.kind != gkProc:
    node.error(ErrOnlyUsableInAProc % "return")

  # for non-void returns where we don't have a
  # value specified, we return the magic 'result' variable
  # this is exactly why shadowing 'result' is prohibited
  if node[0].kind == nkEmpty:
    if gen.procReturnTy.tyKind != tyVoid:
      let resultSym = gen.lookup(newIdent("result"))
      gen.chunk.emit(opcPushL)
      gen.chunk.emit(resultSym.varStackPos.uint16)
  # otherwise if we have a value, use that
  else:
    let valTy = gen.genExpr(node[0])
    if valTy != gen.procReturnTy:
      node[0].error(ErrTypeMismatch % [$valTy.name, $gen.procReturnTy.name])

  # hayago uses two different opcodes for
  # void and non-void return, so we handle that
  if gen.procReturnTy.tyKind != tyVoid:
    gen.chunk.emit(opcReturnVal)
  else:
    gen.chunk.emit(opcReturnVoid)

proc genYield(node: Node) {.codegen.} =
  ## Generate code for a ``yield`` statement.

  # yield can only be used inside of an iterator,
  # but never in a for loop's body. using yield in a for loop's
  # body would trigger an infinite recursion, so we prevent that
  if gen.kind != gkIterator or gen.context == gen.iterForCtx:
    node.error(ErrOnlyUsableInAnIterator % "yield")

  # generate the iterator value
  let valTy = gen.genExpr(node[0])
  if not valTy.sameType(gen.iter.iterYieldTy):
    node[0].error(ErrTypeMismatch % [$valTy.name, $gen.iter.iterYieldTy.name])

  # switch context to the for loop
  let myCtx = gen.context
  gen.context = gen.iterForCtx

  # create a new iter flow block with the for loop variable
  gen.pushFlowBlock(fbLoopIter)
  var loopVar = gen.declareVar(gen.iterForVar, skLet, gen.iter.iterYieldTy)
  loopVar.varSet = true

  # run the for loop's body
  discard gen.genBlock(gen.iterForBody, isStmt = true)

  # go back to the iterator's context
  gen.popFlowBlock()
  gen.context = myCtx
  
proc genArray(node: Node, isInstantiation = false): Sym {.codegen.} =
  # process an array declaration, and add the
  # new type into the current module or scope.
  result = newType(tyArray, name = nil, impl = node)
  for n in node.children:
    result.arrayItems.add(gen.genExpr(n))
  if node.children.len > 0:
    result.arrayTy = result.arrayItems[0]
  # result.arrayTy = gen.module.sym"int"
  # emit the opcode to create an array
  # result.genericBase = some(gen.module.sym"int")
  result.genericInstArgs = some(@[result.arrayTy])
  gen.chunk.emit(opcConstrArray)
  gen.chunk.emit(uint16(result.arrayItems.len))

proc genObjectStorage(node: Node, isInstantiation = false): Sym {.codegen.} =
  # Generate code for an object storage
  result = newType(tyObject, name = nil, impl = node)
  for n in node.children:
    let valTy = gen.genExpr(n[1])
    result.objectFields[n[0].ident] = (
      id: result.objectFields.len,
      name: n[0],
      ty: valTy,
      implVal: valTy
    )
  gen.chunk.emit(opcConstrObj)
  gen.chunk.emit(uint16(result.objectFields.len))

# proc genObject(node: Node, isInstantiation = false): Sym {.codegen.} =
#   # Process an object declaration, and add the new type into the current
#   # module or scope.

#   # create a new type for the object
#   result = newType(tyObject, name = node[0], impl = node)
#   # result.impl = node

#   # check if the object is generic
#   if not isInstantiation and node[1].kind != nkEmpty:
#     # if so, create a new scope for its generic params and collect them
#     gen.pushScope()
#     result.genericParams = gen.collectGenericParams(node[1])

#   # process the object's fields
#   result.objectId = gen.script.typeCount
#   inc(gen.script.typeCount)
#   for fields in node[2]:
#     # get the fields' type
#     let
#       fieldsTy = gen.lookup(fields[^2])
#       implValSym = gen.genExpr(fields[^1])
        
#     # create all the fields with the given type
#     for name in fields[0..^3]:
#       result.objectFields[name.ident] = (
#         id: result.objectFields.len,
#         name: name,
#         ty: fieldsTy,
#         implVal: implValSym
#       )

#   # if the object had generic params, pop their scope
#   if not isInstantiation and result.isGeneric:
#     gen.popScope()
#   gen.addSym(result)

proc genIterator(node: Node, isInstantiation = false): Sym {.codegen.} =
  ## Process an iterator declaration, and add it into the current module or
  ## scope.
  var iterExport: bool
  let identNode: Node = 
    case node[0].kind
    of nkPostfix:
      assert node[0][0].ident == "*"
      iterExport = true
      node[0][1]
    else:
      node[0]

  # create a new symbol for the iterator
  result = newSym(skIterator, name = identNode, impl = node)

  # collect the generic params from the iterator into a new, temporary scope
  if not isInstantiation and node[1].kind != nkEmpty:
    gen.pushScope()
    result.genericParams = gen.collectGenericParams(node[1])

  # get some metadata about its params
  let
    formalParams = node[2]
    params = gen.collectParams(formalParams)

  # get the yield type
  if formalParams[0].kind == nkEmpty:
    node.error(ErrIterMustHaveYieldType)
  let yieldTy = gen.lookup(formalParams[0])
  if yieldTy.kind == skType and yieldTy.tyKind == tyVoid:
    node.error(ErrIterMustHaveYieldType)

  # fill in the iterator
  result.iterParams = params
  result.iterYieldTy = yieldTy
  result.iterExport = iterExport

  # remove the generic param scope
  if not isInstantiation and result.isGeneric:
    gen.popScope()

  # add the resulting iterator to the current scope
  gen.addSym(result)

proc genVar(node: Node) {.codegen.} =
  # handle variable declarations
  for decl in node:
    let implNode = decl[^1]
    if implNode.kind == nkEmpty and node.kind != nkVar:
      decl[^1].error(ErrVarMustHaveValue)
    var valTy: Sym            # the type of the value
    var valTyImpl: Sym        # the specified type of the variable (if any)
    for name in decl[0..^3]:
      # generate the value
      if implNode.kind != nkEmpty:
        # if the implicit value is not empty
        # generate the value and check its type
        valTy = gen.genExpr(implNode)
        # if both the type and the value are specified
        if decl[^2].kind != nkEmpty:
          valTyImpl = gen.lookup(decl[^2])
        else:
          valTyImpl = valTy
      elif decl[^2].kind != nkEmpty:
        # otherwise, use the provided type
        # to generate the default value
        valTyImpl = gen.lookup(decl[^2])
        gen.pushDefault(valTyImpl)
      else:
        # if neither the value nor the type is specified,
        # we emit error that the variable must have a value
        decl[^1].error(ErrTypeMismatch % ["none", "none"])
      
      # determine the variable's type based on the declaration kind
      # if the variable is declared as `var`, it is mutable
      # otherwise, it is immutable (cannot be reassigned and requires
      # an implicit value to be set)
      let varTy =
        case node.kind
        of nkVar: skVar
        of nkLet: skLet
        else: skConst
      
      # declare the variable
      var varExport: bool # whether the variable is exported
      let name = 
        if name.kind == nkPostfix and name[0].ident == "*":
          # when the variable is suffixed with a '*', it is a
          # public variable declared in the global scope
          varExport = true; name[1]
        else:
          # otherwise, we can declare it as a let or const
          name
      if valTy != nil and valTyImpl != nil:
        # before declaring the variable, we need to check if
        # the variable's type matches the expected type
        if not valTy.sameType(valTyImpl):
          decl[^1].error(ErrTypeMismatch % [$valTy.name, $valTyImpl.name])
      else:
        # if the variable's type is not specified, we can use the
        # implicit value's type as the variable's type
        valTy = valTyImpl

      # declare the variable in the current scope
      gen.declareVar(name, varTy, valTy, varExport = varExport)
      gen.popVar(name) # and pop the value into it

import ./parser
proc genImport(node: Node) {.codegen.} =
  # handle import statements
  for pathNode in node.children:
    var moduleProgram: Ast
    # todo expose a custom extension for the import
    var path = 
      if pathNode.stringVal.endsWith".timl":
        pathNode.stringVal
      else:
        pathNode.stringVal & ".timl"
    case node.kind
    of nkImport:
      parser.parseScript(moduleProgram, readFile(path))
      # initialize a new code generator for the import
      # this is a new script, so we need to initialize
      # the code generator with the new script and module
      var
        importChunk = newChunk()
        importScript = newScript(importChunk)
        importModule = newModule(path.extractFilename, some(path))

      # load the system module
      importModule.load(gen.module.modules["system.timl"])
      
      let stdpos = gen.script.stdpos
      importScript.procs = gen.script.procs[0..stdpos]
      importScript.stdpos = stdpos

      # initialize the code generator
      var moduleGen: CodeGen = initCodeGen(importScript, importModule, importChunk)
      
      # generate the module's script based
      # on the parsed module AST program
      moduleGen.genScript(moduleProgram, gen.includePath)
      
      # once the module is generated, we can load it
      # into the current module
      if not gen.module.load(moduleGen.module, fromOtherModule = true):
        node.warn(WarnModuleAlreadyImported % pathNode.stringVal)
      
      # add the module to the current script's modules
      gen.script.scripts[path] = moduleGen.script

      # emit the import opcode
      gen.chunk.emit(opcImportModule)
      gen.chunk.emit(gen.chunk.getString(path))

    of nkInclude:
      # include the module into the current script
      if gen.includePath.isSome:
        # if the include path is set, we can use it to resolve the module
        path = gen.includePath.get() / path
      parser.parseScript(moduleProgram, readFile(path))
      var
        importChunk = newChunk()
        importScript = newScript(importChunk)
        importModule = newModule(path.extractFilename, some(path))
      for n in moduleProgram.nodes:
        gen.genStmt(n)
    else: discard

proc genComment(node: Node) {.codegen.} =
  ## Generate an HTML comment.
  # this is a no-op, because comments are not compiled
  # into the final code, but they are useful for documentation
  # and debugging purposes
  # gen.chunk.emit(opcComment)
  gen.chunk.emit(gen.chunk.getString(node.comment))

proc genStmt(node: Node) {.codegen.} =
  ## Generate code for a statement.
  case node.kind
  of nkVar, nkLet, nkConst: gen.genVar(node)    # variable declaration
  of nkBlock: discard gen.genBlock(node, true)  # block statement
  of nkIf: discard gen.genIf(node, true)        # if statement
  of nkWhile: gen.genWhile(node)                # while loop
  of nkFor: gen.genFor(node)                    # for loop
  of nkBreak: gen.genBreak(node)                # break statement
  of nkContinue: gen.genContinue(node)          # continue statement
  of nkReturn: gen.genReturn(node)              # return statement
  of nkYield: gen.genYield(node)                # yield statement
  of nkProc: discard gen.genProc(node)          # procedure declaration
  of nkMacro: discard gen.genMacro(node)        # macro declaration
  of nkIterator: discard gen.genIterator(node)  # iterator declaration
  of nkObject: discard gen.genObjectStorage(node)      # object declaration
  of nkTypeDef: discard gen.genTypeDef(node)    # type definition
  of nkHtmlElement: discard gen.htmlConstr(node) # HTML element construction
  of nkJavaScriptSnippet:
    discard gen.storeJavaScript(node) # JavaScript snippet
  of nkImport, nkInclude:
    gen.genImport(node) # import statement
  of nkDocComment:
    gen.genComment(node) # generate HTML comment
  else:                                         # expression statement
    let ty = gen.genExpr(node)
    if ty != gen.module.sym"void":
      # if the expression's type is non-void, discard the result.
      # TODO: discard statement for clarity and better maintainability
      # gen.chunk.emit(opcDiscard)
      # gen.chunk.emit(1'u8)
      node.error(ErrUseOrDiscard % [node.render, $ty.name])

proc genBlock(node: Node, isStmt: bool): Sym {.codegen.} =
  # Generate a block of code. Every block creates a new scope
  gen.pushScope()
  for i, s in node:
    if isStmt:
      # if it's a statement block, generate its children normally
      gen.genStmt(s)
    else:
      # otherwise, treat the last statement as
      # an expression (and the value of the block)
      if i < node.len - 1:
        gen.genStmt(s)
      else:
        result = gen.genExpr(s)
  
  # pop the block's scope
  gen.popScope()
  
  # if it was a statement, the block's type is void
  if isStmt: result = gen.module.sym"void"
  
  if node.children.len > 0 == false:
    # warn if the block is empty. not sure if this works
    # all the time, but it should warn when node has no 
    node.warn(WarnEmptyStmt)

proc genScript*(program: Ast, includePath: Option[string],
                  isMainScript: static bool = false) {.codegen.} =
  ## Generates the code for a full script.
  gen.includePath = includePath
  when isMainScript == true:
    # when is the main script, we need to predefine
    # tim engine's global variables, `$app` and `$this`
    for id in ["app", "this"]:
      let varNode = newIdent(id)
      gen.declareVar(varNode, skLet, gen.module.sym"json")
      gen.pushDefault(gen.module.sym"json")
      gen.popVar(varNode)
  for node in program.nodes:
    gen.genStmt(node)
  gen.chunk.emit(opcHalt)

#--
# system
#--

proc hashIdentity(id: string): Hash {.inline.} =
  let id = id[0] & id[1..^1].toLowerAscii
  hashIgnoreStyle(id, 1, id.high)

proc addProc*(script: Script, module: Module, name: string,
              params: seq[TempParamDef] = @[], returnTy: TypeKind,
              impl: ForeignProc = nil, exportSym = true) =
  ## Add a foreign procedure to the given module,
  ## belonging to the given script.
  var nodeParams: seq[ProcParam]
  for param in params:
    case param.pKind
    of tyHtmlElement:
      add nodeParams, (
        newIdent(param.pName),
        module.sym(param.pKindIdent),
        # param.pImplVal,
        param.pImplSym,
        param.isMut,
        param.isOpt
      )
    else:
      add nodeParams, (
        newIdent(param.pName),
        module.sym($(param.pKind)),
        # param.pImplVal,
        param.pImplSym,
        param.isMut,
        param.isOpt
      )
  let (sym, theProc) =
    script.newProc(newIdent(name), impl = nil,
        nodeParams, module.sym($(returnTy)), pkForeign, exportSym)
  theProc.foreign = impl
  discard module.addCallable(sym, sym.name)
  # let procIdentifier: Hash = hashIdentity(name)
  # if module.functions.hasKey(procIdentifier):
  #   module.functions[procIdentifier].add(sym)
  # else:
  #   module.functions[procIdentifier] = @[sym]
  if impl != nil:
    script.procs.add(theProc)

proc paramDef*(name: string, kind: TypeKind, val: Value = nil,
        sym: Sym = nil, mut, isOpt: bool = false, kindStr = ""): TempParamDef {.inline.} =
  ## Create a new parameter definition.
  result = (name, kind, kindStr, sym, mut, isOpt)

  # for tag in tagA..tagWbr:
  #   module.add(genHtmlType(tyHtmlElement, tag))

proc addIterator*(script: Script, module: Module, name: string) =
  ## Add a foreign iterator into the specified module.
  discard # todo
