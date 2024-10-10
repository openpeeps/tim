# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, strutils]
import pkg/nyml
import pkg/kapsis/[cli, runtime] 

import ../server/[app, config]
import ../engine/meta

proc runCommand*(v: Values) =
  ## Run a new Universal Tim Engine microservice
  ## in the background using the `tcp` socket.
  ## 
  ## This feature is powered by ZeroMQ and makes Tim Engine
  ## available from any programming language that implements `libzmq`.
  ## 
  ## More details about ZeroMQ check [https://github.com/zeromq](https://github.com/zeromq)
  let path = absolutePath(v.get("config").getPath.path)
  let config = fromYaml(path.readFile, TimConfig)
  var timEngine =
    newTim(
      config.compilation.source,
      config.compilation.output,
      path.parentDir
    )
  app.run(timEngine, config)