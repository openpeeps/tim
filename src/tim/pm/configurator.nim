# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim
from std/net import Port, `$`

import pkg/[nyml, semver]

when not defined napibuild:
  import pkg/voodoo/parsers/voojson

export `$`

type
  TargetSource* = enum
    tsNim    = "nim"
    tsJS     = "js"
    tsHtml   = "html"
    tsRuby   = "rb"
    tsPython = "py"

  BrowserSync* = ref object
    port*: Port
    delay*: uint # ms todo use jsony hooks + std/times

  ConfigType* = enum
    typeProject = "project"
    typePackage = "package"

  Requirement* = object
    id: string
    version: Version

  PolicyName* = enum
    policyAny = "any"
    policyStdlib = "stdlib"
    policyPackages = "packages"
    policyImports = "imports"
    policyLoops = "loops"
    policyConditionals = "conditionals"
    policyAssignments = "assignments"

  CompilationPolicy* = object
    allow: set[PolicyName]

  CompilationSettings* = object
    target*: TargetSource
    source*, output*: string
    layoutsPath*, viewsPath*, partialsPath*: string
    policy*: CompilationPolicy
    release*: bool

  TimConfig* = ref object
    name*: string
      ## Name of the package or project
      ## This must be a valid identifier
    version*: string
      ## The version of the package
    description*: string
      ## A short description of the package
    license*: string
      ## The license of the package
      ## See https://spdx.org/licenses/ for more information
    requires*: seq[string]
      ## A list of requirements for the package
      ## Each requirement must be a valid identifier
      ## and can be a version range, e.g. "tim >= 0.1.0"
    case `type`*: ConfigType
    of ConfigType.typeProject:
      compilation*: CompilationSettings
      browser_sync*: BrowserSync
    else: discard

when not defined napibuild:
  proc generateYaml*(c: TimConfig): string =
    ## Generate a YAML representation of the TimConfig
    ## This is used to generate the `tim.yml` file
    let str =
      if c.`type` == ConfigType.typePackage:
        voojson.toJson(c, JsonOptions(
          skipFields: @["type", "compilation", "browser_sync"]
        ))
      else:
        toJson(c)
    dump(voojson.fromJson(str))

  proc `$`*(c: TimConfig): string = 
    ## Generate a string representation of the TimConfig
    ## using `pkg/voodoo`
    voojson.toJson(c)
