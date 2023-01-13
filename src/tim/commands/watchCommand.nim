import ./setupEngine

proc runCommand*() =
  newTimEngine()
  discard Tim.precompile()