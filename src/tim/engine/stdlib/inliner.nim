import std/options
import pkg/voodoo/language/[chunk, codegen, ast, sym, value]
import ../parser

type
  TempParamDef* = tuple
    pName: string
      # the name of the parameter, used for error messages and stuff
    pKind: TypeKind
      # the type of the parameter, used for type checking and codegen
    pKindIdent: string
      # the identifier of the parameter type, used for codegen
    pImplSym: Sym
      # the symbol of the parameter implementation, used for codegen
    isMut, isOpt: bool
      # whether the parameter is mutable or optional, used for codegen
    val: Value
      # the default value of the parameter, used for optional parameters

proc toStackView(vals: var seq[Value]): StackView {.inline.} =
  ## seq[Value] -> StackView (ptr UncheckedArray[Value])
  if vals.len == 0:
    return cast[StackView](nil)
  cast[StackView](vals[0].addr)


proc defaultNodeFromValue(v: Value): Node =
  ## Converts runtime Value -> AST literal for default parameter codegen.
  if v == nil: return ast.newNode(nkNil)
  case v.typeId
  of tyBool:
    result = ast.newNode(nkBool)
    result.boolVal = v.boolVal
  of tyInt:
    result = ast.newNode(nkInt)
    result.intVal = v.intVal
  of tyFloat:
    result = ast.newNode(nkFloat)
    result.floatVal = v.floatVal
  of tyString:
    result = ast.newNode(nkString)
    result.stringVal = v.stringVal[]
  of tyNil:
    result = ast.newNode(nkNil)
  else:
    # Unsupported as compile-time default literal in bridge path
    result = nil

proc applyDefaults(args: StackView, argc: int, params: seq[TempParamDef]): seq[Value] =
  result = newSeqOfCap[Value](params.len)

  for i in 0..<argc:
    result.add(args[i])

  if result.len < params.len:
    for i in result.len..<params.len:
      if params[i].val != nil:
        result.add(params[i].val)
        echo params[i].val
      else:
        raise newException(ValueError, "missing required argument: " & params[i].pName)


proc addProc*(script: Script, module: Module, name: string,
              params: seq[TempParamDef] = @[], returnTy: TypeKind,
              impl: ForeignProc = nil, exportSym = true) =
  var nodeParams: seq[ProcParam]

  for raw in params:
    var param = raw
    let paramTy =
      case param.pKind
      of ttyHtmlElement: module.sym(param.pKindIdent)
      else: module.sym($param.pKind)

    # If a default Value is provided, expose it through implSym.impl
    # so callProc -> genExpr(...) pushes that exact value.
    if param.val != nil and param.pImplSym == nil:
      let n = defaultNodeFromValue(param.val)
      if n != nil:
        param.pImplSym = newSym(
          skConst,
          ast.newIdent("__default_" & param.pName),
          impl = n
        )

    let optional = param.isOpt or param.val != nil

    nodeParams.add((
      ast.newIdent(param.pName),
      paramTy,
      param.pImplSym,
      param.isMut,
      optional
    ))

  let (sym, theProc) =
    script.newProc(
      ast.newIdent(name),
      impl = nil,
      nodeParams,
      module.sym($returnTy),
      pkForeign,
      exportSym
    )

  theProc.foreign = impl
  discard module.addCallable(sym, sym.name)
  if impl != nil:
    script.procs.add(theProc)

proc paramDef*(name: string, kind: TypeKind, val: Value = nil,
                sym: Sym = nil, mut, isOpt: bool = false, kindStr = ""
          ): TempParamDef {.inline.} =
  ## Create a new parameter definition.
  result = (name, kind, kindStr, sym, mut, (isOpt or val != nil), val)

proc compileCode*(script: Script, module: Module, filename, code: string) =
  ## Compile some hayago code to the given script and module.
  ## Any generated toplevel code is discarded. This should only be used for
  ## declarations of hayago-side things, eg. iterators.
  var astProgram: Ast
  try:
    parser.parseScript(astProgram, code, "std/system/inline")
  except TimParserError as e:
    echo e.msg
    quit(1)
  try:
    # var codeChunk = newChunk()
    var gen = initCodeGen(script, module, script.mainChunk)
    gen.genScript(astProgram, none(string), emitHalt = false)
  except CodeGenError as e:
    echo e.msg
    quit(1)

const
  Globals* = """
const app* = parseJSON('$globalData')
"""

  InlineCode* = """
iterator `..`*(min: int, max: int): int {
  var i = $min
  if $i >= $max:
    yield($min)
  else:
    while $i <= $max:
      yield($i)
      inc($i)
}

iterator items*(data: json): json {
  var i = 0
  const total = len($data)
  while $i < $total {
    yield($data[$i])
    inc($i)
  }
}


iterator items*(arr: array[object]): object {
  var i = 0
  const total = high($arr)
  while $i <= $total {
    yield($arr[$i])
    inc($i)
  }
}

iterator items*(arr: array[string]): string {
  var i = 0
  const total = high($arr)
  while $i <= $total {
    yield($arr[$i])
    inc($i)
  }
}

iterator items*(arr: array[int]): int {
  var i = 0
  const total = high($arr)
  while $i <= $total {
    yield($arr[$i])
    inc($i)
  }
}
"""