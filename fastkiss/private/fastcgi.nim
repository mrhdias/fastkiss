#
# https://fast-cgi.github.io/spec
#

const
  FCGI_MAX_LENGTH* = 0xffff # 65535
  FCGI_VERSION_1* = 1
  FCGI_HEADER_LENGTH* = 8
  FGCI_KEEP_CONNECTION* = 1

type

  ReadParamState* = enum
    READ_NAME_LEN
    READ_VALUE_LEN
    READ_NAME_DATA
    READ_VALUE_DATA
    READ_FINISH

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


proc initHeader*(kind: HeaderKind, reqId: uint16, contentLength, paddingLenth: int): Header =
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
