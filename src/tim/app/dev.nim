# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, osproc, strutils, sequtils, uri, httpclient]

import pkg/[semver, nyml]
import pkg/kapsis/[cli, runtime]

import ../pm/[configurator, manager, remote]

#
# CLI command `init` a new package
#
proc initCommand*(v: Values) =
  ## Initializes a new Tim Engine package
  ## at the current working directory
  # note `displayError` will block the execution
  # so we can use it to inform user about errors and
  # stop the execution of the command
  let currDirPath = getCurrentDir()
  let currDir = currDirPath.extractFilename()
  var pkgName =
    if v.has"pkg":
      v.get("pkg").getStr
    else:  
      # if no name provided, will prompt user for a package name
      prompt("Package name: ", default = currDir).toLowerAscii()

  if not pkgName.validIdentifier():
    displayError("Invalid package name: `$1`. Package name must be a valid identifier" % [pkgName], quitProcess = true)

  if pkgName == currDir.toLowerAscii():
    # sometimes the pkgName can be a directory created before
    # so we need to check if the current dir is empty before initializing a new package
    let res = toSeq(walkDir(currDirPath, true, true))
    if res.len > 0:
      displayError("Current directory is not empty. Please, choose another one", quitProcess = true)
  else:
    if dirExists(currDirPath / pkgName):
      displayError("Directory `$1` already exists. Please, choose another name" % [pkgName], quitProcess = true)
  
  let pkgDesc = prompt("Package description: ", default = "A new awesome package for Tim Engine")
  let pkgVersion = prompt("Package version: ", default = "0.1.0")
  let pkgLicense = prompt("Package license: ", default = "MIT")
  
  createDir(currDirPath / pkgName)
  createDir(currDirPath / pkgName / "src")

  const sampleCode = """
var hello = "Tim Engine is Awesome"
echo $hello"""
  writeFile(currDirPath / pkgName / "src" / pkgName & ".timl", sampleCode)

  var timConfig = TimConfig(
    name: pkgName,
    `type`: ConfigType.typePackage,
    description: pkgDesc,
    version: pkgVersion,
    license: pkgLicense,
    requires: @[
      "tim >= 0.2.0"
    ]
  )

  writeFile(currDirPath / pkgName / "tim.config.yml",
    timConfig.generateYaml())


#
# CLI command `install` a package
# 
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
        # case pkgConfig.`type`:
        #   of typePackage:
        #     if not pkgr.hasPackage(pkgConfig.name):
        #       display(("Installing $1@$2" % [pkgConfig.name, pkgConfig.version]))
        #       if pkgr.createPackage(orgName, pkgName, pkgConfig):
        #         displayInfo("Updating Packager DB")
        #         pkgr.updatePackages()
        #         displaySuccess("Done!")
        #     else:
        #       displayInfo("Package $1@$2 is already installed" % [pkgConfig.name, pkgConfig.version])
        #   else:
        #     displayError("Tim projects cannot be installed via Packager. Use git instead")
      else: discard # todo prompt error

#
# CLI Command `remove` an installed package 
#
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


#
# CLI Command `develop` a package
#
proc developCommand*(v: Values) =
  ## Create a symlink to a package in local source
  let pkgName = v.get("pkg").getStr
  let pkgr = manager.initPackageRemote()
  # pkgr.loadPackages() # load database of existing packages
  # if not pkgr.hasPackage(pkgName):
  #   displayError("Package `$1` not found" % [pkgName], quitProcess = true)
  
  # let pkgPath = pkgr.getPackagePath(pkgName)
  # if pkgPath.len == 0:
  #   displayError("Package `$1` is not installed" % [pkgName], quitProcess = true)

  # let srcPath = getCurrentDir() / "src"
  # if not dirExists(srcPath):
  #   createDir(srcPath)

  # let linkPath = srcPath / pkgName
  # if fileExists(linkPath):
  #   displayError("Symlink `$1` already exists. Please, remove it first" % [linkPath], quitProcess = true)

  # createSymlink(pkgPath, linkPath)
  # displaySuccess("Symlink created: `$1` -> `$2`" % [linkPath, pkgPath])