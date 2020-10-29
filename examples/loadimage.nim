#
# nimble install https://github.com/mrhdias/fastkiss
# nim c -d:ssl -r loadimage.nim
# http://example:8080/
#
import fastkiss
import httpclient
import asyncfile
import os
from strutils import `%`

const
  remoteImg = "https://raw.githubusercontent.com/mrhdias/fastkiss/master/examples/test.jpg"


proc getImage(): Future[string] {.async.} =
  let client = newAsyncHttpClient()

  let file = openAsync(getTempDir() / "test.jpg", fmWrite)
  let data = await client.getContent(remoteImg)
  await file.write(data)
  file.close()

  return getTempDir() / "test.jpg"


proc oneshot(req: Request) {.async.} =
  let filepath = await getImage()

  try:
    req.response.headers["content-type"] = "image/jpeg"
    req.response.headers["keep-alive"] = "timeout=50, max=200"
    let filesize = cast[int](getFileSize(filepath))

    let file = openAsync(filepath, fmRead)
    let data = await file.readAll()
    respond data
    file.close()

    removeFile(filepath)

  except OSError as e:
    echo "Log: $1: $2" % [e.msg, filepath]


proc parts(req: Request) {.async.} =
  let filepath = await getImage()

  try:
    req.response.headers["content-type"] = "image/jpeg"
    let filesize = cast[int](getFileSize(filepath))

    let file = openAsync(filepath, fmRead)

    const chunkSize = 8*1024
    var remainder = filesize
    while remainder > 0:
      let data = await file.read(min(remainder, chunkSize))
      remainder -= data.len
      resp data # respond in multiple parts

    file.close()
    
    removeFile(filepath)

  except OSError as e:
    echo "Log: $1: $2" % [e.msg, filepath]


proc home(req: Request) {.async.} = """
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width">
    <title>Test</title>
  </head>
  <body>
    Response:
    <ul>
      <li><a href="/oneshot">one-shot</a></li>
      <li><a href="/parts">parts</a></li>
    </ul>
  </body>
</html>""".respond


proc main() =
  let app = newApp()
  app.config.port = 9000 # optional if default port

  app.get("/", home)
  app.get("/oneshot", oneshot)
  app.get("/parts", parts)

  app.run()

main()
