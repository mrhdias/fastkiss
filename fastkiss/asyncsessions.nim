#
#            FastKiss Async Sessions
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import asyncdispatch
import strtabs
import tables
from times import DateTime, now, `-`, inSeconds
from oids import genOid, `$`
from md5 import toMD5, `$`

export strtabs

type
  Session* = ref object
    id*: string
    map*: StringTableRef
    requestTime: DateTime
    callback*: proc (id: string): Future[void]

type
  AsyncSessions* = ref object of RootObj
    pool*: TableRef[string, Session]
    sessionTimeout: int # seconds
    sleepTime: int # milliseconds
    maxSessions*: int
    circularQueue: seq[string]

type
  AsyncSessionsError* = object of CatchableError

proc isDead(requestTime: DateTime, sessionTimeout: int): bool =
  if (now() - requestTime).inSeconds > sessionTimeout: true else: false


proc sessionsManager(self: AsyncSessions): Future[void] {.async.} =
  while true:
    await sleepAsync(self.sleepTime)

    if self.circularQueue.len == 0:
      continue

    # echo "Number of active sessions on the queue: ", self.circularQueue.len
    # echo "Number of active sessions on the pool: ", self.pool.len

    let key = self.circularQueue[0]
    self.circularQueue.delete(0)

    if key notin self.pool:
      continue

    if isDead(self.pool[key].requestTime, self.sessionTimeout):
      # echo "session id timeout: ", key
      if self.pool[key].callback != nil:
        await self.pool[key].callback(key)
      self.pool.del(key)
    else:
      self.circularQueue.add(key)


proc setSession*(self: AsyncSessions): Session =
  ## Create a new Session.
  ##
  if self.pool.len == self.maxSessions:
    raise newException(AsyncSessionsError, "Maximum number of sessions exceeded!")

  let sessionId = $toMD5($genOid())

  self.pool[sessionId] = Session(
    id: sessionId,
    map: newStringTable(),
    requestTime: now(),
    callback: nil
  )
  self.circularQueue.add(sessionId)

  return self.pool[sessionId]


proc getSession*(self: AsyncSessions, id: string): Session =
  ## Get Session Id if exists.
  ##
  if id in self.pool:
    self.pool[id].requestTime = now()
    return self.pool[id]

  return Session()


proc delSession*(self: AsyncSessions, id: string) =
  ## Delete Session Id if exists.
  ##
  if self.pool.hasKey(id):
    self.pool.del(id)


proc cleanAll*(self: AsyncSessions) =
  ## Clean all sessions
  ##
  self.pool.clear()
  self.circularQueue = @[]


proc newAsyncSessions*(
  sleepTime = 5000,
  sessionTimeout = 3600,
  maxSessions: int = 100): AsyncSessions =

  ## Creates a new ``AsyncSessions`` instance.
  # result is the same of self in python
  new result
  result.sleepTime = sleepTime
  result.sessionTimeout = sessionTimeout
  result.maxSessions = maxSessions
  result.pool = newTable[string, Session]()
  result.circularQueue = @[]

  asyncCheck result.sessionsManager()

when not defined(testing) and isMainModule:

  let sessions = newAsyncSessions(
    sleepTime = 1000, # milliseconds
    sessionTimeout = 30, # seconds
    maxSessions = 1
  )

  proc timeoutSession(id: string) {.async.} =
    echo "expired session: ", id

  let session = sessions.setSession()
  echo "session id: ", session.id
  session.map["username"] = "Kiss"
  session.callback = timeoutSession

  let sessionStored = sessions.getSession(session.id)
  echo "username: ", sessionStored.map["username"]

  echo "Wait the session expire..."

  runForever()
