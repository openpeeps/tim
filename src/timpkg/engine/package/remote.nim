# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, httpcore, httpclient, strutils, base64]
import pkg/[jsony, dotenv]

from std/os import existsEnv, getEnv
export base64

type
  SourceType* = enum
    Github = "github_com"
    Gitlab = "gitlab_com"

  GithubFileResponse* = object
    name*, path*, sha*: string
    size*: int64
    url*, html_url*, git_url*,
      download_url*: string
    `type`*: string
    content*: string

  RemoteSource* = object
    apikey*: string
    source: SourceType
    client: HttpClient

let GitHubRemoteEndpoints = newTable({
    "base": "https://api.github.com",
    "repo": "/repos/$1/$2",
    "repo_contents": "/repos/$1/$2/contents",
    "repo_contents_path": "/repos/$1/$2/contents/$3",
    "repo_tags": "/repos/$1/$2/tags",
    "repo_tag_zip": "/repos/$1/$2/zipball/refs/tags/$3",
    "repo_tag_tar": "/repos/$1/$2/tarball/refs/tags/$3",
    "repo_tarball_ref": "/repos/$1/$2/tarball/$3",
})

#
# JSONY hooks
#
# proc parseHook*(s: string, i: var int, v: var Time) =
#   var str: string
#   parseHook(s, i, str)
#   v = parseTime(str, "yyyy-MM-dd'T'hh:mm:ss'.'ffffffz", local())

# proc dumpHook*(s: var string, v: Time) =
#   add s, '"'
#   add s, v.format("yyyy-MM-dd'T'hh:mm:ss'.'ffffffz", local())
#   add s, '"'

proc getRemoteEndpoints*(src: SourceType): TableRef[string, string] =
  case src
  of Github: GitHubRemoteEndpoints
  else: nil

proc getRemotePath*(rs: RemoteSource, path: string,
  args: varargs[string]): string =
  case rs.source
  of Github:
    return GitHubRemoteEndpoints[path]
  else: discard


proc httpGet*(client: RemoteSource,
    path: string, args: seq[string] = @[]
): Response =
  let endpoints = getRemoteEndpoints(client.source)
  let uri = endpoints["base"] & (endpoints[path] % args) 
  result = client.client.request(uri, HttpGet)

proc getFileContent*(client: RemoteSource, res: Response): GithubFileResponse =
  jsony.fromJson(res.body, GithubFileResponse)

proc download*(client: RemoteSource,
    path, tmpPath: string, args: seq[string] = @[]): bool =
  ## Download a file from remote `path` and returns the
  ## local path to tmp file
  let endpoints = getRemoteEndpoints(client.source)
  let uri = endpoints["base"] & (endpoints[path] % args)
  client.client.downloadFile(uri, tmpPath)
  result = true

proc initRemoteSource*(pkgrHomeDir: string, source: SourceType = Github): RemoteSource =
  result.source = source
  let key = "timengine_" & $source & "_apikey"
  dotenv.load(pkgrHomeDir, ".tokens")
  for x in SourceType:
    if existsEnv($x) and source == x:
      result.apikey = getEnv($x)
  result.client = newHttpClient()
  result.client.headers = newHttpheaders({
    "Authorization": "Bearer " & result.apikey
  })

# proc getRemoteSourceFile*(rs: RemoteSource)
# echo getRemotePath(RemoteSource(), "base")