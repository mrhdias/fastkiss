#
# nimble install https://github.com/mrhdias/fastkiss
# nim c -r sessions.nim 
# http://example:8080/sessions
#
import fastkiss
import fastkiss/asyncsessions
from strutils import `%`
from strformat import `&`
from cookies import parseCookies
import sugar


proc getSessionId(headers: HttpHeaders): string = 
  if not headers.hasKey("cookie"):
    return ""

  let cookies = parseCookies(headers["cookie"])
  if "session" in cookies:
    return cookies["session"]

  return ""


proc showSessionPage(
  req: Request,
  sessions: AsyncSessions) {.async.} =

  let sessionId = req.headers.getSessionId()
  if sessionId != "" and (sessionId in sessions.pool):
    if (let session = sessions.getSession(sessionId); session) != nil:
      await req.response(
        &"""Hello User {session.map["username"]} Again :-) {sessionId}""",
        newHttpHeaders([
          ("content-type", "text/plain;charset=utf-8")
        ]),
        200
      )
      # sessions.delSession(sessionId)
    else:
      await req.response("Session Error!")

    return

  proc timeoutSession(id: string) {.async.} =
    echo "expired session: ", id

  var session = sessions.setSession()
  session.map["username"] = "Kiss"
  session.callback = timeoutSession

  await req.response(
    "New Session",
    newHttpHeaders([
      ("Set-Cookie", &"session={session.id}"),
      ("content-type", "text/html;charset=utf-8")
    ]),
    200
  )


proc main() =

  let sessions = newAsyncSessions(
    sleepTime=1000,
    sessionTimeout=30
  )

  let app = newAsyncFCGIServer()
  app.config.port = 9000 # optional if default port

  # app.get("/sessions", proc (req: Request): Future[void] = showSessionPage(req, sessions))
  # with sugar module
  app.get("/sessions", (req: Request) => showSessionPage(req, sessions))

  app.run()

main()
