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

proc formData*(req: Request): FormTableRef[string, string] =
  req.body.formdata

proc formFiles*(req: Request): FormTableRef[string, FileAttributes] =
  req.body.formfiles

proc newApp*(): AsyncFCGIServer = newAsyncFCGIServer()

when not defined(testing) and isMainModule:
  proc main() =
    let app = newApp()
    app.get("/", proc (req: Request) {.async.} =
      await req.response("Hello World!")
    )
    app.run()
  main()
