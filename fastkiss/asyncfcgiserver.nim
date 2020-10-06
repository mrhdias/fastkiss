#
#         FastKiss Async FastCgi Server
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
from os import getFileSize, `/`, existsDir, existsFile,
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
  FCGI_MAX_LENGTH* = 0xffff
  FCGI_VERSION_1* = 1

  FGCI_KEEP_CONNECTION* = 1

  FCGI_HEADER_LENGTH* = 8

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


let mt = newMimetypes()

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



proc sendEnd*(req: Request, appStatus: int32 = 0, status = FCGI_REQUEST_COMPLETE) {.async.} =
  var record: EndRequestRecord
  record.header = initHeader(FCGI_END_REQUEST, req.id, sizeof(EndRequestBody), 0)
  record.body = initEndRequestBody(appStatus, status)
  await req.client.send(addr record, sizeof(record))



proc response*(
  req: Request,
  content = "",
  headers: HttpHeaders,
  appStatus: int32 = 0) {.async.} =

  var payload = ""

  if not headers.hasKey("status"):
    headers.add("status", $HttpCode(appStatus))

  if not headers.hasKey("content-length"):
    headers.add("content-length", $(content.len))

  if not headers.hasKey("content-type"):
    headers.add("content-type", "text/plain;charset=utf-8")

  for name, value in headers.pairs:
    payload.add(&"{name}: {value}\c\L")

  # echo payload

  if content.len > 0:
    payload.add(&"\c\L{content}")

  var header = initHeader(FCGI_STDOUT, req.id, payload.len, 0)
  await req.client.send(addr header, FCGI_HEADER_LENGTH)

  # echo "Payload: ", payload
  if payload.len > 0:
    await req.client.send(payload.cstring, payload.len)
    header.contentLengthB1 = 0
    header.contentLengthB0 = 0
    await req.client.send(addr header, FCGI_HEADER_LENGTH)

  await req.sendEnd()

  if req.keepAlive == 0:
    req.client.close()


proc response*(req: Request, json: JsonNode) {.async.} =
  let content = $json
  let headers = newHttpHeaders([
    ("status", "200 OK"),
    ("content-length", $(content.len())),
    ("content-type", "application/json")
  ])
  await req.response(content, headers, appStatus=200)


proc response*(req: Request, html: string) {.async.} =
  let headers = newHttpHeaders([
    ("status", "200 OK"),
    ("content-length", $(html.len())),
    ("content-type", "text/html;charset=utf-8")
  ])
  await req.response(html, headers, appStatus=200)


### Begin File Server ###

proc sendFile(req: Request, filepath: string): Future[void] {.async.} =
  let filesize = cast[int](getFileSize(filepath))

  # if filesize > high(int):
  #   return "The file size exceeds the integer maximum."

  var extension = "unknown"
  if ((let p = filepath.rfind('.')); p > -1):
    extension = filepath[p+1 .. ^1]

  let payload = "status: 200 OK\c\Lcontent-type: $1\c\L\c\L" % mt.getMimetype(extension)

  var header = initHeader(FCGI_STDOUT, req.id, payload.len, 0)
  await req.client.send(addr header, FCGI_HEADER_LENGTH)

  if payload.len > 0:
    await req.client.send(payload.cstring, payload.len)

    const chunkSize = 8*1024
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

  if existsDir(path):
    path = path / "index.html"

  if existsFile(path):
    await req.sendFile(path)
    return

  let headers = newHttpHeaders([
    ("status", "404 not found"),
    ("content-type", "text/plain")
  ])
  await req.response("404 Not Found", headers, appStatus=404)

### End File Server ###

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
      state = READ_NAME_LEN
      case name
      of "REQUEST_METHOD":
        case value
        of "GET": req.reqMethod = HttpGet
        of "POST": req.reqMethod = HttpPost
        of "HEAD": req.reqMethod = HttpHead
        of "PUT": req.reqMethod = HttpPut
        of "DELETE": req.reqMethod = HttpDelete
        of "PATCH": req.reqMethod = HttpPatch
        of "OPTIONS": req.reqMethod = HttpOptions
        of "CONNECT": req.reqMethod = HttpConnect
        of "TRACE": req.reqMethod = HttpTrace
        else:
          raise newException(IOError, "400 bad request")
      of "REQUEST_URI":
        req.reqUri = value
      else:
        discard
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
          let headers = newHttpHeaders([
            ("status", "413 Payload Too Large"),
            ("content-type", "text/plain;charset=utf-8")
          ])
          await req.response("413 Payload Too Large", headers, appStatus=413)
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
        # req.body.add(chunk)
        await bodyParser.onData(chunk)
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

        if server.routes.hasKey(req.reqMethod) and req.headers.hasKey("document_uri") and
          (let callback = routeCallback(server.routes[req.reqMethod], req.headers["document_uri"]); callback) != nil:
          req.body = bodyParser.body
          await callback(req)

          # Clear the temporary directory here if auto clean
          if server.config.autoCleanTmpUploadDir and
              existsDir(bodyParser.workingDir) and
              bodyParser.workingDir != server.config.tmpUploadDir:

            removeDir(bodyParser.workingDir)

          return

        ### end find routes ###

        # begin serve static files
        if (req.reqMethod == HttpGet) and
          (server.config.staticDir != "") and
            existsDir(server.config.staticDir):
          echo "serve static file"
          await req.fileserver(server.config.staticDir)
          return
        # end serve static files

        let headers = newHttpHeaders([
          ("status", "404 not found"),
          ("content-type", "text/plain")
        ])
        await req.response("404 Not Found", headers, appStatus=404)
    else:
      return
  #else:
  #  await server.response(client, "\c\LNot Implemented")


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

proc addRoute[T: string|Regex](
  server: AsyncFCGIServer,
  methods: openArray[string],
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}) =

  for `method` in methods:
    if not httpMethods.hasKey(`method`):
      echo "Error: HTTP method \"$1\" not exists! skiped..." % `method`
      continue

    if not server.routes.hasKey(httpMethods[`method`]):
      server.routes.add(httpMethods[`method`], newSeq[RouteAttributes]())

    server.routes[httpMethods[`method`]].add(initRouteAttributes(pattern, callback))

proc get*[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["GET"], pattern, callback)

proc post*[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["POST"], pattern, callback)

proc put*[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["PUT"], pattern, callback)

proc patch*[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["PATCH"], pattern, callback)

proc delete*[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["DELETE"], pattern, callback)

proc options*[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(@["OPTIONS"], pattern, callback)

proc any*[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(toSeq(httpMethods.keys), pattern, callback)

proc match*[T: string|Regex](
  server: AsyncFCGIServer,
  methods: openArray[string],
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
) = server.addRoute(methods.map(toUpperAscii), pattern, callback)

#
# End handle Methods
#



proc serve*(server: AsyncFCGIServer) {.async.} =

  ## Starts the process of listening for incoming TCP connections
  server.socket = newAsyncSocket()
  if server.config.reuseAddr:
    server.socket.setSockOpt(OptReuseAddr, true)
  if server.config.reusePort:
    server.socket.setSockOpt(OptReusePort, true)
  server.socket.bindAddr(Port(server.config.port), server.config.address)
  server.socket.listen()

  while true:
    var (address, client) = await server.socket.acceptAddr()

    if server.checkRemoteAddrs(client):
      asyncCheck processClient(server, client, address)
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
