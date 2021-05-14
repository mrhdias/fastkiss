#
# https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events
# https://httpd.apache.org/docs/trunk/mod/mod_proxy_fcgi.html
#
#[
# Apache2 Configuration
<IfModule mod_proxy_fcgi.c>
<VirtualHost *:8080>
    ServerName example

    ErrorLog /var/log/httpd/example_error.log
    CustomLog /var/log/httpd/example_requests.log combined

    ProxyPass "/" "fcgi://localhost:9000/" flushpackets=on

    ErrorDocument 503 "Service Temporary Unavailable"

    RewriteEngine on
    RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
</VirtualHost>

</IfModule>
]#

import fastkiss
import asyncnet
from strutils import split
from times import epochTime
from oids import genOid, `$`
from md5 import toMD5, `$`

const
  pingTime = 10 # 10 seconds
  timeout = 30  # 30 seconds

proc ping(req: Request, testClients: TableRef[string, float]) {.async, gcsafe.} =
  let pair = req.url.query.split('=')

  echo "Pair: ", $pair
  if (pair.len == 2) and (pair[0] == "key") and (pair[1] in testClients):
    testClients.del(pair[1])
  
  "".respond

proc ssedemo(req: Request, testClients: TableRef[string, float]) {.async, gcsafe.} =
  req.response.headers["cache-control"] = "no-cache"
  req.response.headers["content-type"] = "text/event-stream; charset=utf-8"

  var savedTime = epochTime()
  var key = ""
  var i = 0
  while not req.client.isclosed():
    if (key != "") and (key in testClients):
      if (epochTime() - testClients[key]) > timeout:
        testClients.del(key)
        break
    else:
      key = ""

    echo "I'm alive ", $i
    var msg = "event: test\ndata: " & $i & "\n\n"

    let elapsed = epochTime() - savedTime
    if key == "" and (elapsed >= pingTime):
      key = $toMD5($genOid())
      savedTime = epochTime()
      testClients[key] = savedTime
      msg.add("event: ping\ndata: " & key & "\n\n")
    
    msg.resp
    await sleep_async(1000)
    inc(i)

  echo "client disconnected"

proc home(req: Request) {.async.} =
  """<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width">
    <title>Test SSE</title>
  </head>
  <body>
    <div id="testdemo"></div>
    <div id="testping"></div>
    <script type="text/javascript">
//<![CDATA[

if(typeof(EventSource) !== "undefined") {
  // Yes! Server-sent events support!
  
  const evtSource = new EventSource("ssedemo");
  
  evtSource.onopen = function (event) {
    console.log("EventSource opened");
  }
  
  // evtSource.onmessage = function(event) {
  //   console.log("New Message...");
  //   console.log("Data: " + event.data);
  //
  //   document.getElementById('demotest').innerHTML = "message: " + event.data;
  // }
  
  evtSource.addEventListener("test", function(event) {
    console.log("New Test");
    console.log("Data: " + event.data);
    document.getElementById('testdemo').innerHTML = "message: " + event.data;
  });
  
  evtSource.addEventListener("ping", function(event) {
    console.log("New Ping");
    console.log("Ping Data: " + event.data);
    document.getElementById('testping').innerHTML = "ping data: " + event.data;
    const xhttp = new XMLHttpRequest();
    xhttp.open("GET", "ping?key=" + event.data, true);
    xhttp.send();
  });
  
  evtSource.onerror = function(err) {
    console.error("EventSource failed:", err);
  };
} else {
  // Sorry! No server-sent events support..
  console.log("Sorry! No server-sent events support..");
}

//]]>
    </script>
  </body>
</html>""".respond

proc main() =
  let app = newApp()

  var testClients = newTable[string, float]()

  app.get("/ping", proc (req: Request): Future[void] = ping(req, testClients))
  app.get("/ssedemo", proc (req: Request): Future[void] = ssedemo(req, testClients))
  app.get("/", home)

  app.run()

main()
