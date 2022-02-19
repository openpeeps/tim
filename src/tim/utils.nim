import std/macros

# if conditionNode != nil: conditionNode.nodes.add(p.parentNode)
# else: p.statements.add(p.parentNode)
# p.parentNode = nil
# todo better a template
macro skipNilElement*(): untyped =
    nnkStmtList.newTree(
        nnkIfStmt.newTree(
            nnkElifBranch.newTree(
                nnkInfix.newTree(
                    newIdentNode("=="),
                    newIdentNode("htmlNode"),
                    newNilLit()
                ),
                nnkStmtList.newTree(
                    nnkCommand.newTree(
                        newIdentNode("jump"),
                        newIdentNode("p")
                    ),
                    nnkContinueStmt.newTree(
                        newEmptyNode()
                    )
                )
            )
        )
    )