--mm:arc
--define:timHotCode
--threads:on
--deepcopy:on

when defined napibuild:
  --define:napiOrWasm
  --define:watchoutBrowserSync
  --noMain:on
  --passC:"-I/usr/include/node -I/usr/local/include/node"

when isMainModule:
  --define:timStandalone
  when defined release:
    --opt:speed
    --define:danger
    --passC:"-flto"
    --passL:"-flto"
