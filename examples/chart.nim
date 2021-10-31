#
# nimble install https://github.com/mrhdias/fastkiss
# nim c -r chart.nim
# http://example:8080/
#
# "respond(data: string | JsonNode)" is a shortcut for "await req.respond(data: string | JsonNode)"
#
import fastkiss
from strutils import `%`, split, parseFloat
import asyncfile
import json
import times

proc getData(req: Request) {.async.} =

  let file = openAsync("/proc/loadavg", fmRead)
  let line = await file.readLine()
  let parts = line.split(' ', maxsplit = 4)
  file.close()

  let data = %* {
    "data": {
      "time": now().format("HH:mm:ss"),
      "cpu": int(parseFloat(parts[2]) * 100)
    },
    "status": "ok"
  }

  respond data


proc showPage(req: Request) {.async.} = """
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width">
    <title>Chart</title>
  </head>
  <body>
    <div id="chart"></div>
    <script src="https://unpkg.com/frappe-charts@latest"></script>
    <script>
/*<![CDATA[*/

const data = {
  labels: new Array(50).fill("00:00:00"),
  datasets: [
    {
      name: "Some Data", type: "line",
      values: new Array(50).fill(0)
    }
  ]
}

const chart = new frappe.Chart("#chart", {
  title: "My Awesome Chart",
  data: data,
  type: 'line', // or 'bar', 'line', 'scatter', 'pie', 'percentage'
  height: 250,
  colors: ['red'],
  axisOptions: {
    xIsSeries: true
  }
})

function update_chart() {
  fetch("/getdata", {
    method: "get",
  }).then(
    function(response) {
      if (response.status !== 200) {
        console.log('Looks like there was a problem. Status Code: ' + response.status);
        return;
      }
      // Examine the text in the response
      response.json().then(function(data) {
        // console.log(JSON.stringify(data))

        chart.removeDataPoint(0);
        chart.addDataPoint(data["data"]["time"], [data["data"]["cpu"]]);

      });
    }
  ).catch(function(err) {
    console.log('Fetch Error :-S', err);
  });
}

window.setInterval(function(){
  // chart.removeDataPoint(0);
  // let x = Math.floor(Math.random() * 100) + 1;  
  // chart.addDataPoint("12am-3pm", [x]);
  update_chart();
}, 10000);

update_chart();
// clearInterval() 

/*]]>*/
    </script>
  </body>
</html>
  """.respond

proc main() =
  let app = newApp()
  app.config.port = 9000
  app.config.staticDir = "static"
  
  app.get("/", showPage)
  app.get("/getdata", getData)

  app.run()

main()
