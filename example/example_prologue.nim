#This example demonstrates using Tim with Prologue
import std/[strutils, times]
import prologue
include ./initializer

#init Settings for prologue
let 
    settings = newSettings(port = Port(8082))

var app = newApp(settings = settings)

#define your route handling callbacks
proc indexPageHandler(ctx: Context) {.async, gcsafe.} =
    let localObjects = %*{
        "meta": {
            "title": "Tim Engine is Awesome!"
        },
        "path": "/"
    }

    {.cast(gcsafe).}: #timl is a global using GC'ed memory and prologue loves it's callbacks to be gc-safe
        let indexPage = timl.render(viewName = "index", layoutName = "base", local = localObjects)

    resp indexPage

proc aboutPageHandler(ctx: Context) {.async, gcsafe.} =
    let localObjects = %*{
        "meta": {
            "title": "About Tim Engine"
        },
        "path": "/about"
    }
    {.cast(gcsafe).}: #timl is a global using GC'ed memory and prologue loves it's callbacks to be gc-safe
        let aboutPage = timl.render(viewName = "about", layoutName = "secondary", local = localObjects)

    resp aboutPage

proc e404(ctx: Context) {.async, gcsafe.} =
    let localObjects = %*{
        "meta": {
            "title": "Oh, you're a genius!",
            "msg": "Oh yes, yes. It's got action, it's got drama, it's got dance! Oh, it's going to be a hit hit hit!"
        },
        "path": %*(ctx.request.path)
    }
    {.cast(gcsafe).}: #timl is a global using GC'ed memory and prologue loves it's callbacks to be gc-safe
        let e404Page = timl.render(viewName = "error", layoutName = "base", local = localObjects)

    resp e404Page

#tell prologue how to handle routes
app.addRoute("/", indexPageHandler)
app.addRoute("/about", aboutPageHandler)
app.registerErrorHandler(Http404, e404)

app.run()