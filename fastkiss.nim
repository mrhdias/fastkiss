#
#         FastKiss Async FastCgi Server
#        (c) Copyright 2021 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import fastkiss/asyncfcgibodyparser
import fastkiss/asyncfcgiserver
import json
from regex import RegexMatch

export asyncfcgibodyparser
export asyncfcgiserver

template matches*(): RegexMatch =
  ## Result from matching operations in the req.url.path. 
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   req.matches
  req.matches

template groupCaptures*(m: RegexMatch, i: int): seq[string] =
  ## Return seq of captured req.url.path text by group number i.
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   matches.group(i, req.url.path)
  m.group(i, req.url.path)

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

template sendFile*(filepath: string) {.dirty.} =
  ## Respond with a file to the request.
  ## It is a shortcut to the expression:
  ## .. code-block::nim
  ##   await req.sendFile(filepath: string)
  await req.sendFile(filepath)

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
