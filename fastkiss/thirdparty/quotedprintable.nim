#
# https://en.wikipedia.org/wiki/Quoted-printable
#

#import strutils, base64, encodings

from strutils import IdentChars, toHex
from encodings import convert

const safeChars = IdentChars + {
  ' ', '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/',
  ':', ';', '<', '>', '?', '@', '[', '\\', ']', '^', '_', '`', '{', '|', '}', '~'
}

proc quotedPrintable*(str, destEncoding: string, srcEncoding = "utf-8", lineLen = 76, newLine = "\r\n"): string =
  var count = 0
  for c in convert(str, destEncoding, srcEncoding):
    if count == lineLen - (1 + newLine.len): # lineLen - 1('=') - 2("\r\n")
      result.add('=')
      result.add(newLine)
      count = 0

    if c.char in safeChars:
      result.add(c)
      count += 1
    else:
      result.add('=')
      result.add(c.ord().toHex(2)) # 3(=XX) X = hex
      count += 3
