#
# nimble install https://github.com/mrhdias/fastkiss
# nim c -r app.nim
# http://example:8080/
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
  let app = newAsyncFCGIServer()
  app.config.port = 9000 # optional if default port
  app.config.staticDir = staticDir

  app.get("/", proc (req: Request) {.async.} =

    var contents = ""
    contents.add(await staticDir.fileGetContents("html/header.html"))
    contents.add(await staticDir.fileGetContents("html/body.html"))
    contents.add(await staticDir.fileGetContents("html/footer.html"))

    await req.response(contents)
  )

  app.run()

main()
