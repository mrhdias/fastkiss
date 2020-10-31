#
#         FastKiss Async FastCgi Server
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import fastkiss/asyncfcgibodyparser
import fastkiss/asyncfcgiserver
import json

export asyncfcgibodyparser
export asyncfcgiserver

template respond*(data: string | JsonNode) {.dirty.} =
  ## One time request response
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   await req.respond(data: string | JsonNode)
  await req.respond(data)

template resp*(data: string) {.dirty.} =
  ## Breaks the response to the request into multiple parts
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   await req.resp(data: string)
  await req.resp(data)

template formData*(): FormTableRef[string, string] =
  ## Object with the value of the fields from submitted html forms without files.
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   req.body.formdata
  req.body.formdata

template formFiles*(): FormTableRef[string, FileAttributes] =
  ## Object with the value of the input file fields from submitted html forms.
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   req.body.formfiles
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
