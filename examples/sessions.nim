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
import system/ansi_c


proc getSessionId(headers: HttpHeaders): string = 
  if not headers.hasKey("http_cookie"):
    return ""

  let cookies = parseCookies(headers["http_cookie"])
  return if "session" in cookies: cookies["session"] else: ""


proc showSessionPage(
  req: Request,
  sessions: AsyncSessions) {.async.} =

  let sessionId = req.headers.getSessionId()
  if sessionId != "" and (sessionId in sessions.pool):
    if (let session = sessions.getSession(sessionId); session) != nil:
      req.response.headers["content-type"] = "text/plain;charset=utf-8"
      await req.respond(&"""Hello User {session.map["username"]} Again :-) {sessionId}""")
      # sessions.delSession(sessionId)
    else:
      await req.respond("Session Error!")

    return

  proc timeoutSession(id: string) {.async.} =
    echo "expired session: ", id

  var session: Session
  try:
    session = sessions.setSession()
  except AsyncSessionsError as e:
    await req.respond(e.msg)
    return

  session.map["username"] = "Kiss"
  session.callback = timeoutSession

  req.response.headers["set-cookie"] = &"session={session.id}"
  await req.respond("New Session")


proc main() =

  let sessions = newAsyncSessions(
    sleepTime = 1000, # milliseconds
    sessionTimeout = 30, # seconds
    maxSessions = 100
  )

  let app = newApp()
  app.config.port = 9000 # optional if default port

  # Catch ctrl-c
  addSignal(SIGINT, proc(fd: AsyncFD): bool =
    sessions.cleanAll()
    app.close()
    echo "App shutdown completed! Bye-Bye Kisses :)"
    quit(QuitSuccess)
  )

  # app.get("/sessions", proc (req: Request): Future[void] = showSessionPage(req, sessions))
  # with sugar module
  app.get("/sessions", (req: Request) => showSessionPage(req, sessions))

  app.run()

main()
