#
#       FastKiss Async FastCgi Body Parser
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import asyncdispatch, asyncfile
from os import `/`, fileExists, getFileSize,
  existsOrCreateDir, getTempDir
import tables
import httpcore
from strutils import isDigit, parseInt, `%`, intToStr,
  rsplit, split, startsWith, removeSuffix, fromHex
from strformat import `&`
import formtable

export formtable

type
  FileAttributes* = object
    filename*: string
    content_type*: string
    filesize*: BiggestInt

  BodyData* = ref object
    formdata*: FormTableRef[string, string]
    formfiles*: FormTableRef[string, FileAttributes]
    data*: string
    multipart*: bool

type
  AsyncHttpBodyParser* = ref object of RootObj
    initialized*: bool
    workingDir*: string
    onData*: proc (data: string): Future[void] {.closure, gcsafe.}
    body*: BodyData

  HttpBodyParserError* = object of ValueError

# const debug = true

proc splitHeader(s: string): array[2, string] =
  var p = find(s, ':')
  if not (p > 0 and p < s.high):
    return ["", ""]

  let head = s[0 .. p-1]
  p += 1; while s[p] == ' ': p += 1
  return [head, s[p .. ^1]]


proc splitContentDisposition(s: string): (string, seq[string]) =
  var parts = newSeq[string]()

  var
    firstParameter = ""
    buff = ""
  var p = 0

  while p < s.len:
    if s[p] == ';':
      if p > 0 and s[p-1] == '"':
        parts.add(buff)
        buff = ""

      if firstParameter.len == 0:
        if buff.len == 0: break
        firstParameter = buff
        buff = ""

      if buff == "":
        p += 1; while p < s.len and s[p] == ' ': p += 1
        continue
    buff.add(s[p])
    p += 1

  if buff.len > 0 and buff[^1] == '"':
    parts.add(buff)

  return (firstParameter, parts)


proc incCounterInFilename(filename: string): string =
  if filename.len == 0: return ""

  var p = filename.high
  if p > 0 and filename[p] == ')':
    var strnumber = ""
    while isDigit(filename[p-1]):
      strnumber = filename[p-1] & strnumber
      p -= 1

    if p > 1 and filename[p-1] == '(' and filename[p-2] == ' ':
      let number: int = parseInt(strnumber)
      if number > 0:
        return "$1 ($2)" % [filename[0 .. p - 3], intToStr(number + 1)]

  return "$1 (1)" % filename


proc testFilename(tmpdir: string, filename: var string): string =
  if filename.len == 0:
    filename = "unknown"

  var path = ""
  # var count = 0;
  while true:
    path = tmpdir / filename
    if not fileExists(path):
      return path

    let filenameparts = filename.rsplit(".", maxsplit=1)
    filename = if filenameparts.len == 2: "$1.$2" % [incCounterInFilename(filenameparts[0]), filenameparts[1]]
      else: incCounterInFilename(filename)

  return path


#
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Disposition
#
proc processHeader(rawHeaders: seq[string]): Future[(string, Table[string, string])] {.async.} =
  var
    formname = ""
    filename = ""
    content_type = ""

  for rawHeader in rawHeaders:
    # echo ">> Raw Header: " & rawHeader
    let h = splitHeader(rawHeader)
    # h[0] -> Head
    # h[1] -> Tail

    if h[0] == "Content-Disposition":
      let (firstParameter, contentDispositionParts) = splitContentDisposition(h[1])
      if firstParameter != "form-data": continue
      for contentDispositionPart in contentDispositionParts:
        let pair = contentDispositionPart.split("=", maxsplit=1)
        if pair.len == 2:
          let value = if pair[1][0] == '"' and pair[1][^1] == '"': pair[1][1 .. pair[1].len-2] else: pair[1]
          # echo ">> Pair: " & pair[0] & " = " & value
          if value.len > 0:
            if pair[0] == "name":
              formname = value
          if pair[0] == "filename":
            filename = value

    elif h[0] == "Content-Type":
      # echo ">> Raw Header: " & h[0] & " = " & h[1]
      contentType = h[1]

  var formdata = initTable[string, string]()
  if filename.len > 0 or contentType.len > 0:
    formdata["filename"] = filename
    formdata["content-type"] = contentType
  else:
    formdata["data"] = ""

  # echo ">> Form Data: " & $formdata

  return (formname, formdata)



proc getBoundary(contentType: string): string =
  let parts = contentType.split(';')
  if parts.len == 2 and parts[0] == "multipart/form-data":
    let idx = if parts[1][0] == ' ': 1 else: 0
    if parts[1][idx .. ^1].startsWith("boundary="):
      let boundary = parts[1][(idx + 9) .. ^1]
      return &"--{boundary}"
  return ""


proc parse*(self: AsyncHttpBodyParser, headers: HttpHeaders) =
  # if debug: echo "Begin Body"

  template formFiles(): FormTableRef[string, FileAttributes] =
    self.body.formfiles

  template formData(): FormTableRef[string, string] =
    self.body.formdata

  if not (headers.hasKey("content_type") and headers.hasKey("content_length") and (parseInt(headers["content_length"]) > 0)):
    return

  # if debug: echo "Content-Type: ", headers["content_type"]

  if (headers["content_type"].len > 20) and
    (headers["content_type"][0 .. 19] == "multipart/form-data;"):

    let boundary = getBoundary(headers["content_type"])
    if boundary == "":
      return

    self.body.multipart = true
    # if debug: echo "Have Boundary"
    let uploadDirectory = self.workingDir

    proc initFileAttributes(form: Table[string, string]): FileAttributes =
      var attributes: FileAttributes
      attributes.filename = if form.hasKey("filename"): form["filename"] else: "unknown"
      attributes.content_type = if form.hasKey("content_type"): form["content_type"] else: ""
      attributes.filesize = 0

      return attributes

    var
      findHeaders = false
      readHeader = false
      readContent = true
      readBoundary = true

    var countBoundaryChars = 0

    var
      bag = ""
      buffer = ""

    var
      pc = '\0'
      tc = '\0'

    var rawHeaders = newSeq[string]()
    var formname = ""
    var output: AsyncFile

    # if debug: echo "Multipart Form Data"
    proc onData(data: string) {.async.} =
      # if debug: echo "ON BODY MULTIPART..."

      for c in data:

        pc = tc
        tc = c

        if readContent:
          # echo "Read Content"
 
          if readBoundary and c == boundary[countBoundaryChars]:
            if countBoundaryChars == high(boundary):
              # echo "Boundary Found"
              # echo "dubug: bag: >", bag, "< baglen: ", bag.len, " lastchar: >", c, "< buffer: >", buffer, "<"

              buffer.add(c)

              if ((let diff = buffer.len - boundary.len); diff) > 0:
                bag.add(buffer[0 .. diff - 1])

              if bag.len > 0:
                if bag.len > 1:
                  bag.removeSuffix("\c\L")
                
                if formFiles.hasKey(formname) and
                    formFiles.len(formname) > 0 and
                    formFiles.last(formname).filename.len > 0:
                  await output.write(bag)
                elif formData.hasKey(formname):
                  ### add values to sequence
                  formData[formname] = bag
                bag = ""

              if formFiles.hasKey(formname) and
                  formFiles.len(formname) > 0 and
                  formFiles.last(formname).filename.len > 0:
                output.close()
                # looking inside sequence files for the last insertion
                formFiles.table[formname][^1].filesize = getFileSize(uploadDirectory / formFiles.table[formname][^1].filename)

              findHeaders = true # next move find the headers or stop if find "--"
              readContent = false
              readHeader = false
              countBoundaryChars = 0
              continue

            buffer.add(c)
            countBoundaryChars += 1
            continue

          if buffer.len > 0:
            bag.add(buffer)
            buffer = ""

          bag.add(c)

          countBoundaryChars = 0
          continue


        if readHeader:
          # echo "Read Header"

          if c == '\c':
            continue

          if c == '\L' and pc == '\c':
            if buffer.len == 0: # if double newline separator
              readHeader = false
              readContent = true # next move read content

              if rawHeaders.len > 0:
                let (name, form) = await processHeader(rawHeaders)
                formname = name
                if form.hasKey("filename"):
                  var fileattr = initFileAttributes(form)
                  if name notin formFiles:
                    formFiles[name] = newSeq[FileAttributes]()
                  formFiles[name] = fileattr
                  discard existsOrCreateDir(uploadDirectory)

                  if form.hasKey("content-type"):
                    formFiles.table[formname][^1].content_type = form["content-type"]

                  var filename = form["filename"]
                  if (let fullpath = testFilename(uploadDirectory, filename); fullpath.len) > 0:
                    formFiles.table[formname][^1].filename = filename
                    output = openAsync(fullpath, fmWrite)

                else:
                  ### check if form["data"] is always empty
                  if name notin formData:
                    formData[name] = newSeq[string]()

                rawHeaders.setLen(0)
                continue

            rawHeaders.add(buffer)
            buffer = ""
            bag = ""
            continue

          buffer.add(c)
          continue


        if findHeaders:
          # echo "Find Headers"

          if pc == '-' and c == '-': # end of multipart form data
            # buffer = "" # xxxxxxxx necessary?
            break

          if c == '-':
            buffer.add(c)
          elif c == '\L' and pc == '\c':
            readHeader = true # next move read the haeder
            buffer = ""

        # echo "Multipart/data malformed request syntax"

    self.onData = onData

  elif headers["content_type"] == "application/x-www-form-urlencoded":
    # if debug: echo "WWW Form Urlencoded"

    var
      name = ""
      buffer = ""
      encodedchar = ""

    proc onData(data: string) {.async.} =

      proc getPair(name, buffer: string): (string, string) =
        return if name.len == 0 and buffer.len > 0: (buffer, "")
          elif name.len > 0: (name, buffer)
          else: ("", "")

      for c in data:

        if c == '&':
          let (key, value) = getPair(name, buffer)
          if key.len > 0:
            # echo "0 - Key: ", key, " Value: ", value
            formData[key] = value
          name = ""
          buffer = ""
          continue

        if name.len > 0 and c == '&':
          formData[name] = buffer
          name = ""
          buffer = ""
          continue

        if c == '=':
          name = buffer
          buffer = ""
          continue

        if encodedchar.len > 1:
          encodedchar.add(c)
          if (encodedchar.len - 1) mod 3 == 0:
            let decodedchar = chr(fromHex[int](encodedchar))
            if decodedchar != '\x00':
              buffer.add(decodedchar)
              encodedchar = ""
              continue
          continue

        if c == '%':
          encodedchar.add("0x")
          continue

        if c == '+':
          buffer.add(' ')
          continue

        buffer.add(c)

      let (key, value) = getPair(name, buffer)
      if key.len > 0:
        # echo "1 - Key: ", key, " Value: ", value
        formData[key] = value

    self.onData = onData

  #[ Code to be removed
  elif headers["content_type"] == "application/json":
    ### Json ###
    proc onData(data: string) {.async.} =
      if data.len > 0:
        self.body.data.add(data)

    self.onData = onData
  ]#

  else:
    # "application/json" or any other content type
    proc onData(data: string) {.async.} =
      if data.len > 0:
        self.body.data.add(data)

    self.onData = onData


func `$`*(body: BodyData): string {.inline.} =
  $(
    multipart: body.multipart,
    formdata: body.formdata,
    formfiles: body.formfiles,
    data: body.data
  )

proc newBodyData(): BodyData =
  new result
  result.formdata = newFormTable[string, string]()
  result.formfiles = newFormTable[string, FileAttributes]()
  result.multipart = false
  result.data = ""


proc newAsyncHttpBodyParser*(): AsyncHttpBodyParser =

  ## Creates a new ``AsyncHttpBodyParser`` instance.
  
  new result
  result.initialized = false
  result.workingDir = getTempDir()
  result.onData = nil
  result.body = newBodyData()
