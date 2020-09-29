# FastKiss - Nim's FastCGI Web Framework
⚠️ WARNING: This library is still in heavy development. ⚠️
```nim
import fastkiss/asyncfcgiserver

proc main() =
  let app = newAsyncFCGIServer()
  app.config.port = 9000
  
  app.get("/test", proc (req: Request) {.async.} =
    await req.response("Hello World!")
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

### Available Router Methods
Routes that respond to any HTTP verb
```nim
get[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)

post[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)

put[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)

patch[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)

delete[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)

options[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)
```

Route that responds to multiple HTTP verbs
```nim
match[T: string|Regex](
  server: AsyncFCGIServer,
  methods: openArray[string],
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)
```

Route that responds to all HTTP verbs
```nim
any[T: string|Regex](
  server: AsyncFCGIServer,
  pattern: T,
  callback: proc (request: Request): Future[void] {.closure, gcsafe.}
)
```
