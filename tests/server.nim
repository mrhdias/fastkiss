import ../fastkiss

proc main() =
  let app = newAsyncFCGIServer()
  app.config.port = 9000 # optional if default port

  app.get("/", proc (req: Request) {.async.} =
    await req.response("Hello World!")
  )

  app.run()

main()
