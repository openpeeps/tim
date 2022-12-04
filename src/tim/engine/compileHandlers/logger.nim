# High-performance, compiled template engine inspired by Emmet syntax.
#
# (c) 2022 Tim Engine is released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/tim

type
    ErrorType* = enum
        Warning, Fatal

    Message* = ref object
        errorType: ErrorType
        message*: string

    Logger* = object
        logs*: seq[Message]

proc add*(logger: var Logger, message: string, errorType: ErrorType = Warning) =
    logger.logs.add(Message(message: message, errorType: errorType))