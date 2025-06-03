# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://tim-engine.com

import std/[tables, json, hashes, options, sequtils, strutils]
import ./[ast, value]

type
  Context* = distinct uint16
    ## A scope context.

  Scope* {.acyclic.} = ref object of RootObj
    ## A local scope.
    syms*: Table[string, Sym]
    exportSyms*: Table[string, Sym]
      ## A table of exported symbols
    otherSyms*: Table[string, Sym]
      ## A table of symbols imported from other modules
      
    variables*, exportVariables*: Table[string, Sym]
      ## A table of variables. This is used for fast lookups of variables
      ## in the current scope. The key is the hash of the variable's name.
    functions*, exportFunctions*: Table[string, Sym]
      ## A table of functions. This is used for fast lookups of functions
      ## in the current scope.
    typeDefs*, exportTypeDefs*: Table[string, Sym]
      ## A table of type definitions. This is used for fast lookups of type
      ## definitions in the current scope.
    context*: Context
      ## the scope's context. this is used for scope hygiene
  
  Module* {.acyclic.} = ref object of Scope
    ## A module representing the global scope of a single source file.
    name*: string  ## the name of the module
    src*: Option[string]
      ## the source file where the module was defined
      ## this is used for type checking and error reporting
    modules*: Table[string, Module]
      ## a table of modules imported by this module
      ## where the key is the path to the module

  SymKind* = enum
    ## The kind of a symbol.
    skVar = "var"
    skConst = "const"
    skLet = "let"
    skType = "type"
    skProc = "fn"
    skIterator = "iterator"
    skGenericParam = "generic param"
    skHtmlType = "html"
    skChoice = "(...)"  ## an overloaded symbol, stores many symbols with \
                        ## the same name

  TypeKind* = enum
    ## The kind of a type.
    # meta-types
    tyVoid = "void"      # matches no types
    tyAny = "any"        # matches any and all types

    # concrete types
    tyBool = "bool"
    tyInt = "int"        # int64
    tyFloat = "float"    # float64
    tyString = "string"  # ref string
    tyJson = "json"
    tyArray = "array"
    
    tyNil = "nil"        # matches nil

    # user-defined types
    tyObject = "object"
    tyAlias = "alias"
    tyCustom = "custom"
      # a user-defined type that doesn't have a
      # special representation in the VM
    tyHtmlElement = "HtmlElement"

  Sym* {.acyclic.} = ref object
    ## A symbol. This represents an ident that can be looked up.
    name*: Node  ## the name of the symbol
    impl*: Node  ## the implementation of the symbol. may be ``nil`` if the symbol is generated
    src*: Option[string]
      ## the source file where the symbol was defined
      ## this is used for type checking and error reporting
    case kind*: SymKind
    of skVar, skLet, skConst:
      varTy*: Sym        ## the type of the variable
      varSet*: bool      ## is the variable set?
      varLocal*: bool    ## is the variable local?
      varStackPos*: int  ## the position of this local variable on the stack
      varExport*: bool   ## whether the variable is exported or not
    of skType:
      typeExport*: bool
        ## This is used to determine whether the type
        ## can be used in other modules or not.
      case tyKind*: TypeKind
      of tyNil: discard # nil is a special case
      of tyVoid..tyJson:
        isMutable*: bool
      of tyArray:
        arrayTy*: Sym
          ## the type of the array
        arrayMutable*: bool
          ## used to determine whether the array is mutable or not
        arrayItems*: seq[Sym]
          ## the items of the array
      of tyObject:
        objectId*: TypeId
        objectFields*: Table[string, ObjectField]
      of tyAlias:
        aliasId*: TypeId
        aliasTy*: Sym
      of tyCustom:
        discard # todo
      of tyHtmlElement: discard
    of skHtmlType:
      tag*, innerText*: string
      isVoidElement*: bool
    of skProc:
      procId*: uint16              ## the unique number of the proc
      procParams*: seq[ProcParam]  ## the proc's parameters
      procReturnTy*: Sym           ## the return type of the proc
      procExport*: bool
        ## whether the proc is exported or not
    of skIterator:
      iterParams*: seq[ProcParam]  ## the iterator's parameters
      iterYieldTy*: Sym            ## the yield type of the iterator
      iterExport*: bool
        ## whether the iterator is exported or not
    of skGenericParam:
      constraint*: Sym  ## the generic type constraint
    of skChoice:
      choices*: seq[Sym]
    genericParams*: Option[seq[Sym]]
      # some if the sym is generic
    genericInstCache*: Table[seq[Sym], Sym]
    genericBase*: Option[Sym]
      # contains the base generic type if the
      # sym is an instantiation
    genericInstArgs*: Option[seq[Sym]]
      # some if the sym is an instantiation

  ObjectField* = tuple
    id: int     # every object field has an id that's used for lookups on
                # runtime. this id is simply a seq index so field lookups are
                # fast
    name: Node  # the name of the field
    ty: Sym     # the type of the field
    implVal: Sym

  # ArrayItem* = tuple
  #   id: int     # the id of the item
  #   valSym: Sym

  ProcParam* = tuple
    ## A single param of a proc.
    name: Node
    ty: Sym
    implSym: Sym
    isMut: bool
    isOpt: bool

  ArgTuple* = tuple
    sym: Sym
    exprSym: Sym

    # TODO: default param values

  TimCompileError* = object of ValueError
    file*: string
    ln*, col*: int

const
  skVars* = {skVar, skLet, skConst}
  skCallable* = {skProc, skIterator}
  skDecl* = {skType} + skCallable + skVars
  skTyped* = {skType, skHtmlType, skGenericParam}

  tyPrimitives* = {tyVoid..tyString}
  tyMeta* = {tyVoid, tyAny}

proc `==`*(a, b: Context): bool {.borrow.}

proc clone*(sym: Sym): Sym =
  ## Clones a symbol, returning a newly allocated instance with the same fields.
  new(result)
  result[] = sym[]

proc params*(sym: Sym): seq[ProcParam] =
  ## Get the proc/iterator's params.
  assert sym.kind in skCallable
  case sym.kind
  of skProc: result = sym.procParams
  of skIterator: result = sym.iterParams
  else: discard

proc returnTy*(sym: Sym): Sym =
  ## Get the proc/iterator's return or yield type.
  assert sym.kind in skCallable
  case sym.kind
  of skProc: result = sym.procReturnTy
  of skIterator: result = sym.iterYieldTy
  else: discard

proc `$`*(sym: Sym): string

proc `$`*(params: seq[ProcParam]): string =
  ## Stringify a seq of proc parameters.
  result = "("
  for i, param in params:
    result.add($param.name & ": ")

    # mutable parameters are prefixed with a `var
    if param.isMut: result.add($skVar & " ")

    result.add($param.ty) # add the type

    # if param.ty.name.ident == "any":
      # temp. fix this!
      # if param.implVal == nil:
      #   result.add(" = nil")
    if i != params.len - 1: result.add(", ") # add comma, move to next param
  result.add(")")

proc `$`*(sym: Sym): string =
  ## Stringify a symbol in a user-friendly way.
  case sym.kind
  of skVar, skLet, skConst:
    # we don't have a runtime value for the variable,
    # so we just show the name and the type
    result =
      if sym.kind == skVar: "var "
      else: "let "
    result.add(sym.name.render)
    result.add(": ")
    result.add($sym.varTy)
  of skType:
    case sym.tykind
    of tyArray:
      # assert sym.arrayTy != nil, "array type must have a type"
      result = "array["
      if sym.arrayTy != nil:
        result.add(sym.arrayTy.name.render)
      else:
        if sym.genericInstArgs.isSome:
          result.add(sym.genericInstArgs.get()[0].name.render)
      result.add("]")
    else:
      result = sym.name.render
      if sym.genericInstArgs.isSome:
        result.add('[' & sym.genericInstArgs.get.join(", ") & ']')
  of skGenericParam:
    result = sym.name.render
    if sym.constraint != nil:
      if sym.constraint.name.ident != "any":
        result.add(": " & $sym.constraint)
  of skCallable:
    result =
      if sym.kind == skProc:
        if sym.name.ident.startsWith("@"): "block "
        else: $skProc & " "
      else: "iterator "
    result.add(sym.name.render)
    if sym.genericParams.isSome or sym.genericInstArgs.isSome:
      # let genericParams =
      #   sym.genericParams.get(otherwise = sym.genericInstArgs.get)
      # result.add('[' & genericParams.join(", ") & ']')
      let genericParams = sym.genericParams.get()
      result.add('[' & genericParams.join(", ") & ']')
    result.add($sym.params)
    case sym.returnTy.kind
    of skType:
      if sym.returnTy.tyKind != tyVoid:
        result.add(": ")
        result.add($sym.returnTy)
    of skGenericParam:
      result.add(": ")
      result.add($sym.returnTy.name)
    else: discard # error?
  of skChoice:
    result = sym.choices.join("\n").indent(2)
  else: discard

# proc `$$`*(sym: Sym): string =
#   ## Stringify a symbol verbosely for debugging purposes.
#   case sym.kind
#   of skVar, skLet, skConst:
#     result = $(sym.kind) & " of type " & sym.varTy.name.ident
#   of skType:
#     result = "type"
#     if sym.genericParams.isSome:
#       result.add('[')
#       result.add(sym.genericParams.get.join(", "))
#       result.add(']')
#     result.add(" = ")
#     case sym.tyKind
#     of tyPrimitives: result.add($sym.tyKind)
#     of tyObject:
#       result.add("object {")
#       for name, field in sym.objectFields:
#         result.add(" " & name & ": " & $field.ty.name & ";")
#       result.add(" }")
#     of tyAlias:
#       discard # todo
#     of tyCustom:
#       discard # todo
#     of tyJson:
#       discard
#     of tyHtmlElement: discard # todo
#   of skProc:
#     result = "proc " & $sym.name & "{" & $sym.procId & "}" & $sym.procParams
#   of skIterator:
#     result = "iterator " & $sym.name & $sym.iterParams
#   of skGenericParam:
#     result = $sym.name
#     if sym.constraint != nil:
#       result.add(": " & $sym.constraint)
#   of skChoice:
#     result = "choice between " & $sym.choices.len & " {"
#     for choice in sym.choices:
#       result.add(" " & $choice & ",")
#     result.add(" }")

proc isGeneric*(sym: Sym): bool =
  ## Returns whether the symbol is generic or not.
  ## A symbol is generic if it has generic params or *is* a generic param.
  (sym.genericParams.isSome or sym.kind == skGenericParam) and
  sym.genericBase.isNone

proc isInstantiation*(sym: Sym): bool =
  ## Returns whether the symbol is an instantiation.
  result = sym.genericBase.isSome

proc hash*(sym: Sym): Hash =
  ## Hashes a sym (for use in Tables).

  # we don't do any special hashing, just hash it by instance to make sure that
  # even if there are two symbols named the same, they'll stay different when
  # used in table lookups

  # side note: this efficient hashing of integers that Nim claims to provide
  # is just converting the int to a Hash (which is a distinct int) :)
  result = hash(cast[int](sym))

proc newSym*(kind: SymKind, name: Node, impl: Node = nil): Sym =
  ## Create a new symbol from a Node.
  result = Sym(name: name, impl: impl, kind: kind)

proc newType*(kind: TypeKind, name: Node, impl: Node = nil): Sym =
  ## Create a new type symbol from a Node.
  result = Sym(name: name, impl: impl, kind: skType, tyKind: kind)

proc genType*(kind: TypeKind, name: string, exportSym: bool,
      genericParams: Option[seq[Sym]] = none(seq[Sym])): Sym =
  ## Generate a new type symbol from a string name.
  result = Sym(
    name: newIdent(name),
    kind: skType,
    tyKind: kind,
    typeExport: exportSym
  )
  if genericParams.isSome:
    result.genericParams = genericParams

proc genHtmlType*(kind: TypeKind, tag: HtmlTag): Sym =
  ## Generate a new type symbol from a string name
  result = Sym(
    name: newIdent($tag),
    kind: skHtmlType,
    isVoidElement: tag in voidHtmlElements
  )

proc sameType*(a, b: Sym): bool =
  ## Returns ``true`` if ``a`` and ``b`` are are compatible types.
  assert a.kind in skTyped + skVars and b.kind in skTyped + skVars,
    "type comparison can't be done on non-type symbols"

  # make them mutable for the next segment
  var (a, b) = (a, b)

  # if b is a variable, we need to check the type of the variable
  # instead of the variable itself
  if b.kind in skVars:
    b = b.varTy

  if a.kind in skVars:
    a = a.varTy

  # handle generic params as a special case,
  # because they're a different kind of a symbol
  if a.kind == skGenericParam: a = a.constraint
  if b.kind == skGenericParam: b = b.constraint

  # ``any`` is a special case: it matches literally any type
  case a.kind
  of skType:
    case b.kind
    of skHtmlType:
      return a.tyKind == tyAny
    else:
      if a.tyKind == tyAny or b.tyKind == tyAny:
        return true
  else: discard

  # as for other types: if they're not generic,
  # we simply check if the symbols are equal
  if not a.isInstantiation and not b.isInstantiation:
    case a.kind
    of skHtmlType:
      return b.kind == skHtmlType
    else:
      return a.tyKind == b.tyKind

  else:
    # otherwise, we check the base type,
    # and the generic params for equivalence
    
    # an generic type referenced somewhere in code cannot possibly pass
    # ``isGeneric``, because all symbols are instantiated on lookup
    # echo a
    # echo b
    # assert not a.isGeneric and not b.isGeneric,
    #   "type somehow is generic even though it was instantiated"

    # both types have to be instantiations to be
    # equivalent, but this limitation may be lifted at some point
    # if not a.isInstantiation and b.isInstantiation or
    #    a.isInstantiation and not b.isInstantiation:
    #   return false
    # echo a
    # echo b.isInstantiation
    if a.isInstantiation and b.isInstantiation == false:
      if b.genericInstArgs.isSome:
        if a.kind == b.kind:
          result = true
          let bArgs = b.genericInstArgs.get
          for i, arg in a.genericInstArgs.get:
            result = result and arg.sameType(bArgs[i])
            if result == false: break
          return result
        return false
      else:
        result = true
        for i, arg in a.genericInstArgs.get:
          result = result and arg.sameType(b)
          if result == false: break
        return # result
    
    if a.genericInstArgs.isNone and b.genericInstArgs.isSome:
      # echo a
      # echo b
      # echo a.genericInstArgs.isSome()
      # echo b.genericInstArgs.isSome()
      return false

    # likewise, both types have to have the same amount of generic arguments
    # if a.genericInstArgs.get.len != b.genericInstArgs.get.len:
    #   return false

    # in the end, we check if the base types are
    # equivalent and the parameters are equivalent
    result = a.genericBase.get.sameType(b.genericBase.get)
    for i, arg in a.genericInstArgs.get:
      result = result and arg.sameType(b.genericInstArgs.get[i])
      if result == false: break

proc sameParams*(sym: Sym, args: seq[Sym]): bool =
  ## Returns ``true`` if both ``a`` and ``b`` are called with the same
  ## parameters.
  assert sym.kind in skCallable, "symbol must be callable: " & $skCallable

  if args.len > sym.params.len: return # false
  
  for i, param in sym.params:
    try:
      if not param.ty.sameType(args[i]):
        return false
    except IndexDefect:
      if param.isOpt == false:
        return false
        
  result = true
  # if param.isMut and args[i].kind != skVar:
  #   return false

proc sameParams*(a, b: Sym): bool =
  ## Overload of ``sameParams`` for two symbols.
  assert b.kind in skCallable, "symbol must be callable: " & $skCallable
  result = a.sameParams(b.params.mapIt(it.ty))

proc canAdd*(choice, sym: Sym): bool =
  ## Tests if ``sym`` can be added into ``choice``. Refer to ``add``
  ## documentation below for details.
  assert choice.kind == skChoice
  if sym.kind notin skDecl: return false
  case sym.kind
  of skVars:
    result = choice.choices.allIt(it.kind notin skVars)
  of skType:
    result = choice.choices.allIt(it.kind != skType)
  of skCallable:
    result = choice.choices.allIt(not sym.sameParams(it))
  of skHtmlType:
    result = choice.choices.allit(it.kind != skHtmlType)
  of skGenericParam, skChoice: discard

proc canExport(sym: Sym): bool =
  ## Returns ``true`` if the symbol can be exported.
  ## This is used to determine whether the symbol can be
  ## used in other modules or not.
  result = 
    case sym.kind
    of skVar, skLet, skConst:
      sym.varExport
    of skType:
      sym.typeExport
    of skProc:
      sym.procExport
    of skIterator:
      sym.iterExport
    else: false

proc addVariable*(scope: Scope, sym: Sym, lookupName: Node, fromOtherModule: static bool = false): bool {.discardable.} =
  ## Add a variable to the given scope.
  if not scope.variables.hasKey(lookupName.ident):
    scope.variables[lookupName.ident] = sym
    # scope.syms[lookupName.ident] = sym # todo remove `syms`
    when fromOtherModule == false:
      if sym.canExport():
        # add the symbol to the export table so it can be used
        # in other modules that import this module
        scope.exportVariables[lookupName.ident] = sym
    return true

proc addCallable*(scope: Scope, sym: Sym, lookupName: Node, fromOtherModule: static bool = false): bool {.discardable.} =
  ## Add a callable to the given scope.
  if not scope.functions.hasKey(lookupName.ident):
    scope.functions[lookupName.ident] = sym
    when fromOtherModule == false:
      if sym.canExport():
        # just like with variables, if a function is suffixed with `*`,
        # it will be available in other modules that import this module
        scope.exportFunctions[lookupName.ident] = sym
    return true

  # otherwise, add it to a shared 'choice' symbol
  # if an overload with the same name doesn't already exist
  let other = scope.functions[lookupName.ident]
  if other.kind != skChoice:
    var choice = newSym(skChoice, other.name)
    choice.choices.add(other)
    scope.functions[lookupName.ident] = choice
    when fromOtherModule == false:
      if sym.canExport():
        if scope.exportFunctions[lookupName.ident].kind != skChoice:
          scope.exportFunctions[lookupName.ident] = choice

  if scope.functions[lookupName.ident].canAdd(sym):
    scope.functions[lookupName.ident].choices.add(sym)
    # scope.syms[lookupName].choices.add(sym) # todo remove `syms`
    when fromOtherModule == false:
      if sym.canExport():
        scope.exportFunctions[lookupName.ident].choices.add(sym)
    return true

proc addType*(scope: Scope, sym: Sym, lookupName: Node, fromOtherModule: static bool = false): bool {.discardable.} =
  ## Add a type to the given scope.
  if not scope.typeDefs.hasKey(lookupName.ident):
    scope.typeDefs[lookupName.ident] = sym
    scope.syms[lookupName.ident] = sym # todo remove `syms`
    when fromOtherModule == false:
      if sym.canExport(): # export the type as well
        scope.exportTypeDefs[lookupName.ident] = sym
    return true

proc add*(scope: Scope, sym: Sym, lookupName: Node = nil, fromOtherModule: static bool = false): bool {.discardable.} =
  ## Add a symbol to the given scope. If a symbol under the given name already
  ## exists, it's added into an skChoice. The rules for overloading are:
  ## - there may only be one skVar or skLet under a given skChoice,
  ## - there may only be one skType under a given skChoice,
  ## - there may be any number of skProcs with unique parameters under a
  ##   single skChoice.
  ## If any one of these checks fails, the proc will return ``false``.
  ## These checks will probably made more strict in the future.

  # this proc can override the name of the ident. this is used for generic
  # instantiations to make type aliases under the names of the generic
  # parameters
  let name =
    if lookupName == nil: sym.name
    else: lookupName

  case sym.kind
  of skVars:
    return addVariable(scope, sym, name, fromOtherModule)
  of skCallable:
    return addCallable(scope, sym, name, fromOtherModule)
  of skType:
    return addType(scope, sym, name, fromOtherModule)
  of skGenericParam:
    if not scope.variables.hasKey(lookupName.ident):
      scope.variables[lookupName.ident] = sym
      # scope.syms[lookupName.ident] = sym # todo remove `syms`
      # if sym.canExport(): # export the type as well
      #   scope.exportTypeDefs[lookupName.ident] = sym
      return true
  else: discard # todo

proc `$`*(scope: Scope): string =
  ## Stringifies a scope.
  ## This is only really useful for debugging.
  for name, sym in scope.syms:
    result.add("\n  ")
    result.add(name)
    result.add(": ")
    # result.add($$sym)

proc `$`*(module: Module): string =
  ## Stringifies a module.
  ## This is only really useful for debugging.
  result = "module " & module.name & ":" & $module.Scope

proc sym*(module: Module, name: string): Sym =
  ## Get the symbol ``name`` from a module.
  result = module.syms[name]

proc load*(module: Module, other: Module, fromOtherModule: static bool = false): bool {.discardable.} =
  ## Import public symbols from `other` into `module`
  ## If the module is already imported it will return `false`
  let otherModulePath = other.src.get()
  if module.modules.hasKey(otherModulePath):
    return # false
  for k, sy in other.exportTypeDefs:
    discard module.addType(sy, sy.name, fromOtherModule)
  for k, sy in other.exportVariables:
    discard module.addVariable(sy, sy.name, fromOtherModule)
  for k, sy in other.exportFunctions:
    discard module.addCallable(sy, sy.name, fromOtherModule)
  module.modules[otherModulePath] = other
  result = true

proc newModule*(name: string,
        src: Option[string] = none(string)): Module =
  ## Initialize a new module.
  result = Module(name: name, src: src)

proc initSystemTypes*(module: Module) =
  ## Add primitive types into the module.
  ## This should only ever be called when creating the ``system`` module.
  for kind in tyPrimitives:
    let name = $kind
    module.add(genType(kind, name, true))

  let genT = ast.newIdent("T")
  let genArrayType = newSym(skGenericParam, genT, impl = genT)
  genArrayType.constraint = module.sym"any"
  module.add(genType(tyArray, "array", true, some(@[genArrayType])))
  module.add(genType(tyJson, "json", true))