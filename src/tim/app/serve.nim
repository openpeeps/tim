# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, httpcore, net, os, strutils, options, locks]
import pkg/kapsis/runtime
import pkg/openparser/[yaml, json]
import pkg/watchout
import pkg/vancode/manager/packager

import supranim/network/webserver

import ../meta/[initializer, config, websocket]

type
  WebApp* = ref object
    server*: WebServer
    engine*: TimEngine
    configInstance*: TimConfig
    baseDir*: string
    watcher*: Watchout
    wsServer*: WebSocketServer

var webapp*: WebApp

var templateLock: Lock
initLock(templateLock)

proc serveTemplate(req: var Request, viewName: string) =
  acquire(templateLock)
  let viewTpl = webapp.engine.getView(viewName.replace(".", "/"))
  let layoutTpl = webapp.engine.getLayout("base")
  if viewTpl != nil and layoutTpl != nil:
    try:
      let html = "<!DOCTYPE html>" & $interpret(viewTpl, layoutTpl, newJObject(), webapp.engine.globalData)
      release(templateLock)
      req.send(200, html)
      return
    except Exception as e:
      echo e.msg
      release(templateLock)
      req.send(500, "Internal Server Error")
      return
  release(templateLock)
  req.send(404, "Not Found")

proc onRequest(req: var Request) {.gcsafe.} =
  {.gcsafe.}:
    let path = req.path
    var viewName = webapp.configInstance.server.routes.getOrDefault(path)
    if viewName.len == 0 and path != "/":
      viewName = webapp.configInstance.server.routes.getOrDefault(path.strip(chars={'/'}, leading=true))
    if viewName.len > 0:
      serveTemplate(req, viewName)
    else:
      let staticPath = webapp.baseDir / "public" / path.relativePath("/")
      if fileExists(staticPath):
        let headers = newHttpHeaders()
        let ext = staticPath.splitFile().ext.toLowerAscii()
        case ext
        of ".html", ".htm": headers.add("Content-Type", "text/html")
        of ".css":          headers.add("Content-Type", "text/css")
        of ".js":           headers.add("Content-Type", "application/javascript")
        of ".png":          headers.add("Content-Type", "image/png")
        of ".jpg", ".jpeg": headers.add("Content-Type", "image/jpeg")
        of ".gif":          headers.add("Content-Type", "image/gif")
        of ".svg":          headers.add("Content-Type", "image/svg+xml")
        of ".ico":          headers.add("Content-Type", "image/x-icon")
        else:               discard
        req.send(200, readFile(staticPath), headers)
      else:
        req.send(404, "Not Found")

proc serveCommand*(v: Values) =
  let configPath = $(v.get("config").getPath)
  let yamlFile = readFile(configPath)
  let config: TimConfig = parseYaml(yamlFile, TimConfig)
  let baseDir = absolutePath(configPath.parentDir())
  discard existsOrCreateDir(baseDir / "storage")

  let timEngine = newTim(
    src = "templates",
    output = "storage",
    basepath = baseDir
  )
  timEngine.precompile()

  webapp = WebApp(
    server: newWebServer(
      port = config.server.port,
      enableMultiThreading = config.server.threads > 1
    ),
    engine: timEngine,
    configInstance: config,
    baseDir: baseDir
  )

  let pkgr = packager.initPackageRemote()
  pkgr.loadPackages()

  webapp.watcher = newWatchout(@[
    baseDir / "templates" / "layouts",
    baseDir / "templates" / "views",
    baseDir / "templates" / "partials"
  ], some("*.timl"))

  webapp.watcher.onFound = proc(file: watchout.File) =
    acquire(templateLock)
    let tpl = webapp.engine.getTemplateByPath(file.getPath())
    if tpl != nil:
      if tpl.templateType in {ttView, ttLayout}:
        discard webapp.engine.precompileTemplate(tpl, pkgr)
    else:
      let newTpl = webapp.engine.registerTemplate(file.getPath())
      if newTpl.templateType != ttPartial:
        discard webapp.engine.precompileTemplate(newTpl, pkgr)
    release(templateLock)

  webapp.watcher.onChange = proc(file: watchout.File) =
    let fpath = file.getPath()
    var size = getFileSize(fpath)
    sleep(300)
    while getFileSize(fpath) != size:
      size = getFileSize(fpath)
      sleep(200)
    acquire(templateLock)
    let tpl = webapp.engine.getTemplateByPath(fpath)
    if tpl != nil and tpl.templateType in {ttView, ttLayout}:
      if webapp.engine.precompileTemplate(tpl, pkgr):
        notifyAllClients(webapp.wsServer)
    release(templateLock)

  webapp.watcher.onDelete = proc(file: watchout.File) =
    acquire(templateLock)
    let tpl = webapp.engine.getTemplateByPath(file.getPath())
    if tpl != nil:
      case tpl.templateType
      of ttView:
        webapp.engine.views.del(tpl.sources.src)
      of ttLayout:
        webapp.engine.layouts.del(tpl.sources.src)
      of ttPartial:
        webapp.engine.partials.del(tpl.sources.src)
    release(templateLock)

  webapp.watcher.start()

  let wsPort = if config.browser_sync != nil: config.browser_sync.port
               else: Port(9000)
  webapp.wsServer = startWebSocket(wsPort)

  webapp.server.start(onRequest)
