# FastKiss - A FastCGI Web Framework for Nim
⚠️ WARNING: This library is still in heavy development. ⚠️

FastKiss is an FastCGI Host/Server Framework for [Nim](https://www.nim-lang.org) Web Applications. It was developed against Nginx, but should work with any web server that implements the FCGI spec.

The FastCGI server allows you to easily integrate your FastKiss web application into a standard web server environment, taking advantage of existing features provided by a web server developed for this purpose. This allows you to use all the state of the art features such as advanced protocol support (HTTPS, HTTP/2.0), HTTP keep-alive, high performance static file delivery, HTTP compression, or URL redirect/rewrite services without increases the overhead and complexity of building anything into your application code.
```nim
import fastkiss
import re
from strutils import `%`

proc main() =
  let app = newApp()
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
  
  app.get("/static", proc (req: Request) {.async.} =
    await req.sendFile("./test.txt")
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
    fastcgi_param HTTP_COOKIE $http_cookie;
    fastcgi_param HTTP_AUTHORIZATION $http_authorization;

    client_max_body_size 1000M;
    include fastcgi_params;
    fastcgi_pass 127.0.0.1:9000;
  }
}
```
APACHE2 FastCGI Configuration File Example
```
Listen 127.0.0.1:8080
LoadModule proxy_module modules/mod_proxy.so
LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so
LoadModule rewrite_module modules/mod_rewrite.so
# Need a server with SSL support
# LoadModule http2_module modules/mod_http2.so

<IfModule mod_proxy_fcgi.c>
<VirtualHost *:8080>
  ServerName example
  ServerAlias anotherexample
  ServerAdmin admin@example.tld

  ErrorLog /var/log/httpd/example_error.log
  CustomLog /var/log/httpd/example_requests.log combined

  ProxyPass "/" "fcgi://localhost:9000/"

  # Need a server with SSL support
  # Protocols h2 http/1.1

  RewriteEngine on
  RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
</VirtualHost>
</IfModule>
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
