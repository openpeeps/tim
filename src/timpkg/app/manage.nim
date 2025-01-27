# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, osproc, strutils, sequtils, uri, httpclient]
import ../engine/package/[manager, remote]
import ../server/config

import pkg/kapsis/[cli, runtime]
import pkg/[nyml, semver]

proc initCommand*(v: Values) =
  ## Initialize a Tim Engine package
  let currDir = getCurrentDir()
  if walkDir(currDir).toSeq.len > 0:
    displayError("Could not init a package. Directory is not empty")
  let pkgname = currDir.extractFilename
  let configPath = currDir / pkgname & ".config.yaml"
  let username = execCmdEx("git config user.name")
  let pkglicense = ""
  let config = """
name: $1
type: package
version: 0.1.0
author: $2
license: $3
description: "A cool package for Tim Engine"

requires:
  - tim >= 0.1.3
  """ % [pkgname, username.output, pkglicense]
  createDir(currDir / "src")
  writeFile(configPath, config)

proc aliasCommand*(v: Values) =
  ## Creates an alias of a local package.
  ## This command allows to import the local project
  ## using the pkg prefix `@import 'pkg/mypackage'`
  # if walkFiles(getCurrentDir() / "*.config.yaml"):
    # echo "?"
  # execCmdEx("ln -s")
  discard

proc installCommand*(v: Values) =
  ## Install a package from remote GIT sources
  let pkgr = manager.initPackageRemote()
  pkgr.loadPackages() # load database of existing packages
  let pkgUrl = v.get("pkg").getUrl()
  if pkgUrl.scheme.len > 0:
    if pkgUrl.hostname == "github.com":
      let pkgPath = pkgUrl.path[1..^1].split("/")
      # Connect to the remote source and try find a `tim.config.yaml`,
      # Check the `yaml` config file and download the package
      let orgName = pkgPath[0]
      let pkgName = pkgPath[1]
      let res = pkgr.remote.httpGet("repo_contents_path", @[orgName, pkgName, "tim.config.yaml"])
      case res.code
      of Http200:
        let remoteYaml: GithubFileResponse = pkgr.remote.getFileContent(res) # this is base64 encoded
        let pkgConfig: TimConfig = fromYaml(remoteYaml.content.decode(), TimConfig)
        case pkgConfig.`type`:
          of typePackage:
            if not pkgr.hasPackage(pkgConfig.name):
              display(("Installing $1@$2" % [pkgConfig.name, pkgConfig.version]))
              if pkgr.createPackage(orgName, pkgName, pkgConfig):
                displayInfo("Updating Packager DB")
                pkgr.updatePackages()
                displaySuccess("Done!")
            else:
              displayInfo("Package $1@$2 is already installed" % [pkgConfig.name, pkgConfig.version])
          else:
            displayError("Tim projects cannot be installed via Packager. Use git instead")
      else: discard # todo prompt error

proc removeCommand*(v: Values) =
  ## Removes an installed package by name and version (if provided)
  let input = v.get("pkg").getStr.split("@")
  var hasVersion: bool
  let pkgName = input[0]
  let pkgVersion =
    if input.len == 2:
      hasVersion = true; parseVersion(input[1])
    else: newVersion(0,1,0)
  displayInfo("Finding package `" & pkgName & "`")
  let pkgr = manager.initPackageRemote()
  pkgr.loadPackages() # load database of existing packages
  if pkgr.hasPackage(pkgName):
    displaySuccess("Delete package `" & pkgName & "`")
    pkgr.deletePackage(pkgName)
  else:
    displayError("Package `" & pkgName & "` not found")
