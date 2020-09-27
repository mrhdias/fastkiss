#
#
#                 FastKiss Utils
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

from strutils import fromHex

# https://github.com/nim-lang/Nim/edit/version-1-2/lib/pure/uri.nim
# https://www.freeformatter.com/url-parser-query-string-splitter.html
# http://127.0.0.1:8080/fcgi/testget?a=1&b=0&c=3&d&e&a=5&a=t%20e%20x%20t&e=http%3A%2F%2Fw3schools.com%2Fmy%20test.asp%3Fname%3Dst%C3%A5le%26car%3Dsaab

iterator decodeData*(data: string): tuple[key, value: TaintedString] =
  var
    name = ""
    buffer = ""
    encodedchar = ""

  proc getPair(name, buffer: string): array[2, string] =
    return if name.len == 0 and buffer.len > 0: [buffer, ""]
      elif name.len > 0: [name, buffer]
      else: ["", ""]

  for c in data:

    if c == '&':
      let pair = getPair(name, buffer)
      if pair[0].len > 0:
        yield (pair[0].TaintedString, pair[1].TaintedString)
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

  let pair = getPair(name, buffer)
  if pair[0].len > 0:
    yield (pair[0].TaintedString, pair[1].TaintedString)
