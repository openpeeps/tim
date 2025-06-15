# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim
from std/net import Port, `$`
import pkg/[nyml, semver]

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
    version*: string
    license*, description*: string
    requires*: seq[string]
    case `type`*: ConfigType
    of typeProject:
      compilation*: CompilationSettings
    else: discard
    browser_sync*: BrowserSync

proc `$`*(c: TimConfig): string = 
  jsony.toJson(c)

# when isMainModule:
#   const sample = """
# name: "bootstrap"
# type: package
# version: 0.1.0
# author: OpenPeeps
# license: MIT
# description: "Bootstrap v5.x components for Tim Engine"
# git: "https://github.com/openpeeps/bootstrap.timl"

# requires:
#   - tim >= 0.1.4
#   """
#   echo fromYaml(sample, TimConfig)
