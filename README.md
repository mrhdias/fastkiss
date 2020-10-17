# FastKiss - [Nim](https://www.nim-lang.org)'s FastCGI Web Framework
⚠️ WARNING: This library is still in heavy development. ⚠️
```nim
import fastkiss
import re
from strutils import `%`

proc main() =
  let app = newAsyncFCGIServer()
  app.config.port = 9000 # optional if default port

  app.get("/test", proc (req: Request) {.async.} =
    await req.response("Hello World!")
  )

  app.get(r"/test/(\w+)".re, proc (req: Request) {.async.} =
    await req.response("Hello $1!" % req.regexCaptures[0])
  )

  app.match(["GET", "POST"], "/which", proc (req: Request) {.async.} =
    await req.response("Hello $1!" % $req.reqMethod)
  )

  app.run()

main()
```

NGINX FastCGI Configuration File Example
```
server {
  listen  8080;
  server_name example;
  # add example to hosts file
  # nano -w /etc/hosts
  #
  # 127.0.0.1   example
  #

  location / {
    fastcgi_param COOKIE $http_cookie;
    fastcgi_param Authorization $http_authorization;

    client_max_body_size 1000M;
    include fastcgi_params;
    fastcgi_pass 127.0.0.1:9000;
  }
}
```

Test
```
$ nimble install https://github.com/mrhdias/fastkiss
$ nano -w example.nim
$ nim c -r example.nim
$ sudo systemctl start nginx
$ wget -qO- http://example:8080/test
Hello World!!⏎
```

### Configuration Options
```nim
config.port = 9000 # Default Port
config.address = ""
config.reuseAddr = true # Default value
config.reusePort = false # Default value

# Default temporary directory of the current user to save temporary files
config.tmpUploadDir = getTempDir()
# The value true will cause the temporary files left after request processing to be removed.
config.autoCleanTmpUploadDir = true
# To serve static files such as images, CSS files, and JavaScript files
config.staticDir = ""
# Sets the maximum allowed size of the client request body
config.maxBody = 8388608 # Default 8MB = 8388608 Bytes
```

### Available Router Methods
Routes that respond to any HTTP verb
```nim
get*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)

post*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)

put*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)

patch*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)

delete*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)

options*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)
```

Route that responds to multiple HTTP verbs
```nim
match*(
  server: AsyncFCGIServer,
  methods: openArray[string],
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)
```

Route that responds to all HTTP verbs
```nim
any*(
  server: AsyncFCGIServer,
  pattern: string | Regex,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)
```
