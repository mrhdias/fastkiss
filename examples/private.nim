#
# nimble install https://github.com/mrhdias/fastkiss
# nim c -r private.nim 
# http://example:8080/
#
import fastkiss
import fastkiss/basicauth
from strutils import `%`

proc showPage(req: Request) {.async.} =
  let htmlpage = """
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width">
    <title>BasicAuth Test</title>
  </head>
  <body>
    <a href="auth">Private Page</a>
  </body>
</html>
"""
  await req.response(htmlpage)


proc showPrivatePage(req: Request) {.async.} =
  let users = {"guest": "0123456789", "mrhdias": "abcdef"}.toTable
  let c = req.getCredentials()

  if not (c.username in users and c.password == users[c.username]):
    await req.authRequired("My Server")
    return

  let htmlpage = """
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width">
    <title>BasicAuth Test Private</title>
  </head>
  <body>
    Success <strong>$1</strong>!
  </body>
</html>
""" % c.username

  await req.response(htmlpage)


proc main() =
  let app = newAsyncFCGIServer()
  app.config.port = 9000 # optional if default port

  app.get("/", showPage)
  app.get("/auth", showPrivatePage)

  app.run()

main()
