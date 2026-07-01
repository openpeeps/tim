# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, httpcore, net, os, strutils]
import pkg/kapsis/runtime
import pkg/openparser/[yaml, json]

import supranim/network/webserver
import supranim/core/[router, request, response]

import ../meta/[initializer, config]

type
  WebApp* = ref object
    ## Represents a web application that serves at a specified port and handles
    server*: WebServer
      ## A powpow web server instance that listens for incoming HTTP requests and serves responses.
    router*: HttpRouterInstance
      ## A router instance that maps incoming HTTP requests to specific handlers based on the request path and method.
    engine*: TimEngine
      ## A Tim Engine instance that handles template rendering for the web application.
    configInstance*: TimConfig
      ## The configuration object for the web application, containing settings such as routes, server port, and other options.

var webapp: WebApp # a singleton instance of the web application, initialized in the `serveCommand` procedure.

proc render*(engine: TimEngine, view: string, layout: string = "base",
            data: JsonNode): string =
  ## Render a Tim Engine template based on the view and layout templates.
  ## 
  ## Optionally, you can pass a `JsonNode` object as data to be used
  ## within the template as local data available under the `$this` variable.
  ## 
  ## If no layout is provided, the default `base` layout will be used.
  ## 
  ## Raises a `TimEngineError` if the view or layout templates are not found.
  ## Ensure to handle these exceptions in your web server to respond
  ## with appropriate HTTP status codes (e.g., 404 or 500).
  let
    viewTpl: TimTemplate = engine.getView(view.replace(".", "/"))
    layoutTpl: TimTemplate = engine.getLayout(layout)
  
  if viewTpl == nil:
    raise newException(TimEngineError, "View template not found: " & view)

  if layoutTpl == nil:
    raise newException(TimEngineError, "Layout template not found: " & layout)
  result.add("<!DOCTYPE html>")    # Add DOCTYPE declaration at the beginning of the output
  result.add($interpret(viewTpl, layoutTpl, data, engine.globalData))

proc renderView*(engine: TimEngine, view: string, data: JsonNode): string =
  ## Render a Tim Engine template based on the view and layout templates.
  ## 
  ## Optionally, you can pass a `JsonNode` object as data to be used
  ## within the template as local data available under the `$this` variable.
  ## 
  ## If no layout is provided, the default `base` layout will be used.
  ## 
  ## Raises a `TimEngineError` if the view or layout templates are not found.
  ## Ensure to handle these exceptions in your web server to respond
  ## with appropriate HTTP status codes (e.g., 404 or 500).
  let viewTpl: TimTemplate = engine.getView(view.replace(".", "/"))
  if viewTpl == nil:
    raise newException(TimEngineError, "View template not found: " & view)
  result.add($interpret(viewTpl, data, engine.globalData))

proc onRequest(req: var Request) =
  # Handle incoming HTTP requests and serve the appropriate response based on the request path and method
  {.gcsafe.}:
    let path = req.getUriPath()
    if path == "/":
      let indexView = webapp.configInstance.server.routes.getOrDefault("/", "index")
      if webapp.router.checkExists("/", HttpGet).exists:
        try:
          let html = webapp.engine.render(indexView, "base", newJObject())
          req.send(200, html)
          return
        except:
          discard
      else:
        try:
          let html = webapp.engine.renderView(indexView, newJObject())
          req.send(200, html)
          return
        except:
          req.send(404, "Not Found")
        return

    let routeCheck = webapp.router.checkExists(path, HttpGet)
    if routeCheck.exists:
      let viewName = webapp.configInstance.server.routes.getOrDefault(path, path)
      try:
        let html = webapp.engine.render(viewName, "base", newJObject())
        req.send(200, html)
        return
      except:
        discard

    try:
      let html = webapp.engine.renderView(path, newJObject())
      req.send(200, html)
      return
    except:
      req.send(404, "Not Found")

proc requestHandle(req: var request.Request, res: var Response): void =
  discard

proc serveCommand*(v: Values) =
  ## Command for starting a local development server that serves rendered templates
  let configPath = $(v.get("config").getPath)
  let yamlFile = readFile(configPath)
  let config: TimConfig = parseYaml(yamlFile, TimConfig)
  let baseDir = configPath.parentDir()
  discard existsOrCreateDir(baseDir / "storage")

  let timEngine = newTim(
    src = baseDir / "src" / "templates",
    output = baseDir / "storage",
    basepath = baseDir
  )
  timEngine.precompile()

  var router = newHttpRouter()
  for routePath, viewName in config.server.routes:
    router.registerRoute(routePath, HttpGet, requestHandle)

  webapp = WebApp(
    server: newWebServer(
      port = Port(8000),
      enableMultiThreading = config.server.threads > 1
    ),
    router: router,
    engine: timEngine,
    configInstance: config
  )

  let nThreads = if config.server.threads > 1: config.server.threads.int else: 0
  webapp.server.start(onRequest, startupCallback = nil, threads = nThreads)
