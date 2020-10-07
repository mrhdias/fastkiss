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
import times
import oids
import strutils

export strtabs

type
  Session = ref object
    id*: string
    map*: StringTableRef
    requestTime: DateTime
    callback*: proc (id: string): Future[void]

type
  AsyncSessions* = ref object of RootObj
    pool*: TableRef[string, Session]
    sessionTimeout: int
    sleepTime: int
    maxSessions*: int

proc sessionsManager(self: AsyncSessions): Future[void] {.async.} =
  while true:
    await sleepAsync(self.sleepTime)

    if self.pool == nil:
      continue

    # echo "Number of active sessions: ", self.pool.len
    # echo "check for sessions timeout..."
    var to_del = newSeq[string]()
    for key, value in self.pool:
      if (now() - self.pool[key].requestTime).inSeconds > self.sessionTimeout:
        # echo "session id timeout:", key
        to_del.add(key)

    for key in to_del:
      if self.pool[key].callback != nil:
        await self.pool[key].callback(key)
      # echo "the session will be deleted:", key
      self.pool.del(key)


proc setSession*(self: AsyncSessions): Session =
  let sessionId = genOid()

  return (self.pool[$sessionId] = Session(
    id: $sessionId,
    map: newStringTable(),
    request_time: now(),
    callback: nil
  ); self.pool[$sessionId])


proc getSession*(self: AsyncSessions, id: string): Session =
  if not self.pool.hasKey(id): return nil
  self.pool[id].request_time = now()
  return self.pool[id]


proc delSession*(self: AsyncSessions, id: string) =
  ## Delete Session Id if exists.
  ##
  if self.pool.hasKey(id):
    self.pool.del(id)


proc newAsyncSessions*(
  sleepTime = 5000,
  sessionTimeout = 3600,
  maxSessions: int = 100): AsyncSessions =

  ## Creates a new ``AsyncSessions`` instance.
  # result is the same of self in python
  new result
  result.sleepTime = sleepTime
  result.sessionTimeout = sessionTimeout
  result.pool = newTable[string, Session]()

  asyncCheck result.sessionsManager()
