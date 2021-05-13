import asyncdispatch
import ../fastkiss

var stop = false

proc shutdown(app: AsyncFCGIServer) {.async.} =
  while true:
    if stop:
      app.close()
      echo "App test shutdown completed."
      quit(QuitSuccess)

    await sleepAsync(2000)
    echo "Start the app test shutdown ..."
    stop = true


proc main() =
  let app = newAsyncFCGIServer()
  app.config.port = 9000 # optional if default port

  asyncCheck app.shutdown()

  app.get("/", proc (req: Request) {.async.} =
    await req.respond("Hello World!")
  )

  app.run()

main()
