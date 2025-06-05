# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://tim-engine.com

const
  ErrorFmt* = "$1($2:$3): $4"

  # lex errors
  ErrUnknownOperator* = "unknown operator: '$1'"
  ErrUntermStringLit* = "unterminated string literal"
  ErrUntermStroppedIdent* = "unterminated stropped identifier"
  ErrUnexpectedChar* = "unexpected character: '$1'"
  ErrXExpectedGotY* = "$1 expected, got $2"
  ErrOpExpectedGotY* = "'$1' expected, got $2"

  # parse errors
  ErrUnmatchedParen* = "right paren ')' expected"
  ErrGenericIllegalInProcType* = "generic params are not allowed in proc types"
  ErrAssignOpExpected* = "assignment operator '=' expected, got '$1'"
  ErrMissingToken* = "missing '$1'"
  ErrXExpected* = [
    1: "'$#' expected",
    2: "'$#' or '$#' expected",
  ]
  ErrProcNameExpected* = "proc name expected"
  ErrProcParamsExpected* = "proc params expected"

  # compile errors
  ErrShadowResult* = "variable shadows implicit 'result' variable"
  ErrLocalRedeclaration* = "'$1' is already declared in this scope"
  ErrGlobalRedeclaration* = "'$1' is already declared"
  ErrUndefinedReference* = "undeclared identifier '$1'"
  ErrImmutableReassignment* = "'$1' cannot be assigned to"
  ErrTypeMismatch* = "type mismatch: got <$1>, but expected <$2>"
  ErrTypeMismatchChoice* = "type mismatch: got <$1>, but expected one of:$2"
  ErrNotAProc* = "'$1' is not a procedure"
  ErrInvalidField* = "'$1' is not a valid field"
  ErrNonExistentField* = "field '$1' does not exist for <$2>"
  ErrInvalidAssignment* = "cannot assign to '$1'"
  ErrTypeIsNotAnObject* = "'$1' is not an object type"
  ErrObjectFieldsMustBeInitialized* = "all object fields must be initialized"
  ErrFieldInitMustBeAColonExpr* =
    "field initializer must be a colon expression: 'a: b'"
  ErrValueIsVoid* = "value does not have a valid type (its type is <void>)"
  ErrOnlyUsableInABlock* =
    "'$1' can only be used inside a loop or a block statement"
  ErrOnlyUsableInALoop* = "'$1' can only be used inside a loop"
  ErrOnlyUsableInAProc* = "'$1' can only be used inside a proc"
  ErrOnlyUsableInAMacro* = "'$1' can only be used inside a macro"
  ErrOnlyUsableInAnIterator* = "'$1' can only be used inside an iterator"
  ErrVarMustHaveValue* = "variable must have a value"
  ErrIterMustHaveYieldType* = "iterator must have a non-void yield type"
  ErrSymKindMismatch* = "$1 expected, but got $2"
  ErrInvalidSymName* = "'$1' is not a valid symbol name"
  ErrCouldNotInferGeneric* =
    "could not infer generic params for '$1'. specify them explicitly"
  ErrNotGeneric* = "'$1' is not generic"
  ErrGenericArgLenMismatch* = "got $1 generic arguments, but expected $2"
  ErrUseOrDiscard* = "expression $1 is of type `$2` and has to be used or discarded"
  ErrExportOnlyTopLevel* = "exporting symbols is only allowed at the top level"
  WarnEmptyStmt* = "Empty statement is redundant"
  WarnModuleAlreadyImported* = "Module '$1' is already imported"
  ErrTypeNotConcrete* = "type `$1` is not concrete"
  
  ErrBadIndentation* = "Bad indentation"
  ErrUnexpectedToken* = "Unexpected token: `$1`"