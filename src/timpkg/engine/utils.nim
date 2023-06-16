proc malloc_trim*(size: csize_t): cint {.importc, varargs, header: "malloc.h", discardable.}

template freem*(obj: untyped) =
  reset(obj)
  discard malloc_trim(sizeof(obj).csize_t)