# FastKiss - Nim's FastCGI Web Framework

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

FastCGI NGINX Configuration Example
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
```
