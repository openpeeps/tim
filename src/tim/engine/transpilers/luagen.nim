include ./private

#
# Forward declarations
#
proc genStmt(node: Node, indent: int = 0) {.codegen.}

#
# Lua Transpiler
#

proc repeatStr(s: string, n: int): string =
  for i in 0..<n:
    result.add(s)

proc getImplValue(node: Node, unquoted = true): string =
  case node.kind
  of nkInt:     $node.intVal
  of nkFloat:   $node.floatVal
  of nkString:
    if unquoted: "\"" & node.stringVal & "\""
    else: node.stringVal
  of nkBool:
    if node.boolVal: "true"
    else: "false"
  of nkArray:
    "{" & node.children.mapIt(getImplValue(it)).join(", ") & "}"
  of nkObject:
    "{ " & node.children.mapIt(
      if it.kind == nkIdentDefs:
        let key = it[0].render
        let value = getImplValue(it[^1])
        key & " = " & value
      else:
        ""
    ).join(", ") & " }"
  else: ""

proc writeVar(node: Node, indent: int = 0): string {.codegen.} =
  let ind = repeatStr("  ", indent)
  for decl in node:
    let varName = decl[0].ident
    let value = decl[^1].getImplValue
    result.add(ind & "local " & varName & " = " & value & "\n")

proc renderHandle(node: Node, unquoted = true): string =
  case node.kind
  of nkString:
    if not unquoted: "\"" & node.stringVal & "\""
    else: node.stringVal
  of nkInt:
    $node.intVal
  of nkFloat:
    $node.floatVal
  of nkBool:
    if node.boolVal: "true" else: "false"
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

proc writeHtml(node: Node, indent: int = 0): string {.codegen.} =
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
                  "\" .. " & left.renderHandle(false) & " .. \""
              let rightVal =
                if right.kind == nkIdent and right.ident.len > 0 and right.ident[0] == '$':
                  "\" .. "& right.ident[1..^1] & " .. \""
                else:
                  (if right.kind == nkString: right.stringVal
                                        else: "\" .. " & right.renderHandle(false) & " .. \"")
              customAttrs.add((attr.attrNode[1].renderHandle(true), leftVal & rightVal))
          else:
            let key = attr.attrNode[1].renderHandle
            let value =
              case attr.attrNode[2].kind
              of nkIdent, nkCall:
                "\" .. " & attr.attrNode[2].renderHandle & " .. \""
              else: 
                attr.attrNode[2].renderHandle
            customAttrs.add((key, value))
        elif attr.attrNode.kind == nkString:
          customAttrs.add((attr.attrNode.stringVal, ""))
      else:
        discard
  let ind = repeatStr("  ", indent)
  result.add(ind & "html = html .. \"<" & tag)
  if classNames.len > 0:
    result.add(" class=\\\"" & classNames.join(" ") & "\\\"")
  if idVal.len > 0:
    result.add(" id=\\\"" & idVal & "\\\"")
  for (name, value) in customAttrs:
    if value.len > 0:
      result.add(" " & name & "=\\\"" & value & "\\\"")
    else:
      result.add(" " & name)
  result.add(">\"\n")
  for child in node.childElements:
    case child.kind
    of nkBool, nkInt, nkFloat:
      result.add(ind & "html = html .. " & child.renderHandle & "\n")
    of nkString:
      if tag == "script":
        let js = minifyInlineJsVanilla(child.stringVal)
        result.add(ind & "html = html .. [[")
        result.add(js)
        result.add("]]\n")
      else:
        result.add(ind & "html = html .. " & child.renderHandle(false) & "\n")
    of nkIdent:
      result.add(ind & "html = html .. " & child.renderHandle & "\n")
    of nkCall:
      if child[0].ident[0] == '@':
        discard
      else:
        result.add(gen.genStmt(child, indent + 2))
    else:
      result.add(gen.genStmt(child, indent + 2))
  if node.tag notin voidHtmlElements:
    result.add(ind & "html = html .. \"</" & tag & ">\"\n")

proc genStmt(node: Node, indent: int = 0): Rope {.codegen.} =
  result = Rope()
  let ind = repeatStr("  ", indent)
  case node.kind
  of nkVar, nkLet, nkConst:
    result.add(gen.writeVar(node, indent))
  of nkProc:
    let fnName = node[0].render
    let params = node[2]
    result.add(ind & "function " & fnName & "(")
    result.add(params[1..^1].mapIt(it[0].render).join(", "))
    result.add(")\n")
    for param in params[1..^1]:
      if param.kind == nkIdentDefs:
        let pname = param[0].render
        result.add(ind & "  -- @param " & pname & "\n")
    result.add(gen.genStmt(node[3], indent + 1))
    result.add(ind & "end\n")
  of nkMacro:
    let fnName = node[0].ident[1..^1]
    let params = node[2]
    result.add(ind & "function " & fnName & "(")
    result.add(params[1..^1].mapIt(it[0].render).join(", "))
    result.add(")\n")
    for param in params[1..^1]:
      if param.kind == nkIdentDefs:
        let pname = param[0].render
        result.add(ind & "  -- @param " & pname & "\n")
    result.add(ind & "  -- @return string HTML\n")
    result.add(ind & "  local html = ''\n")
    result.add(gen.genStmt(node[3], indent + 1))
    result.add(ind & "  return html\n")
    result.add(ind & "end\n")
  of nkHtmlElement:
    result.add(gen.writeHtml(node, indent))
  of nkIf:
    result.add(ind & "if " & node[0].render & " then\n")
    result.add(gen.genStmt(node[1], indent + 1))
    let hasElse = node.children.len mod 2 == 1
    let elifBranches = if hasElse: node[2..^2] else: node[2..^1]
    for i in countup(0, elifBranches.len - 1, 2):
      result.add(ind & "elseif " & elifBranches[i].render & " then\n")
      result.add(gen.genStmt(elifBranches[i + 1], indent + 1))
    if hasElse:
      result.add(ind & "else\n")
      result.add(gen.genStmt(node[^1], indent + 1))
    result.add(ind & "end\n")
  of nkFor:
    let varName = node[0].render
    let iterable = node[1]
    if iterable.kind == nkInfix and iterable[0].kind == nkIdent and iterable[0].ident == "..":
      let startVal = iterable[1].render
      let endVal = iterable[2].render
      result.add(ind & "for " & varName & " = " & startVal & ", " & endVal & " do\n")
      result.add(gen.genStmt(node[2], indent + 1))
      result.add(ind & "end\n")
    else:
      result.add(ind & "for _, " & varName & " in ipairs(" & iterable.render & ") do\n")
      result.add(gen.genStmt(node[2], indent + 1))
      result.add(ind & "end\n")
  of nkCall:
    if node[0].ident == "echo":
      result.add(ind & "print(" & node[1..^1].mapIt(it.render).join(", ") & ")\n")
    else:
      result.add(ind & node[0].render & "(" & node[1..^1].mapIt(it.render).join(", ") & ")\n")
  of nkBlock:
    for i, s in node:
      result.add(gen.genStmt(s, indent))
  of nkReturn:
    if node[0].kind != nkEmpty:
      result.add(ind & "return " & node[0].render & "\n")
    else:
      result.add(ind & "return\n")
  of nkBreak:
    result.add(ind & "break\n")
  of nkContinue:
    result.add(ind & "goto continue\n")
  of nkWhile:
    result.add(ind & "while " & node[0].render & " do\n")
    result.add(gen.genStmt(node[1], indent + 1))
    result.add(ind & "end\n")
  else: discard

proc genScript*(program: Ast, includePath: Option[string],
            isMainScript: static bool = false,
            isSnippet: static bool = false,
            withReturnStmt: static bool = true) {.codegen.} =
  result.add("local $1 = {}\n" % [gen.module.getModuleName()])
  result.add("\n-- @param args Table\n-- @return string The generated HTML.\n")
  result.add("function $1.render(args)\n" % [gen.module.getModuleName()])
  result.add("  local app = args.app or {}\n")
  result.add("  local this = args.app or {}\n")
  result.add("  local html = ''\n")
  for node in program.nodes:
    result.add(gen.genStmt(node, 2))
  result.add("  return html\n")
  result.add("end\n")
  when withReturnStmt == true:
    result.add("return $1\n" % [gen.module.getModuleName()])
