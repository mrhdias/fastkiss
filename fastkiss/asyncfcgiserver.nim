#
#         FastKiss Async FastCgi Server
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
from os import getFileSize, `/`, dirExists, fileExists,
  removeDir, getTempDir, getEnv
import asyncnet, asyncdispatch, asyncfile
import httpcore
import asyncfcgibodyparser
import tables
from sequtils import toSeq, map
from strformat import `&`
from strutils import rfind, `%`, parseInt, split, strip, toUpperAscii
import re
import oids
import mimetypes
import json

export asyncdispatch
export httpcore except parseHeader
export tables

const
  DEFAULT_PORT = 9000
  FCGI_WEB_SERVER_ADDRS = "FCGI_WEB_SERVER_ADDRS"

  httpMethods = {
    "GET": HttpGet,
    "POST": HttpPost,
    "HEAD": HttpHead,
    "PUT": HttpPut,
    "DELETE": HttpDelete,
    "PATCH": HttpPatch,
    "OPTIONS": HttpOptions,
    "CONNECT": HttpConnect,
    "TRACE": HttpTrace}.toTable


const
  FCGI_MAX_LENGTH* = 0xffff # 65535
  FCGI_VERSION_1* = 1
  FCGI_HEADER_LENGTH* = 8
  FGCI_KEEP_CONNECTION* = 1

type
  RouteAttributes = ref object
    pathPattern: string
    regexPattern: Regex
    callback: proc (request: Request): Future[void] {.closure, gcsafe.}

  Config* = object
    port*: int
    address*: string
    reuseAddr*: bool
    reusePort*: bool
    tmpUploadDir*: string ## Default temporary directory of the current user to save temporary files
    autoCleanTmpUploadDir*: bool ## The value true will cause the temporary files left after request processing to be removed.
    staticDir*: string ## To serve static files such as images, CSS files, and JavaScript files
    maxBody*: int ## The maximum content-length that will be read for the body

  AsyncFCGIServer* = ref object
    socket*: AsyncSocket
    allowedIps*: seq[string]
    routes: TableRef[
      HttpMethod,
      seq[RouteAttributes]
    ]
    config*: Config

  ReadParamState* = enum
    READ_NAME_LEN
    READ_VALUE_LEN
    READ_NAME_DATA
    READ_VALUE_DATA
    READ_FINISH

  Response* = ref object
    headers*: HttpHeaders
    statusCode*: HttpCode
    parted: bool

  Request* = object
    id*: uint16
    keepAlive*: uint8
    reqMethod*: HttpMethod
    reqUri*: string
    client*: AsyncSocket
    headers*: HttpHeaders
    regexCaptures*: array[20, string]
    body*: BodyData
    rawBody*: string
    response*: Response

type
  HeaderKind* = enum
    FCGI_BEGIN_REQUEST = 1
    FCGI_ABORT_REQUEST
    FCGI_END_REQUEST
    FCGI_PARAMS
    FCGI_STDIN
    FCGI_STDOUT
    FCGI_STDERR
    FCGI_DATA
    FCGI_GET_VALUES
    FCGI_GET_VALUES_RESULT
    FCGI_MAX

  Header* = object
    version*: uint8
    kind*: HeaderKind
    requestIdB1*: uint8
    requestIdB0*: uint8
    contentLengthB1*: uint8
    contentLengthB0*: uint8
    paddingLength*: uint8
    reserved*: uint8

  ProtocolStatus* = enum
    FCGI_REQUEST_COMPLETE
    FCGI_CANT_MPX_CONN
    FCGI_OVERLOADED
    FCGI_UNKNOWN_ROLE

  BeginRequestBody* = object
    roleB1*: uint8
    roleB0*: uint8
    flags*: uint8
    reserved*: array[5, uint8]

  EndRequestBody* = object
    appStatusB3*: uint8
    appStatusB2*: uint8
    appStatusB1*: uint8
    appStatusB0*: uint8
    protocolStatus*: uint8
    reserved*: array[3, char]

  EndRequestRecord* = object
    header*: Header
    body*: EndRequestBody

var mt {.threadvar.}: MimeDB
mt = newMimetypes()

const chunkSize = 8*1024

proc initHeader(kind: HeaderKind, reqId: uint16, contentLength, paddingLenth: int): Header =
  result.version = FCGI_VERSION_1
  result.kind = kind
  result.requestIdB1 = uint8((reqId shr 8) and 0xff)
  result.requestIdB0 = uint8(reqId and 0xff)
  result.contentLengthB1 = uint8((contentLength shr 8) and 0xff)
  result.contentLengthB0 = uint8(contentLength and 0xff)
  result.paddingLength = paddingLenth.uint8
  result.reserved = 0

proc initEndRequestBody*(appStatus: int32, status = FCGI_REQUEST_COMPLETE): EndRequestBody =
  result.appStatusB3 = uint8((appStatus shr 24) and 0xff)
  result.appStatusB2 = uint8((appStatus shr 16) and 0xff)
  result.appStatusB1 = uint8((appStatus shr 8) and 0xff)
  result.appStatusB0 = uint8((appStatus) and 0xff)
  result.protocolStatus = status.uint8


proc initRequest(): Request =
  result.keepAlive = 0
  result.headers = newHttpHeaders()
  result.response = new Response
  result.response.headers = newHttpHeaders()
  result.response.statusCode = Http200
  result.response.parted = false


proc sendEnd*(req: Request, appStatus: int32 = 0, status = FCGI_REQUEST_COMPLETE) {.async.} =
  var record: EndRequestRecord
  record.header = initHeader(FCGI_END_REQUEST, req.id, sizeof(EndRequestBody), 0)
  record.body = initEndRequestBody(appStatus, status)
  await req.client.send(addr record, sizeof(record))

#
# Utility functions
#

iterator getRange(size, dataLength: int): HSlice[int, int] =
  if size > 0 and dataLength > 0:
    var n = 0
    while (n + size) < dataLength:
      yield n .. (n + size - 1)
      n += size

    if n < dataLength:
      yield n .. (dataLength - 1)

proc stringifyHeaders(resp: Response, contentLength = -1): string =

  if not resp.headers.hasKey("status"):
    resp.headers.add("status", $resp.statusCode)

  if not resp.headers.hasKey("content-type"):
    resp.headers.add("content-type", "text/html; charset=utf-8")

  if resp.headers.hasKey("content-length") and (contentLength == -1):
    resp.headers.del("content-length")
  elif not resp.headers.hasKey("content-length") and (contentLength > -1):
    resp.headers.add("content-length", $contentLength)

  var payload = ""
  for name, value in resp.headers.pairs:
    payload.add(&"{name}: {value}\c\L")

  # echo payload
  return payload

#
# Begin One-shot Response
#

proc respond*(req: Request, content = "") {.async.} =
  if req.response.parted:
    raise newException(IOError, "500 Internal Server Error")

  let payload = "$1\c\L" % req.response.stringifyHeaders(content.len)

  var header = initHeader(FCGI_STDOUT, req.id, payload.len, 0)
  await req.client.send(addr header, FCGI_HEADER_LENGTH)

  await req.client.send(payload.cstring, payload.len)

  if content.len > 0:
    # The content is send in chunks to avoid the error:
    # net::ERR_CONTENT_LENGTH_MISMATCH 200 (OK) if big payloads

    for strRange in getRange(chunkSize, content.len):
      let dataLen = (strRange.b - strRange.a) + 1
      header.contentLengthB1 = uint8((dataLen shr 8) and 0xff)
      header.contentLengthB0 = uint8(dataLen and 0xff)
      await req.client.send(addr header, FCGI_HEADER_LENGTH)
      await req.client.send(content[strRange].cstring, dataLen)

  header.contentLengthB1 = 0
  header.contentLengthB0 = 0
  await req.client.send(addr header, FCGI_HEADER_LENGTH)

  await req.sendEnd()

  if req.keepAlive == 0:
    req.client.close()


proc respond*(req: Request, json: JsonNode) {.async.} =
  let content = $json
  req.response.headers["content-type"] = "application/json"
  req.response.headers["content-length"] = $(content.len())

  await req.respond(content)

#
# Begin Response Parted
#

proc respBegin(req: Request, content = "") {.async.} =

  if req.response.parted:
    raise newException(IOError, "500 Internal Server Error")

  # set -1 to remove the content-length header if exists
  let payload = "$1\c\L" % req.response.stringifyHeaders(-1)

  var header = initHeader(FCGI_STDOUT, req.id, payload.len, 0)
  await req.client.send(addr header, FCGI_HEADER_LENGTH)

  await req.client.send(payload.cstring, payload.len)

  req.response.parted = true


proc resp*(req: Request, payload: string) {.async.} =
  # https://trac.nginx.org/nginx/ticket/1292
  if not req.response.parted:
    if not req.response.headers.hasKey("content-type"):
      req.response.headers["content-type"] = "text/html; charset=utf-8"
    req.response.statusCode = Http200
    await req.respBegin("")

  if payload.len == 0:
    return

  # The content is send in chunks to avoid the error:
  # net::ERR_CONTENT_LENGTH_MISMATCH 200 (OK) if big payloads

  var header = initHeader(FCGI_STDOUT, req.id, payload.len, 0)
  for strRange in getRange(chunkSize, payload.len):
    let dataLen = (strRange.b - strRange.a) + 1
    header.contentLengthB1 = uint8((dataLen shr 8) and 0xff)
    header.contentLengthB0 = uint8(dataLen and 0xff)
    await req.client.send(addr header, FCGI_HEADER_LENGTH)
    await req.client.send(payload[strRange].cstring, dataLen)


proc respEnd(req: Request) {.async.} =
  if not req.response.parted:
    raise newException(IOError, "500 Internal Server Error")

  var header = initHeader(FCGI_STDOUT, req.id, 0, 0)
  header.contentLengthB1 = 0
  header.contentLengthB0 = 0
  await req.client.send(addr header, FCGI_HEADER_LENGTH)

  await req.sendEnd()
  req.response.parted = false

  if req.keepAlive == 0:
    req.client.close()


#
# Begin File Server
#

proc sendFile*(req: Request, filepath: string): Future[void] {.async.} =

  if not fileExists(filepath):
    req.response.headers["content-type"] = "text/plain; charset=utf-8"
    req.response.statusCode = Http404
    await req.respond($req.response.statusCode)
    return

  let filesize = cast[int](getFileSize(filepath))

  # if filesize > high(int):
  #   return "The file size exceeds the integer maximum."

  var extension = "unknown"
  if ((let p = filepath.rfind('.')); p > -1):
    extension = filepath[p+1 .. ^1]

  let payload = "status: 200 OK\c\Lcontent-type: $1\c\Lcontent-length: $2\c\L\c\L" % [mt.getMimetype(extension), $filesize]

  var header = initHeader(FCGI_STDOUT, req.id, payload.len, 0)
  await req.client.send(addr header, FCGI_HEADER_LENGTH)

  await req.client.send(payload.cstring, payload.len)

  var remainder = filesize
  let file = openAsync(filepath, fmRead)

  while remainder > 0:
    let data = await file.read(min(remainder, chunkSize))
    remainder -= data.len
    header.contentLengthB1 = uint8((data.len shr 8) and 0xff)
    header.contentLengthB0 = uint8(data.len and 0xff)
    await req.client.send(addr header, FCGI_HEADER_LENGTH)
    await req.client.send(data.cstring, data.len)

  file.close()

  header.contentLengthB1 = 0
  header.contentLengthB0 = 0
  await req.client.send(addr header, FCGI_HEADER_LENGTH)

  await req.sendEnd()

  if req.keepAlive == 0:
    req.client.close()


proc fileserver*(req: Request, staticDir=""): Future[void] {.async.} =
  var url_path = $req.headers["document_uri"]

  url_path = if url_path.len > 1 and url_path[0] == '/': url_path[1 .. ^1] else: "index.html"
  var path = static_dir / url_path

  if dirExists(path):
    path = path / "index.html"

  await req.sendFile(path)

#
# End File Server
#

#
# proc cookies*(req: Request): Table[string, string] =
#  ## Cookies from the browser.
#  if (let cookie = req.headers.getOrDefault("Cookie"); cookie != ""):
#    result = parseCookies(cookie)
#   else:
#     result = initTable[string, string]()


proc getParams(req: var Request, buffer: ptr array[FCGI_MAX_LENGTH + 8, char], length: int) =
  var
    pos = 0
    nameLen: uint32
    valueLen: uint32
    state: ReadParamState
    name: string
    value: string

  while pos < length:
    case state
    of READ_NAME_LEN:
      nameLen = buffer[pos].uint32
      if nameLen == 0x80:
        nameLen = (nameLen and 0x7f) shl 24 + buffer[pos + 1].uint8
        nameLen = nameLen shl 16 + buffer[pos + 2].uint8
        nameLen = nameLen shl 8 + buffer[pos + 3].uint8
        inc(pos, 4)
      else:
        inc(pos, 1)
      state = READ_VALUE_LEN
    of READ_VALUE_LEN:
      valueLen = buffer[pos].uint32
      if valueLen == 0x80:
        valueLen = (valueLen and 0x7f) shl 24 + buffer[pos + 1].uint8
        valueLen = valueLen shl 16 + buffer[pos + 2].uint8
        valueLen = valueLen shl 8 + buffer[pos + 3].uint8
        inc(pos, 4)
      else:
        inc(pos, 1)
      state = READ_NAME_DATA
    of READ_NAME_DATA:
      name = newString(nameLen)
      copyMem(name.cstring, addr buffer[pos], nameLen)
      inc(pos, nameLen.int)
      state = READ_VALUE_DATA
    of READ_VALUE_DATA:
      value = newString(valueLen)
      copyMem(value.cstring, addr buffer[pos], valueLen)
      inc(pos, valueLen.int)
      state = READ_FINISH
    of READ_FINISH:
      # echo name, " = ", value
      state = READ_NAME_LEN
      if name == "REQUEST_METHOD":
        if httpMethods.hasKey(value):
          req.reqMethod = httpMethods[value]
        else:
          raise newException(IOError, "400 bad request")
      elif name == "REQUEST_URI":
        req.reqUri = value

      req.headers.add(name, value)

proc processClient(
  server: AsyncFCGIServer,
  client: AsyncSocket,
  address: string) {.async.} =

  var
    req = initRequest()
    readLen = 0
    header: Header
    buffer: array[FCGI_MAX_LENGTH + 8, char]
    length: int
    payloadLen: int

  let bodyParser = newAsyncHttpBodyParser()

  while not client.isClosed:
    readLen = await client.recvInto(addr header, sizeof(Header))
    if readLen != sizeof(Header) or header.version.ord < FCGI_VERSION_1:
      return

    length = (header.contentLengthB1.int shl 8) or header.contentLengthB0.int
    payloadLen = length + header.paddingLength.int

    if payloadLen > FCGI_MAX_LENGTH:
      return

    req.client = client
    req.id = (header.requestIdB1.uint16 shl 8) + header.requestIdB0

    case header.kind
    of FCGI_GET_VALUES:
      echo "get value"

    of FCGI_BEGIN_REQUEST:
      readLen = await client.recvInto(addr buffer, payloadLen)
      let begin = cast[ptr BeginRequestBody](addr buffer)
      req.keepAlive = begin.flags and FGCI_KEEP_CONNECTION

    of FCGI_PARAMS:
      readLen = await client.recvInto(addr buffer, payloadLen)
      if readLen != payloadLen: return
      if length != 0:
        req.getParams(addr buffer, length)

    of FCGI_STDIN:
      if (req.reqMethod == HttpPost) and (not bodyParser.initialized):
        if req.headers.hasKey("content_length") and parseInt(req.headers["content_length"]) > server.config.maxBody:

          req.response.headers["content-type"] = "text/plain; charset=utf-8"
          req.response.statusCode = Http413
          await req.respond($req.response.statusCode)
          return

        bodyParser.initialized = true
        bodyParser.workingDir = server.config.tmpUploadDir / $genOid()
        req.headers.add("Working-Directory", bodyParser.workingDir)
        bodyParser.parse(req.headers)

      readLen = await client.recvInto(addr buffer, payloadLen)
      if readLen != payloadLen: return
      if length != 0:
        var chunk = newString(length)
        copyMem(chunk.cstring, addr buffer, length)
        if bodyParser.initialized:
          await bodyParser.onData(chunk)
        else:
          req.rawBody.add(chunk)
      else:

        ### begin find routes ###

        proc routeCallback(
          routes: seq[RouteAttributes],
          documentUri: string): proc (request: Request): Future[void] {.closure, gcsafe.} =

          let pattern = if (documentUri.len > 1 and documentUri[^1] == '/'): documentUri[0 ..< ^1] else: documentUri

          for route in routes:
            if route.regexPattern != nil:
              if pattern =~ route.regexPattern:
                req.regexCaptures = matches
                return route.callback
            elif route.pathPattern != "":
              if route.pathPattern == pattern:
                return route.callback

          return nil

        # for compatibility between apache and nginx servers.
        if not req.headers.hasKey("document_uri") and req.headers.hasKey("request_uri"):
          req.headers["document_uri"] = req.headers["request_uri"].split("?", 1)[0]

        if server.routes.hasKey(req.reqMethod) and req.headers.hasKey("document_uri") and
          (let callback = routeCallback(server.routes[req.reqMethod], req.headers["document_uri"]); callback) != nil:
          req.body = bodyParser.body
          await callback(req)
          # if the response is parted
          if req.response.parted:
            await req.respEnd()

          # Clear the temporary directory here if auto clean
          if server.config.autoCleanTmpUploadDir and
              dirExists(bodyParser.workingDir) and
              bodyParser.workingDir != server.config.tmpUploadDir:

            removeDir(bodyParser.workingDir)

          return

        ### end find routes ###

        # begin serve static files
        if (req.reqMethod == HttpGet) and
          (server.config.staticDir != "") and
            dirExists(server.config.staticDir):
          # echo "serve static file"
          await req.fileserver(server.config.staticDir)
          return
        # end serve static files

        req.response.headers["content-type"] = "text/plain; charset=utf-8"
        req.response.statusCode = Http404
        await req.respond($req.response.statusCode)
    else:
      return
  # else:
  #   await req.respond("Not Implemented")


proc checkRemoteAddrs(server: AsyncFCGIServer, client: AsyncSocket): bool =
  if server.allowedIps.len > 0:
    let (remote, _) = client.getPeerAddr()
    return remote in server.allowedIps
  return true



#
# Begin Handle Methods
#

proc initRouteAttributes(
  pattern: string,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}): RouteAttributes = RouteAttributes(
  pathPattern: pattern,
  regexPattern: nil,
  callback: callback
)

proc initRouteAttributes(
  pattern: Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}): RouteAttributes = RouteAttributes(
  pathPattern: "",
  regexPattern: pattern,
  callback: callback
)

proc addRoute(
  server: AsyncFCGIServer,
  methods: openArray[string],
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}) =

  for `method` in methods:
    if not httpMethods.hasKey(`method`):
      echo "Error: HTTP method \"$1\" not exists! skiped..." % `method`
      continue

    if not server.routes.hasKey(httpMethods[`method`]):
      server.routes[httpMethods[`method`]] = newSeq[RouteAttributes]()

    server.routes[httpMethods[`method`]].add(initRouteAttributes(pattern, callback))

proc get*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["GET"], pattern, callback)

proc post*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["POST"], pattern, callback)

proc put*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["PUT"], pattern, callback)

proc head*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["HEAD"], pattern, callback)

proc patch*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["PATCH"], pattern, callback)

proc delete*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["DELETE"], pattern, callback)

proc options*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["OPTIONS"], pattern, callback)

proc connect*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["CONNECT"], pattern, callback)

proc trace*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["TRACE"], pattern, callback)

proc any*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(toSeq(httpMethods.keys), pattern, callback)

proc match*(
  server: AsyncFCGIServer,
  methods: openArray[string],
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(methods.map(toUpperAscii), pattern, callback)

#
# End handle Methods
#

proc listen(server: AsyncFCGIServer) =
  ## Listen to the given port and address.

  server.socket = newAsyncSocket()
  if server.config.reuseAddr:
    server.socket.setSockOpt(OptReuseAddr, true)

  if server.config.reusePort:
    server.socket.setSockOpt(OptReusePort, true)

  server.socket.bindAddr(Port(server.config.port), server.config.address)
  server.socket.listen()

proc serve*(server: AsyncFCGIServer) {.async.} =

  ## Starts the process of listening for incoming TCP connections
  server.listen()

  while true:
    var (address, client) = await server.socket.acceptAddr()

    if server.checkRemoteAddrs(client):
      asyncCheck server.processClient(client, address)
    else:
      client.close()


proc close*(server: AsyncFCGIServer) =
  ## Terminates the async http server instance.
  server.socket.close()


proc run*(server: AsyncFCGIServer) =
  echo "The FastKiss is kissing at fcgi://$1:$2" % [
    if server.config.address == "": "0.0.0.0" else: server.config.address,
    $(server.config.port)
  ]
  asyncCheck server.serve()
  runForever()


proc newAsyncFCGIServer*(): AsyncFCGIServer =
  ## Creates a new ``AsyncFCGIServer`` instance.
  new result
  result.config.reuseAddr = true
  result.config.reusePort = false
  result.routes = newTable[
    HttpMethod,
    seq[RouteAttributes]
  ]()

  result.config.port = DEFAULT_PORT
  result.config.address = ""
  result.config.tmpUploadDir = getTempDir()
  result.config.autoCleanTmpUploadDir = true
  result.config.staticDir = ""
  result.config.maxBody = 8388608 # 8MB = 8388608 Bytes

  let fwsa = getEnv(FCGI_WEB_SERVER_ADDRS, "")
  if fwsa.len > 0:
    for add in fwsa.split(','):
      result.allowedIps.add(add.strip())
