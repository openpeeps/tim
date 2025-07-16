# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://tim-engine.com

import std/[macros, options, os, hashes,
        sequtils, strutils, ropes, tables, re]

import ../[ast, chunk, errors, sym, value]

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
proc genStmt(node: Node, indent: int = 0) {.codegen.}

#
# PHP Transpiler
#

const 
  phpVar = "$"
  phpLet = "$"
  phpConst = "const"
  phpAssign = "$1 = $2;"
  phpFunc = "function $1($2) {\n$3\n}"

proc getImplValue(node: Node, unquoted = true): string =
  # Helper to render PHP values from AST nodes
  case node.kind
  of nkInt:     $node.intVal
  of nkFloat:   $node.floatVal
  of nkString: 
    if unquoted: "\"" & node.stringVal & "\""
    else: node.stringVal
  of nkBool:
    $node.boolVal
  of nkArray:
    # Render array as PHP array
    "[" & node.children.mapIt(getImplValue(it)).join(", ") & "]"
  of nkObject:
    # Render object as PHP associative array
    "[" & node.children.mapIt(
      if it.kind == nkIdentDefs:
        let key = it[0].render
        let value = getImplValue(it[^1])
        "'" & key & "' => " & value
      else:
        ""
    ).join(", ") & "]"
  else: ""

proc writeVar(node: Node) {.codegen.} =
  # Write variable declaration (PHP $var)
  # var prefix: string
  # case node.kind
  # of nkVar, nkLet:
  #   prefix = phpVar
  # else:
    # result.add(phpConst & " ")
  for decl in node:
    result.add(phpVar & decl[0].ident & " = " & decl[^1].getImplValue & ";\n")

proc renderHandle(node: Node): string =
  # Render a node as a PHP expression for HTML/text output
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
    if node.ident notin ["==", "!=", ">", "<", ">=", "<="]:
      phpVar & node.ident
    else:
      # For operators, just return the ident
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

proc repeatStr(s: string, n: int): string =
  for i in 0..<n:
    result.add(s)

proc writeHtml(node: Node, indent: int = 0) {.codegen.} =
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
        assert attr.attrNode.kind == nkInfix, "attribute node must be an infix. Got " & $(attr.attrNode.kind)
        let key = attr.attrNode[1].renderHandle
        let value = attr.attrNode[2].renderHandle
        customAttrs.add((key, value))
      else:
        discard
  let ind = repeatStr("  ", indent)
  result.add(ind & "{\n")
  result.add(ind & "  $html .= \"<" & tag)
  if classNames.len > 0:
    result.add(" class=\\\"" & classNames.join(" ") & "\\\"")
  if idVal.len > 0:
    result.add(" id=\\\"" & idVal & "\\\"")
  for (key, value) in customAttrs:
    result.add(" " & key & "=\\\"" & value & "\\\"")
  result.add(">\";\n")
  for child in node.childElements:
    case child.kind
    of nkBool, nkInt, nkFloat, nkString:
      result.add(ind & "  $html .= '" & child.getImplValue(false) & "';\n")
    of nkCall:
      if child[0].ident.len > 0 and child[0].ident[0] == '@':
        discard
      else:
        result.add(gen.genStmt(child, indent + 2))
    of nkInfix:
      # Handle infix expressions
      result.add(ind & "  $html .= " & child.renderHandle() & ";\n")
    else:
      result.add(gen.genStmt(child, indent + 2))
  if node.tag notin voidHtmlElements:
    result.add(ind & "  $html .= \"</" & tag & ">\";\n")
  result.add(ind & "}\n")

proc genStmt(node: Node, indent: int = 0): Rope {.codegen.} =
  result = Rope()
  let ind = repeatStr("  ", indent)
  case node.kind
  of nkVar, nkLet, nkConst:
    for decl in node:
      let varName = decl[0].ident
      let varType = if decl[1].kind != nkEmpty: decl[1].render else: "mixed"
      result.add(ind & "// @var $" & varName & ": " & varType & "\n")
      result.add(ind & gen.writeVar(node))
  of nkProc:
    let fnName = node[0].render
    let params = node[2]
    let retType = if node[2][0].kind != nkEmpty: node[2][0].render else: "mixed"
    result.add(ind & "/**\n")
    for param in params[1..^1]:
      if param.kind == nkIdentDefs:
        let pname = param[0].render
        let ptype = if param[1].kind != nkEmpty: param[1].render else: "mixed"
        result.add(ind & " * @param " & ptype & " $" & pname & "\n")
    result.add(ind & " * @return " & retType & "\n")
    result.add(ind & " */\n")
    result.add(ind & "function " & fnName & "(")
    result.add(params[1..^1].mapIt("$" & it[0].render).join(", "))
    result.add(") {\n")
    result.add(gen.genStmt(node[3], indent + 1))
    result.add(ind & "}\n")
  of nkMacro:
    let fnName = node[0].ident[1..^1]
    let params = node[2]
    result.add(ind & "/**\n")
    for param in params[1..^1]:
      if param.kind == nkIdentDefs:
        let pname = param[0].render
        let ptype = if param[1].kind != nkEmpty: param[1].render else: "mixed"
        result.add(ind & " * @param " & ptype & " $" & pname & "\n")
    result.add(ind & " * @return string HTML\n")
    result.add(ind & " */\n")
    result.add(ind & "function " & fnName & "(")
    result.add(params[1..^1].mapIt("$" & it[0].render).join(", "))
    result.add(") {\n")
    result.add(ind & "  $html = \";\n")
    result.add(gen.genStmt(node[3], indent + 1))
    result.add(ind & "  return $html;\n")
    result.add(ind & "}\n")
  of nkHtmlElement:
    result.add(gen.writeHtml(node, indent))
  of nkIf:
    result.add(ind & "if (" & node[0].render & ") {\n")
    result.add(gen.genStmt(node[1], indent + 1))
    result.add(ind & "}\n")
    let hasElse = node.children.len mod 2 == 1
    let elifBranches = if hasElse: node[2..^2] else: node[2..^1]
    for i in countup(0, elifBranches.len - 1, 2):
      result.add(ind & "else if (" & elifBranches[i].render & ") {\n")
      result.add(gen.genStmt(elifBranches[i + 1], indent + 1))
      result.add(ind & "}\n")
    if hasElse:
      result.add(ind & "else {\n")
      result.add(gen.genStmt(node[^1], indent + 1))
      result.add(ind & "}\n")
  of nkFor:
    let varName = node[0].render
    let iterable = node[1]
    if iterable.kind == nkInfix and iterable[0].kind == nkIdent and iterable[0].ident == "..":
      let startVal = iterable[1].render
      let endVal = iterable[2].render
      result.add(ind & "for ($" & varName & " = " & startVal & "; $" & varName & " <= " & endVal & "; $" & varName & "++) {\n")
      result.add(gen.genStmt(node[2], indent + 1))
      result.add(ind & "}\n")
    else:
      result.add(ind & "foreach (" & iterable.renderHandle & " as $" & varName & ") {\n")
      result.add(gen.genStmt(node[2], indent + 1))
      result.add(ind & "}\n")
  of nkCall:
    if node[0].kind == nkIdent and node[0].ident == "echo":
      result.add(ind & "echo " & node[1..^1].mapIt(it.render).join(", ") & ";\n")
    else:
      discard
  of nkBlock:
    for i, s in node:
      result.add(gen.genStmt(s, indent))
  of nkReturn:
    if node[0].kind != nkEmpty:
      result.add(ind & "return " & node[0].render & ";\n")
    else:
      result.add(ind & "return;\n")
  of nkBreak:
    result.add(ind & "break;\n")
  of nkContinue:
    result.add(ind & "continue;\n")
  of nkWhile:
    result.add(ind & "while (" & node[0].render & ") {\n")
    result.add(gen.genStmt(node[1], indent + 1))
    result.add(ind & "}\n")
  else: discard

proc genScript*(program: Ast, includePath: Option[string],
            isMainScript: static bool = false,
            isSnippet: static bool = false) {.codegen.} =
  # Generate the PHP script from the AST
  when isSnippet == true:
    let baseCode =
      utilsJS.replace(re(r"^\s*//.*$", {reStudy, reMultiLine}))
            .replace(re"/\*[\s\S]*?\*/")
            .replace(re"\s{2,}", "")
            .replace(re"\n+")
    echo baseCode
  result.add("<?php\n$html = '';\n")
  for node in program.nodes:
    result.add(gen.genStmt(node, 0))
  result.add("echo $html;\n")
