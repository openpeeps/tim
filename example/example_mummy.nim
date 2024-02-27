import std/[times, os, strutils, json]
import pkg/[mummy, mummy/routers]

include ./initializer

#
# Example Mummy + Tim Engine
#
template initHeaders {.dirty.} =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/html"

proc resp(req: Request, view: string, layout = "base",
    local = newJObject(), code = 200) =
  initHeaders()
  {.gcsafe.}:
    local["path"] = %*(req.path)
    let output = timl.render(view, layout, local = local)
  req.respond(200, headers, output)

proc indexHandler(req: Request) =
  req.resp("index", local = %*{
    "meta": {
      "title": "Tim Engine is Awesome!"
      }
    }
  )

proc aboutHandler(req: Request) =
  req.resp("about", layout = "secondary",
    local = %*{
      "meta": {
        "title": "About Tim Engine"
      }
    }
  )

proc e404(req: Request) =
  req.resp("error", code = 404,
    local = %*{
      "meta": {
        "title": "Oh, you're a genius!",
        "msg": "Oh yes, yes. It's got action, it's got drama, it's got dance! Oh, it's going to be a hit hit hit!"
      }
    }
  )

var router: Router
router.get("/", indexHandler)
router.get("/about", aboutHandler)

# Custom 404 handler
router.notFoundHandler = e404

let server = newServer(router)
echo "Serving on http://localhost:8081"
server.serve(Port(8081))
