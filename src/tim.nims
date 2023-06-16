when defined emscripten:
  # This path will only run if -d:emscripten is passed to nim.
  --nimcache:tmp # Store intermediate files close by in the ./tmp dir.
  --os:linux # Emscripten pretends to be linux.
  --cpu:wasm32 # Emscripten is 32bits.
  --cc:clang # Emscripten is very close to clang, so we ill replace it.
  when defined(windows):
    --clang.exe:emcc.bat  # Replace C
    --clang.linkerexe:emcc.bat # Replace C linker
    --clang.cpp.exe:emcc.bat # Replace C++
    --clang.cpp.linkerexe:emcc.bat # Replace C++ linker.
  else:
    --clang.exe:emcc  # Replace C
    --clang.linkerexe:emcc # Replace C linker
    --clang.cpp.exe:emcc # Replace C++
    --clang.cpp.linkerexe:emcc # Replace C++ linker.
  when compileOption("threads"):
    # We can have a pool size to populate and be available on page run
    # --passL:"-sPTHREAD_POOL_SIZE=2"
    discard
  --listCmd # List what commands we are running so that we can debug them.

  --gc:arc
  --exceptions:goto
  --define:noSignalHandler
  --objChecks:off # for some reason I get ObjectConversionDefect in std/streams 
  --define:release
  switch("passL", "-s ALLOW_MEMORY_GROWTH")
  # switch("passL", "-s INITIAL_MEMORY=512MB")
  switch("passL", "-O3 -o step1.html --shell-file src/shell_minimal.html")
  switch("passL", "-s EXPORTED_FUNCTIONS=_free,_malloc,_tim")
  switch("passL", "-s EXPORTED_RUNTIME_METHODS=ccall,cwrap,setValue,getValue,stringToUTF8,allocateUTF8,UTF8ToString")
else:
  --threads:on
  --define:useMalloc
  --gc:arc
  --deepcopy:on
  --define:msgpack_obj_to_map
  when defined release:
    --define:danger
    --opt:speed
    --passC: "-flto"
    --passL: "-flto"
    --define:nimAllocPagesViaMalloc