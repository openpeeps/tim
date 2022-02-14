import std/macros

# dumpAstGen:
#     if conditionNode != nil:
#         conditionNode.nodes.add(p.parentNode)
#     else:
#         p.statements.add(p.parentNode)
#     p.parentNode = nil
#     conditionNode = nil

macro registerNode*(conditionNode: typed): untyped =
    # if conditionNode != nil:
    #     conditionNode.nodes.add(p.parentNode)
    # else:
    #     p.statements.add(p.parentNode)
    # p.parentNode = nil
    nnkStmtList.newTree(
      nnkIfStmt.newTree(
        nnkElifBranch.newTree(
          nnkInfix.newTree(
            newIdentNode("!="),
            newIdentNode(conditionNode.strVal),
            newNilLit()
          ),
          nnkStmtList.newTree(
            nnkCall.newTree(
              nnkDotExpr.newTree(
                nnkDotExpr.newTree(
                  newIdentNode(conditionNode.strVal),
                  newIdentNode("nodes")
                ),
                newIdentNode("add")
              ),
              nnkDotExpr.newTree(
                newIdentNode("p"),
                newIdentNode("parentNode")
              )
            )
          )
        ),
        nnkElse.newTree(
          nnkStmtList.newTree(
            nnkCall.newTree(
              nnkDotExpr.newTree(
                nnkDotExpr.newTree(
                  newIdentNode("p"),
                  newIdentNode("statements")
                ),
                newIdentNode("add")
              ),
              nnkDotExpr.newTree(
                newIdentNode("p"),
                newIdentNode("parentNode")
              )
            )
          )
        )
      ),
      nnkAsgn.newTree(
        nnkDotExpr.newTree(
          newIdentNode("p"),
          newIdentNode("parentNode")
        ),
        newNilLit()
      ),
      nnkAsgn.newTree(
        newIdentNode(conditionNode.strVal),
        newNilLit()
      )
    )
