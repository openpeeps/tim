# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[macros, options, os, sequtils,
                strutils, ropes, tables]

import pkg/voodoo/language/[ast, chunk, errors, sym]

type
  GenKind = enum
    gkToplevel
    gkProc
    gkBlockProc
    gkIterator
  
  CodeGen* {.acyclic.} = object
    ## a code generator for a module or proc.
    script: Script              # the script all procs go into
    module: Module              # the global scope
    chunk: Chunk                # the chunk of code we're generating
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

const
  utilsJS = staticRead(currentSourcePath().parentDir / "tim.js")

proc initCodeGen*(script: Script, module: Module, chunk: Chunk,
        kind = gkToplevel): CodeGen =
  result = CodeGen(script: script, module: module,
                    chunk: chunk, kind: kind)

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
  theProc[3][0] = ident"Rope"
  theProc.params.insert(1,
    newIdentDefs(ident"gen", nnkVarTy.newTree(ident"CodeGen")))
  if theProc[^1].kind != nnkEmpty:
    let body = nnkStmtList.newTree(
      newAssignment( ident"result", newCall(ident"rope")),
      theProc[^1]
    )
    theProc[^1] = newCall("genGuard", body)
  result = theProc

#
# Forward declarations
#
proc genStmt(node: Node, indent: int = 0): Rope {.codegen.}

proc error*(node: Node, msg: string) =
  ## Raise a compile error on the given node.
  raise (ref CodeGenError)(
          # file: node.file,
          ln: node.ln,
          col: node.col,
          msg: ErrorFmt % ["", $node.ln, $node.col, msg]
        )

#
# Nim Transpiler
#
proc getImplValue(node: Node, unquoted = true): string =
  # Helper to render Python values from AST nodes
  case node.kind
  of nkInt:     $node.intVal
  of nkFloat:   $node.floatVal
  of nkString:  "\"" & node.stringVal & "\""
  of nkBool:
      if node.boolVal: "True" else: "False"
  else:
    "" # TODO

proc writeVar(node: Node, indent: int = 0) {.codegen.} =
  result = rope(repeat(" ", indent))
  case node.kind
  of nkVar:
    result.add("var")
  else:
    result.add("const")
    if node.children[0][^1].kind == nkEmpty:
      node.error(ErrVarMustHaveValue) # constant variables must have an initial value
  result.add(" ")
  for decl in node:
    let varName = decl[0].ident
    let value = decl[^1].getImplValue
    result.add(varName & " = " & $value & "\n")

proc renderHandle(node: Node, unquoted = true): string =
  # Render a node as a Nim expression for HTML/text output
  case node.kind
  of nkString:
    node.stringVal
  of nkInt:
    $node.intVal
  of nkFloat:
    $node.floatVal
  of nkBool:
    $node.boolVal
  of nkIdent:
    node.ident
  of nkPrefix:
    node[0].renderHandle & node[1].renderHandle
  of nkPostfix:
    node[0].renderHandle & node[1].renderHandle
  of nkInfix:
    node[1].renderHandle & ' ' & node[0].renderHandle & ' ' & node[2].renderHandle
  of nkCall:
    node[0].renderHandle & '(' & node[1..^1].mapIt(it.renderHandle).join(", ") & ')'
  else:
    ""

proc writeHtml(node: Node, indent: int = 0) {.codegen.} =
  # Write HTML as string concatenation
  let tag = node.getTag()
  var
    classNames: seq[string] = @[]
    idVal: string = ""
    customAttrs: seq[(string, string)] = @[]
  for attr in node.attributes:
    if attr.kind == nkHtmlAttribute:
      case attr.attrType
      of htmlAttrClass:
        case attr.attrNode.kind
        of nkString:
          classNames.add(attr.attrNode.stringVal)
        of nkIdent:
          classNames.add(attr.attrNode.ident)
        else:
          discard
      of htmlAttrId:
        case attr.attrNode.kind
        of nkString:
          idVal = attr.attrNode.stringVal
        of nkIdent:
          idVal = attr.attrNode.ident
        else:
          discard
      of htmlAttr:
        if attr.attrNode.kind == nkInfix:
          if attr.attrNode[2].kind == nkInfix:
            if attr.attrNode[2][0].ident == "&":
              let left = attr.attrNode[2][1]
              let right = attr.attrNode[2][2]
              let leftVal =
                if left.kind == nkString:
                  left.stringVal
                else:
                  "${" & left.renderHandle(false) & ".toString()}"
              let rightVal =
                if right.kind == nkIdent and right.ident.len > 0 and right.ident[0] == '$':
                  "${" & right.ident[1..^1] & "}"
                else:
                  (if right.kind == nkString: right.stringVal
                                        else: "${" & right.renderHandle(false) & ".toString()}")
              customAttrs.add((attr.attrNode[1].renderHandle(true), leftVal & rightVal))
          else:
            let key = attr.attrNode[1].renderHandle
            let value =
              case attr.attrNode[2].kind
              of nkIdent, nkCall:
                "#{" & attr.attrNode[2].renderHandle & "}"
              else: 
                attr.attrNode[2].renderHandle
            customAttrs.add((key, value))
        elif attr.attrNode.kind == nkString:
          customAttrs.add((attr.attrNode.stringVal, ""))
      else:
        discard
  let ind = repeat(" ", indent)
  result.add(ind & "block:\n")
  result.add(ind & "  add result, \"<" & tag)
  
  if classNames.len > 0:
    # Join class names with spaces
    result.add(" class=\\\"" & classNames.join(" ") & "\\\"")
  
  if idVal.len > 0:
    # Add id attribute if present
    result.add(" id=\\\"" & idVal & "\\\"")
  
  for (key, value) in customAttrs:
    # Add custom attributes
    if value.len > 0:
      result.add(" " & key & "=\\\"" & value & "\\\"")
    else:
      result.add(" " & key)
  result.add(">\"\n")
  for child in node.childElements:
    case child.kind
    of nkBool, nkInt, nkFloat:
      result.add(ind & "  add result, \"" & child.renderHandle & "\"\n")
    of nkString:
      result.add(ind & "  add result, \"" & child.renderHandle(true) & "\"\n")
    of nkCall:
      # handle function calls
      if child[0].ident[0] == '@':
        discard
      else:
        result.add(gen.genStmt(child, indent + 2))
    else:
      result.add(gen.genStmt(child, indent + 2))
  if node.tag notin voidHtmlElements:
    result.add(ind & "  add result, \"</" & tag & ">\"\n")


proc genStmt(node: Node, indent: int = 0): Rope {.codegen.} =
  result = rope()
  let ind = repeat(" ", indent)
  case node.kind
  of nkHtmlElement:
    result.add(gen.writeHtml(node, indent))
  of nkVar, nkLet, nkConst:
    result.add(gen.writeVar(node, indent))
  of nkCall:
    result.add(ind & node.render & "\n")
  of nkIf:
    result.add(ind & "if " & node[0].render & ": \n")
    result.add(gen.genStmt(node[1], indent + 2))
    let hasElse = node.children.len mod 2 == 1
    let elifBranches = if hasElse: node[2..^2] else: node[2..^1]
    for i in countup(0, elifBranches.len - 1, 2):
      result.add(ind & "elif " & elifBranches[i].render & ":\n")
      result.add(gen.genStmt(elifBranches[i + 1], indent + 2))
    if hasElse:
      result.add(ind & "else:\n")
      result.add(gen.genStmt(node[^1], indent + 2))
  of nkFor:
    let varName = node[0].render
    let iterable = node[1]
    if iterable.kind == nkInfix and iterable[0].kind == nkIdent and iterable[0].ident == "..":
      # Range: 0..3
      let startVal = iterable[1].render
      let endVal = iterable[2].render
      result.add(ind & "for " & varName & " in " & startVal & ".. " & endVal & ":\n")
      result.add(gen.genStmt(node[2], indent + 2))
    else:
      result.add(ind & "for " & varName & " in " & iterable.render & ":\n")
      result.add(gen.genStmt(node[2], indent + 2))
  of nkProc:
    # Function declaration with TypeDoc
    let fnName = node[0].render
    let params = node[2]
    let retType = if node[2][0].kind != nkEmpty: node[2][0].render else: "void"
    result.add(ind & "proc " & fnName & "(")
    result.add(params[1..^1].mapIt(it[0].render).join(", "))
    result.add("): $1 = \n" % retType)
    result.add(gen.genStmt(node[3], indent + 2))
  of nkMacro:
    let fnName = node[0].ident[1..^1]
    let params = node[2]
    result.add(ind & "proc " & fnName & "(")
    result.add(params[1..^1].mapIt(it[0].render).join(", "))
    result.add("): string =\n")
    result.add(gen.genStmt(node[3], indent + 2))
    result.add(ind & "  move(result)\n")
  of nkBlock:
    for s in node:
      result.add(gen.genStmt(s, indent))
  of nkReturn:
    if node[0].kind != nkEmpty:
      result.add(ind & "return " & node[0].render & "\n")
    else:
      result.add(ind & "return\n")
  of nkBreak:
    result.add(ind & "break\n")
  of nkContinue:
    result.add(ind & "continue\n")
  of nkWhile:
    result.add(ind & "while " & node[0].render & ":\n")
    result.add(gen.genStmt(node[1], indent + 2))
  else: discard

proc genScript*(program: Ast, includePath: Option[string],
            isMainScript: static bool = false,
            isSnippet: static bool = false) {.codegen.} =
  ## Generates a Nim script from the given AST `program`.
  result.add("import std/[json]\n\n")
  result.add("proc get$1View*(layout: string = \"base\", local: JsonNode = newJObject()): string =\n" % gen.module.getModuleName())
  result.add("  ## HTML template render function for rendering the $1 \n" % gen.module.getModuleName())
  for node in program.nodes:
    result.add(gen.genStmt(node, 2))
  result.add("  move(result)")

