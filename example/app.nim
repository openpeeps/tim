import ../src/tim
import std/[options, asyncdispatch, macros,
  os, strutils, times, json]
import pkg/[httpbeast]

from std/httpcore import HttpCode, Http200
from std/net import Port

const projectPath = getProjectPath()

template getStaticAsset(path: string) {.dirty.} =
  let assetsPath = projectPath / "storage" / path
  if fileExists(assetsPath):
    var contentType = "Content-Type: " 
    if assetsPath.endsWith(".svg"):
      add contentType, "image/svg+xml"
    elif assetsPath.endsWith(".png"):
      add contentType, "image/png"
    elif assetsPath.endsWith(".js"):
      add contentType, "text/javascript"
    elif assetsPath.endsWith(".css"):
      add contentType, "text/css"
    req.send(Http200, readFile(assetsPath), headers = contentType)
    return

var
  timl = newTim(
    src = "templates",
    output = "storage",
    basepath = currentSourcePath(),
    minify = true,
    indent = 2
  )

let currentYear = now().format("yyyy")
let globalData = %*{
    "year": parseInt(currentYear)
  }

proc precompileEngine() {.thread.} =
  {.gcsafe.}:
    timl.precompile(waitThread = true, global = globalData)

var thr: Thread[void]
createThread(thr, precompileEngine)

proc resp(req: Request, view: string, code = Http200,
    headers = "Content-Type: text/html", local = newJObject()) =
  let htmlOutput = timl.render(view, local = local)
  req.send(code, htmlOutput, headers)

proc onRequest(req: Request): Future[void] =
  {.gcsafe.}:
    let path = req.path.get()
    case req.httpMethod.get()
    of HttpGet:
      case path
      of "/":
        req.resp("index")
      of "/about":
        req.resp("about")
      else:
        if path.startsWith("/assets"):
          getStaticAsset(path)
        req.send(Http404)
    else: req.send(Http500)

echo "http://127.0.0.1:1234"
let serverSettings = initSettings(Port(1234), numThreads = 1)
run(onRequest, serverSettings)
