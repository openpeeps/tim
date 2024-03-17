import ../src/tim

#
# Setup Tim Engine
#
var
  timl =
    newTim(
      src = "templates",
      output = "storage",
      basepath = currentSourcePath(),
      minify = true,
      indent = 2,
      showHtmlError = true
    )

# some read-only data to expose inside templates
# using the built-in `$app` constant
let globalData = %*{
    "year": parseInt(now().format("yyyy")),
    "stylesheets": [
      {
        "type": "stylesheet",
        "src": "https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css"
      },
      {
        "type": "preconnect",
        "src": "https://fonts.googleapis.com"
      },
      {
        "type": "preconnect",
        "src": "https://fonts.gstatic.com"
      },
      {
        "type": "stylesheet",
        "src": "https://fonts.googleapis.com/css2?family=Inter:wght@100..900&display=swap"
      }
    ]
  }
# 2. Pre-compile discovered templates
#    before booting your web app.
#
#    Note that `waitThread` will keep thread alive.
#    This is required while in dev mode
#    by the built-in file system monitor
#    in order to rebuild templates.
#
#    Don't forget to enable hot code reload
#    using `-d:timHotCode`
var timThread: Thread[void]
proc precompileEngine() {.thread.} =
  {.gcsafe.}:
    # let's add some placeholders
    const snippetCode2 = """
div.alert.aler.dark.rounded-0.border-0.mb-0 > p.mb-0: "Alright, I'm the second snippet loaded by #topbar placeholder."
    """
    let snippetParser = parseSnippet("mysnippet", readFile("./mysnippet.timl"))
    timl.addPlaceholder("topbar", snippetParser.getAst)
    
    let snippetParser2 = parseSnippet("mysnippet2", snippetCode2)
    timl.addPlaceholder("topbar", snippetParser2.getAst)

    timl.precompile(
      waitThread = true,
      global = globalData,
      flush = true,         # flush old cache on reboot
    )

createThread(timThread, precompileEngine)
