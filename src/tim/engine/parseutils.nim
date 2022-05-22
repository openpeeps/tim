# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

template setHTMLAttributes[T: Parser](p: var T, htmlNode: var HtmlNode): untyped =
    ## Set HTML attributes for current HtmlNode, this template covers
    ## all kind of attributes, including `id`, and `class` or custom.
    var id: IDAttribute
    var hasAttributes: bool
    var attributes: Table[string, seq[string]]
    while true:
        if p.current.kind == TK_ATTR_CLASS and p.next.kind == TK_IDENTIFIER:
            # TODO check for wsno for `.` token and prevent mess
            hasAttributes = true
            if attributes.hasKey("class"):
                if p.next.value in attributes["class"]:
                    p.setError("Duplicate class entry found for \"$1\"" % [p.next.value])
                else: attributes["class"].add(p.next.value)
            else:
                attributes["class"] = @[p.next.value]
            jump p, 2
        elif p.current.kind == TK_ATTR_ID and p.next.kind == TK_IDENTIFIER:
            # TODO check for wsno for `#` token
            if htmlNode.hasID():
                p.setError("Elements can hold a single ID attribute.")
            id = IDAttribute(value: p.next.value)
            if id != nil: htmlNode.id = id
            jump p, 2
        elif p.current.kind == TK_IDENTIFIER and p.next.kind == TK_ASSIGN:
            # TODO check for wsno for other `attr` token
            let attrName = p.current.value
            jump p
            if p.next.kind != TK_STRING:
                p.setError("Missing value for \"$1\" attribute" % [attrName])
                break
            if attributes.hasKey(attrName):
                p.setError("Duplicate attribute name \"$1\"" % [attrName])
            else:
                attributes[attrName] = @[p.next.value]
                hasAttributes = true
            jump p, 2
        elif p.current.kind == TK_COLON:
            if p.next.kind != TK_STRING:
                # Handle string content assignment or enter in a multi dimensional nest
                p.setError("Expecting string content for \"$1\" node" % [htmlNode.nodeName])
                break
            else:
                jump p
                if (p.current.line == p.next.line) and not p.next.isEOF:
                    p.setError("Bad indentation after enclosed string")      # TODO a better error message?
                    break
                let htmlTextNode = HtmlNode(
                    nodeType: HtmlText,
                    nodeName: getSymbolName(HtmlText),
                    text: p.current.value,
                    meta: (column: p.current.col, indent: p.current.wsno, line: p.current.line)
                )
                htmlNode.nodes.add(htmlTextNode)
            break
        else: break

    if hasAttributes:
        for attrName, attrValues in attributes.pairs:
            htmlNode.attributes.add(HtmlAttribute(name: attrName, value: attrValues.join(" ")))
        hasAttributes = false
    clear(attributes)

proc parseVariable[T: Parser](p: var T, tokenVar: TokenTuple): VariableNode =
    ## Parse and validate given VariableNode
    # var varNode: VariableNode
    let varName: string = tokenVar.value
    if not p.data.hasVar(varName):
        p.setError("Undeclared variable \"$1\"" % [varName])
        return nil
    result = newVariableNode(varName, p.data.getVar(varName))

template parseCondition[T: Parser](p: var T, conditionNode: ConditionalNode): untyped =
    ## Parse and validate given ConditionalNode 
    let currln: int = p.current.line
    var compToken: TokenTuple
    var varNode1, varNode2: VariableNode
    var comparatorNode: ComparatorNode
    while true:
        if p.current.kind == TK_IF and p.next.kind != TK_VARIABLE:
            p.setError("Missing variable identifier for conditional statement")
            break
        jump p
        varNode1 = p.parseVariable(p.current)
        jump p
        if varNode1 == nil: break    # and prompt "Undeclared identifier" error
        elif p.current.kind in {TK_EQ, TK_NEQ}:
            compToken = p.current
            if p.next.kind == TK_VARIABLE:
                jump p
                varNode2 = p.parseVariable(p.current)
            comparatorNode = newComparatorNode(compToken, @[varNode1, varNode2])
            conditionNode.comparatorNode = comparatorNode
        elif p.next.kind != TK_STRING:
            p.setError("Invalid conditional. Missing comparison value")
            break
        break