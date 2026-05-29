# when defined(macosx):
#   --passL:"/opt/local/lib/libevent.a"
#   --passL:"/opt/local/lib/libevent_pthreads.a"
#   --passL:"/usr/local/lib/libmonocypher.a"
#   --passC:"-I /opt/local/include"
#   --passC:"-Wno-incompatible-function-pointer-types"
# elif defined(linux):
#   # --passL:"-L/usr/local/lib/lib -L/usr/local/lib -Wl,-rpath,/usr/local/lib/lib -Wl,-rpath,/usr/local/lib -levent"
#   --passL:"/usr/lib/x86_64-linux-gnu/libevent.a"
#   --passL:"/usr/lib/x86_64-linux-gnu/libevent_pthreads.a"
#   --passL:"/usr/lib/lib/x86_64-linux-gnu/libmonocypher.a"
#   --passC:"-I /usr/include"

--mm:atomicArc
--define:ssl
--threads:on
--deepcopy:on
--define:nimPreviewHashRef

when defined napibuild:
  --define:release

when defined release:
  --opt:speed
  when defined clang:
    --passC:"-O3 -flto -march=native"
    --passL:"-O3 -flto -march=native"
