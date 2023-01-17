proc handleViewInclude(c: var Compiler) =
  if c.hasViewCode:
    if c.minify:
      add c.html, c.viewCode
    else:
      add c.html, indent(c.viewCode, c.baseIndent * 2)
  else:
    add c.html, c.timView.setPlaceHolderId()

  if c.hasJS:
    add c.html, NewLine & "<script type=\"text/javascript\">"
    add c.html, $c.js
    add c.html, NewLine & "</script>"
  if c.hasSass:
    add c.html, NewLine & "<style>"
    add c.html, $c.sass
    add c.html, NewLine & "</style>"