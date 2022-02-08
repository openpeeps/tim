task dev, "Compile Tim":
    echo "\n✨ Compiling..." & "\n"
    exec "nimble build --gc:arc -d:useMalloc"