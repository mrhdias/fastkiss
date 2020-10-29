#
# nimble install https://github.com/mrhdias/fastkiss
# nim c -r confidential.nim 
# http://example:8080/
#
import fastkiss
import fastkiss/basicauth
from strutils import `%`

#
# "respond(data: string)" is a shortcut for "await req.respond(data: string)"
#
proc showPage(req: Request) {.async.} = """
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
  """.respond


proc showPrivatePage(req: Request) {.async.} =
  let users = {"guest": "0123456789", "mrhdias": "abcdef"}.toTable
  let c = req.getCredentials()

  if not (c.username in users and c.password == users[c.username]):
    await req.authRequired("My Server")
    return

  respond """
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
</html>""" % c.username

proc main() =
  let app = newApp()
  app.config.port = 9000 # optional if default port

  app.get("/", showPage)
  app.get("/auth", showPrivatePage)

  app.run()

main()
