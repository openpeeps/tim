--mm:arc
--define:timHotCode
--threads:on

when defined napibuild:
  --define:napiOrWasm
  --noMain:on
  --passC:"-I/usr/include/node -I/usr/local/include/node"