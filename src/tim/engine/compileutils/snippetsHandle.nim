proc handleJavaScriptSnippet(c: var Compiler, node: Node) =
  c.js &= node.jsCode

proc handleSassSnippet(c: var Compiler, node: Node) =
  try:
    c.sass &= NewLine & compile(node.sassCode, indentOnly = true)
  except SassException:
    c.logs.add(getCurrentExceptionMsg())