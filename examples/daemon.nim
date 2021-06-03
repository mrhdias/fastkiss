#
# nano -w nginx/conf/nginx.conf
# worker_processes  4
#
# nimble install https://github.com/mrhdias/fastkiss
# nim c -r daemon.nim
# http://example:8080/
#[
Runs on my Laptop Intel Core i3-8130U @ 2.20GHz, 8 GB memory

$ nim c -d:danger --gc:orc daemon.nim 
$ wrk --latency -d 30 -t 4 -c 100 http://example:8080/
Running 30s test @ http://example:8080/
  4 threads and 100 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     7.85ms    5.17ms  34.66ms   66.38%
    Req/Sec     3.33k   225.11     4.30k    73.75%
  Latency Distribution
     50%    7.24ms
     75%   10.98ms
     90%   14.99ms
     99%   22.32ms
  398161 requests in 30.04s, 66.07MB read
Requests/sec:  13252.49
Transfer/sec:      2.20MB
]#

import fastkiss
import posix
import cpuinfo

var pid: Pid

proc launchApp() =

  let app = newApp()
  app.config.port = 9000 # optional if default port
  app.config.reusePort = true

  app.get("/", proc (req: Request) {.async.} =
    await req.respond("Hello World!")
  )

  app.run()

proc processes(forks = 0) =

  var children: seq[Pid]

  for _ in 0 .. forks - 1:
    let pid = fork()
    if pid < 0:
      # error forking a child
      quit(QuitFailure)

    elif pid > 0:
      # In parent process
      children.add(pid)

    else:
      # In child process
      launchApp()
      quit(QuitSuccess)

  for child in children:
    var status: cint
    discard waitpid(child, status, 0)


proc daemonize() =

  let pidFile = "test.pid"
  var standIn, standOut, standErr: File

  pid = fork()

  if pid < 0:
    # error forking a child
    quit(QuitFailure)

  elif pid > 0:
    # In parent process

    if len(pidFile) > 0:
      echo "To stop the server: kill ", $pid
      echo "or kill $(cat test.pid)"
      writeFile(pidFile, $pid)

    quit(QuitSuccess)

  # In child process

  onSignal(SIGKILL, SIGINT, SIGTERM):
    echo "Exiting: ", sig
    discard kill(pid, SIGTERM)
    quit(QuitSuccess)

  # decouple from parent environment
  if chdir("/") < 0:
    quit(QuitFailure)

  discard umask(0) # don't inherit file creation perms from parent

  if setsid() < 0: # make it session leader
    quit(QuitFailure)

  signal(SIGCHLD, SIG_IGN)

  if not standIn.open("/dev/null", fmRead):
    quit(QuitFailure)
  if not standOut.open("/dev/null", fmAppend):
    quit(QuitFailure)
  if not standErr.open("/dev/null", fmAppend):
    quit(QuitFailure)

  if dup2(getFileHandle(standIn), getFileHandle(stdin)) < 0:
    quit(QuitFailure)
  if dup2(getFileHandle(standOut), getFileHandle(stdout)) < 0:
    quit(QuitFailure)
  if dup2(getFileHandle(standErr), getFileHandle(stderr)) < 0:
    quit(QuitFailure)

  # fork n x cpu processes
  var processors = countProcessors()
  echo processors
  if processors == 0:
    processors = 2
  processes(processors)


proc main() =
  daemonize()

main()
