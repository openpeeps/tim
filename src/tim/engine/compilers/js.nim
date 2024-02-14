# A super fast template engine for cool kids
#
# (c) 2023 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, strutils, json,
  jsonutils, options, terminal]

import pkg/jsony
import ../ast, ../logging

from std/xmltree import escape
from ../meta import TimEngine, TimTemplate, TimTemplateType,
  getType, getSourcePath

import ./tim # TimCompiler object

type
  JSCompiler* = object of TimCompiler
    ## Object of a TimCompiler to transpile Tim templates
    ## to `JavaScript` HtmlElement nodes for client-side
    ## rendering.
    globalScope: ScopeTable = ScopeTable()
    data: JsonNode
    jsOutputCode: string = "{"
    jsCountEl: uint
    targetElement: string

const
  domCreateElement = "let $1 = document.createElement('$2');"
  domSetAttribute = "$1.setAttribute('$2','$3');"
  domInsertAdjacentElement = "$1.insertAdjacentElement('beforeend',$2);"
  domInnerText = "$1.innerText=\"$2\";"

# Forward Declaration
proc evaluateNodes(c: var JSCompiler, nodes: seq[Node], elp: string = "")


proc toString(c: var JSCompiler, x: Node): string =
  result =
    case x.nt
    of ntLitString:
      if x.sVals.len == 0:
        x.sVal
      else: ""
    else: ""

proc getAttrs(c: var JSCompiler, attrs: HtmlAttributes, elx: string): string =
  let len = attrs.len
  for k, attrNodes in attrs:
    var attrStr: seq[string]
    for attrNode in attrNodes:
      case attrNode.nt
      of ntAssignableSet:
        add attrStr, c.toString(attrNode)
      else: discard # todo
    add result, domSetAttribute % [elx, k, attrStr.join(" ")]
    # add result, attrStr.join(" ")

proc createHtmlElement(c: var JSCompiler, x: Node, elp: string) =
  ## Create a new HtmlElement
  # c.jsClientSideOutput
  let elx = "el" & $(c.jsCountEl)
  add c.jsOutputCode, domCreateElement % [elx, x.getTag()]
  if x.attrs != nil:
    add c.jsOutputCode, c.getAttrs(x.attrs, elx)
  inc c.jsCountEl
  if x.nodes.len > 0:
    c.evaluateNodes(x.nodes, elx)
  if elp.len > 0:
    add c.jsOutputCode, domInsertAdjacentElement % [elp, elx]
  else:
    add c.jsOutputCode, domInsertAdjacentElement % ["document.querySelector('" & c.targetElement & "')", elx]

proc evaluateNodes(c: var JSCompiler, nodes: seq[Node], elp: string = "") =
  for i in 0..nodes.high:
    case nodes[i].nt
    of ntHtmlElement:
      c.createHtmlElement(nodes[i], elp)
    of ntLitString, ntLitInt, ntLitFloat, ntLitBool:
      add c.jsOutputCode, domInnerText % [elp, c.toString(nodes[i])]
    else: discard # todo

proc newCompiler*(nodes: seq[Node], clientTargetElement: string): JSCompiler =
  ## Create a new instance of `JSCompiler`
  result = JSCompiler(targetElement: clientTargetElement)
  result.evaluateNodes(nodes)

proc getOutput*(c: var JSCompiler): string =
  add c.jsOutputCode, "}" # end block statement
  result = c.jsOutputCode
