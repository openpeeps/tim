# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim
proc parseVariable(p: var Parser, tokenVar: TokenTuple): VariableNode =
    ## Parse and validate given VariableNode
    # var varNode: VariableNode
    let varName: string = tokenVar.value
    # if not p.data.hasVar(varName):
    #     p.setError UndeclaredVariable % [varName]
    #     return nil
    result = newVariableNode(varName, "")
    jit p

template setHTMLAttributes(p: var Parser, htmlNode: var HtmlNode, nodeIndent = 0 ): untyped =
    ## Set HTML attributes for current HtmlNode, this template covers
    ## all kind of attributes, including `id`, and `class` or custom.
    var id: IDAttribute
    var hasAttributes: bool
    var attributes: Table[string, seq[string]]
    while true:
        if p.current.kind == TK_ATTR_CLASS:
            # if p.next.kind != TK_IDENTIFIER:
            #     p.setError("Invalid class name \"$1\"" % [p.next.value])
            #     break
            hasAttributes = true
            if attributes.hasKey("class"):
                if p.next.value in attributes["class"]:
                    p.setError DuplicateClassName % [p.next.value], true
                else: attributes["class"].add(p.next.value)
            else:
                attributes["class"] = @[p.next.value]
            jump p, 2
        elif p.current.kind == TK_ATTR_ID and p.next.kind == TK_IDENTIFIER:
            # TODO check wsno for `#` token
            if htmlNode.hasID():
                p.setError InvalidAttributeId, true
            id = IDAttribute(value: p.next.value)
            if id != nil: htmlNode.id = id
            jump p, 2
        elif p.current.kind in {TK_IDENTIFIER, TK_STYLE} and p.next.kind == TK_ASSIGN:
            # TODO check wsno for other `attr` token
            p.current.kind = TK_IDENTIFIER
            let attrName = p.current.value
            jump p
            if p.next.kind != TK_STRING:
                p.setError InvalidAttributeValue % [attrName], true
            if attributes.hasKey(attrName):
                p.setError DuplicateAttributeKey % [attrName], true
            else:
                attributes[attrName] = @[p.next.value]
                hasAttributes = true
            jump p, 2
        elif p.current.kind == TK_COLON:
            if p.next.kind notin {TK_STRING, TK_VARIABLE}:
                # Handle string content assignment or enter in a multi dimensional nest
                p.setError InvalidTextNodeAssignment % [htmlNode.nodeName], true
            else:
                jump p
                var varName: string
                if p.current.kind == TK_VARIABLE:
                    varName = p.current.value
                    jit p
                p.current.pos = htmlNode.meta.column # get base column from `htmlMeta` node
                if (p.current.line == p.next.line) and not p.next.isEOF and (p.next.kind != TK_AND):
                    p.setError InvalidIndentation, true
                elif (p.next.line > p.current.line) and (p.next.pos > p.current.pos):
                    p.setError InvalidIndentation, true
                var currentTextValue = p.current.value
                var nodeConcat: seq[HtmlNode]
                let col = p.current.pos
                let line = p.current.line
                if p.next.kind == TK_AND:
                    # If provided, Tim can handle string concatenations like
                    # a: "Click here" & span: "to buy" which output to
                    # <a>Click here <span>to buy</span</a>
                    if p.next.line == p.current.line:
                        # handle inline string concatenations using `&` separator
                        jump p
                        while true:
                            if p.current.line != line: break
                            if p.current.kind == TK_AND:
                                jump p
                                continue
                            elif p.current.kind in {TK_STRING, TK_VARIABLE}:
                                nodeConcat.add newTextNode(p.current.value, (col, nodeIndent, line, 0, 0))
                            jump p
                    else:
                        p.setError InvalidIndentation, true
                var htmlTextNode = newTextNode(currentTextValue, (col, nodeIndent, line, 0, 0), nodeConcat)
                if varName.len != 0:
                    htmlTextNode.varAssignment = newVariableNode(varName, "")
                    jump p
                htmlNode.nodes.add(htmlTextNode)
            break
        else: break

    if hasAttributes:
        for attrName, attrValues in attributes.pairs:
            htmlNode.attributes.add(HtmlAttribute(name: attrName, value: attrValues.join(" ")))
        hasAttributes = false
    clear(attributes)

template parseIteration(p: var Parser, interationNode: IterationNode): untyped =
    if p.next.kind != TK_VARIABLE:
        p.setError InvalidIterationMissingVar, true
    jump p
    let varItemName = p.current.value
    if p.next.kind != TK_IN:
        p.setError InvalidIteration, true
    jump p
    if p.next.kind != TK_VARIABLE:
        p.setError InvalidIterationMissingVar, true
    iterationNode.varItemName = varItemName
    iterationNode.varItemsName = p.next.value
    jump p, 2
    jit p  # enable JIT compilation flag

template parseCondition(p: var Parser, conditionNode: ConditionalNode): untyped =
    ## Parse and validate given ConditionalNode 
    var compToken: TokenTuple
    var varNode1, varNode2: VariableNode
    var comparatorNode: ComparatorNode
    while true:
        if p.current.kind == TK_IF and p.next.kind != TK_VARIABLE:
            p.setError InvalidConditionalStmt, true
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
            p.setError InvalidConditionalStmt, true
        break
    jit p

template parseDeferBlock(p: var Parser) =
    ## Parse `defer` block statements
    ## TODO