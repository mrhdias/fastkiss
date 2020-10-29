#
# nimble install https://github.com/mrhdias/fastkiss
# nim c -r app.nim
# http://example:8080/
#
# "resp(data: string)" is a shortcut for "await req.resp(data: string)"
#
import fastkiss
import asyncfile
import os
from strutils import `%`

const staticDir = "static"

proc fileGetContents(staticDir, filename: string): Future[string] {.async.} =
  try:
    let file = openAsync(staticDir / filename, fmRead)
    let data = await file.readAll()
    file.close()
    return data
  except OSError as e:
    return "$1: $2" % [e.msg, staticDir / filename]

proc main() =
  let app = newApp()
  app.config.port = 9000 # optional if default port
  app.config.staticDir = staticDir

  app.get("/", proc (req: Request) {.async.} =
    resp await staticDir.fileGetContents("html/header.html")
    resp await staticDir.fileGetContents("html/body.html")
    resp await staticDir.fileGetContents("html/footer.html")
  )

  app.run()

main()
