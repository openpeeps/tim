--mm:arc
--define:timHotCode
--threads:on
--deepcopy:on
--define:nimPreviewHashRef
--define:ssl
--define:"ThreadPoolSize=1"
--define:"FixedChanSize=2"

when defined napibuild:
  --define:napiOrWasm
  --define:watchoutBrowserSync
  --noMain:on
  --passC:"-I/usr/include/node -I/usr/local/include/node"

when isMainModule:
  --define:timStandalone
  --define:watchoutBrowserSync
  when defined release:
    --opt:speed
    --define:danger
    --passC:"-flto"
    --passL:"-flto"
