#
# https://en.wikipedia.org/wiki/MIME
#

import asyncdispatch
import asyncfile
from strutils import `%`, join, Digits, Letters
from os import `/`
from fastkiss/asyncfcgibodyparser import FileAttributes
from base64 import encodeMime
import fastkiss/thirdparty/quotedprintable
from random import randomize, rand

type
  AsyncMimeMpM* = ref object of RootObj
    boundary*: string
    workingDir: string

randomize()

func digitsAndLetters(): string =
  for c in Digits + Letters:
    result.add(c)

const chars = digitsAndLetters()

proc genBoundary(): string =
  for _ in .. 52:
    result.add(chars[rand(0 .. (chars.len - 1))])

proc stringifyHeaders(headers: varargs[tuple[name, value: string]]): string =
  for header in headers:
    result.add("$1: $2\c\L" % [header.name, header.value])


proc fileGetContents(filename: string): Future[string] {.async.} =
  try:
    let file = openAsync(filename, fmRead)
    let data = await file.readAll()
    file.close()
    return data
  except OSError as e:
    echo "$1: $2" % [e.msg, filename]


proc message*(
  self: AsyncMimeMpM,
  message: string,
  files: seq[FileAttributes]): Future[string] {.async.} =

  var parts: seq[string]
  parts.add("This is a message with multiple parts in MIME format.\c\L")

  let msgHeaders = stringifyHeaders(
    ("Content-Type", "text/plain; charset=\"UTF-8\""),
    ("Content-Transfer-Encoding", "quoted-printable")
  )
  parts.add("\c\L$1\c\L$2\c\L" % [msgHeaders, quotedPrintable(message, "utf-8")])

  for file in files:
    let data = await fileGetContents(self.workingDir / file.filename)
    let attchHeaders = stringifyHeaders(
      ("Content-Type", if file.content_type == "text/plain": "text/plain; charset=\"UTF-8\"" else: file.content_type),
      ("Content-Transfer-Encoding", if file.content_type == "text/plain": "quoted-printable" else: "base64")
    )
    parts.add("\c\L$1\c\L$2\c\L" % [
      attchHeaders, if file.content_type == "text/plain": quotedPrintable(data, "utf-8") else: encodeMime(data)
    ])

  result = parts.join("--$1" % self.boundary)
  result.add("--$1--" % self.boundary)


proc newAsyncMimeMpM*(workingDir: string): AsyncMimeMpM =

  new result
  result.boundary = "_$1_FASTKISS_" % genBoundary()
  result.workingDir = workingDir
