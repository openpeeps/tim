# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[os, tables]

type
  ResolvedFiles = Table[string, seq[string]]
  FileResolver* = object
    ## Manages file resolution for imports/includes
    resolvedFiles: ResolvedFiles
      # Tracks which files have been resolved (imported/included)

  ResolverError* = object of CatchableError

proc initResolver*(): FileResolver =
  ## Initialize a new FileResolver
  result.resolvedFiles = ResolvedFiles()

proc fileExists*(resolver: FileResolver, filePath: string): bool =
  # Checks if the file exists on disk
  return fileExists(filePath)

proc isResolved*(resolver: FileResolver, filePath: string): bool =
  # Checks if the file has already been resolved (included/imported)
  result = resolver.resolvedFiles.hasKey(filePath)

proc markResolved(resolver: var FileResolver, aFile, bFile: string) =
  # Marks a file as resolved (included/imported)
  # `aFile`: the module doing the import
  # `bFile`: the imported module
  # Ensure both `aFile` and `bFile` have entries
  if not resolver.resolvedFiles.hasKey(aFile):
    resolver.resolvedFiles[aFile] = @[]

  if not resolver.resolvedFiles.hasKey(bFile):
    resolver.resolvedFiles[bFile] = @[]

  # Add bFile to aFile's list, and aFile to bFile's list
  if bFile notin resolver.resolvedFiles[aFile]:
    resolver.resolvedFiles[aFile].add(bFile)

  if aFile notin resolver.resolvedFiles[bFile]:
    resolver.resolvedFiles[bFile].add(aFile)

proc resolveFile*(resolver: var FileResolver, aFile, bFile: string) =
  ## Resolve a file import/include. This proc checks
  ## if the file exists, if it has already been resolved,
  ## and if there are any circular or self-imports.
  ## 
  ## If all checks pass, it marks the file as resolved.
  ## TODO handle symlinks
  if not resolver.fileExists(bFile):
    raise newException(ResolverError, "File does not exist: " & bFile)
  if resolver.resolvedFiles.hasKey(aFile):
    if bFile == aFile:
      raise newException(ResolverError, "Self-import detected: " & aFile)
    elif bFile in resolver.resolvedFiles[aFile]:
      raise newException(ResolverError,
        "Circular import detected: " & aFile & " <-> " & bFile)
  resolver.markResolved(aFile, bFile)
