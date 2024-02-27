import ../src/tim
import std/[options, asyncdispatch, macros,
  os, strutils, times, json]
import pkg/[httpbeast]

from std/httpcore import HttpCode, Http200
from std/net import Port

include ./initializer

proc resp(req: Request, view: string, layout = "base", code = Http200,
    headers = "Content-Type: text/html", local = newJObject()) =
  local["path"] = %*(req.path.get())
  let htmlOutput = timl.render(view, layout, local = local)
  req.send(code, htmlOutput, headers)

proc onRequest(req: Request): Future[void] =
  {.gcsafe.}:
    let path = req.path.get()
    case req.httpMethod.get()
    of HttpGet:
      case path
      of "/":
        req.resp("index",
          local = %*{
            "meta": {
              "title": "Tim Engine is Awesome!"
            }
          })
      of "/about":
        req.resp("about", "secondary",
          local = %*{
            "meta": {
              "title": "About Tim Engine"
            }
          })
      req.resp("error", code = Http404, local = %*{
        "meta": {
          "title": "Oh, you're a genius!",
          "msg": "Oh yes, yes. It's got action, it's got drama, it's got dance! Oh, it's going to be a hit hit hit!"
        }
      })
    else: req.send(Http501)

echo "Serving on http://localhost:8080"
let serverSettings = initSettings(Port(8080), numThreads = 1)
run(onRequest, serverSettings)
