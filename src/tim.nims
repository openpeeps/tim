--deepcopy:on
--define:ssl
--threads:on
--mm:orc
--define:nimPreviewHashRef

when defined napibuild:
  --define:release

when defined release:
  --opt:speed
  when defined clang:
    --passC:"-O3 -flto -march=native"
    --passL:"-O3 -flto -march=native"
