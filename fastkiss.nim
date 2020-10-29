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

template respond*(data: string) {.dirty.} =
  ## One time request response
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   await req.respond(data: string)
  await req.respond(data)

template resp*(data: string) {.dirty.} =
  ## Breaks the response to the request into multiple parts
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   await req.resp(data: string)
  await req.resp(data)


proc formData*(req: Request): FormTableRef[string, string] =
  req.body.formdata


proc formFiles*(req: Request): FormTableRef[string, FileAttributes] =
  req.body.formfiles

proc newApp*(): AsyncFCGIServer = newAsyncFCGIServer()

when not defined(testing) and isMainModule:
  proc main() =
    let app = newApp()
    app.get("/", proc (req: Request) {.async.} =
      await req.respond("Hello World!")
    )
    app.run()
  main()
