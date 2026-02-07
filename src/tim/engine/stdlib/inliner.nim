import std/options
import pkg/voodoo/language/[chunk, codegen, ast, sym, value]
import ../parser

type
  TempParamDef* = tuple
    pName: string
    pKind: TypeKind
    pKindIdent: string
    pImplSym: Sym
    isMut, isOpt: bool

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
        param.pImplSym,
        param.isMut,
        param.isOpt
      )
    else:
      let paramSym = 
        if param.pImplSym != nil:
          # if the parameter has an implementation value, use its type
          param.pImplSym
        else:
          module.sym($param.pKind)
      add nodeParams, (
        newIdent(param.pName),
        paramSym,
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
                sym: Sym = nil, mut, isOpt: bool = false, kindStr = ""
          ): TempParamDef {.inline.} =
  ## Create a new parameter definition.
  result = (name, kind, kindStr, sym, mut, isOpt)


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