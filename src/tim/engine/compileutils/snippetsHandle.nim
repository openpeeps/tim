proc handleJavaScriptSnippet(c: var Compiler, node: Node) =
  c.js &= node.jsCode

proc handleSassSnippet(c: var Compiler, node: Node) =
  try:
    c.sass &= NewLine & compileSass(node.sassCode)
  except SassException:
    c.logs.add(getCurrentExceptionMsg())