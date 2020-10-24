#
#
#       FastKiss HTTP Basic Authentication
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import asyncdispatch, asyncfcgiserver
from strutils import splitWhitespace, startsWith, split, `%`
from base64 import decode

type
  Credentials = object
    username*: string
    password*: string

proc getCredentials*(req: Request): Credentials =

  if req.headers.hasKey("http_authorization") and
      req.headers["http_authorization"].len() > 10 and
      req.headers["http_authorization"].startsWith("Basic "):

    let parts = req.headers["http_authorization"].splitWhitespace(maxsplit=1)

    if parts.len() == 2 and parts[1].len() > 3:
      let credentials = decode(parts[1]).split(':', maxsplit=1)
      if credentials.len() == 2:
        return Credentials(username: credentials[0], password: credentials[1])

  return Credentials(username: "", password: "")


proc authRequired*(req: Request, realm: string = "") {.async.} =
  let htmlpage = """
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<html>
<head><title>401 Unauthorized</title></head>
<body>
<h1>Unauthorized</h1>
<p>This server could not verify that you
are authorized to access the document
requested.  Either you supplied the wrong
credentials (e.g., bad password), or your
browser doesn't understand how to supply
the credentials required.</p>
</body>
</html>
"""
  let headers = newHttpHeaders([
    ("status", "401 Unauthorized"),
    ("WWW-Authenticate", "Basic realm=\"$1\"" % realm),
    ("content-length", $(htmlpage.len())),
    ("content-type", "text/html;charset=utf-8")
  ])
  await req.response(htmlpage, headers, appStatus=401)
