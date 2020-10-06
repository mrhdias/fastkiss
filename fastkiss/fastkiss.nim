
#
#         FastKiss Async FastCgi Server
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import fastkiss/asyncfcgibodyparser
import fastkiss/asyncfcgiserver

export asyncfcgibodyparser
export asyncfcgiserver

when not defined(testing) and isMainModule:
  proc main() =
    let app = newAsyncFCGIServer()
    app.get("/", proc (req: Request) {.async.} =
      await req.response("Hello World!")
    )
    app.run()
  main()
