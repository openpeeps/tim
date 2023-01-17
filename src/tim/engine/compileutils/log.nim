proc hasError*(c: Compiler): bool =
  result = c.logs.len != 0

proc getErrors*(c: Compiler): seq[string] =
  result = c.logs

proc printErrors*(c: var Compiler, filePath: string) =
  if c.logs.len != 0:
    echo filePath
    for error in c.logs:
      echo indent("Warning: " & error, 2)
    setLen(c.logs, 0)