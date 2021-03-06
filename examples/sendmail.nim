#
# nimble install https://github.com/mrhdias/fastkiss
# nim c -d:ssl -r sendmail.nim
# http://example:8080/sendmail
#
# How to send email through your gmail account?
# For test purposes access this link:
# https://myaccount.google.com/lesssecureapps
# Allow less secure apps: OFF (Turn ON)
#
import fastkiss
import smtp
import regex
import strutils
import json

const
  fromAddress = "youremail@gmail.com"
  username = "youremail@gmail.com"
  password = "********"

proc validateEmail(emailAddress: string): bool =
  emailAddress.match(re"""^(([^<>()\[\]\.,;:\s@\"]+(\.[^<>()\[\]\.,;:\s@\"]+)*)|(\".+\"))@(([^<>()[\]\.,;:\s@\"]+\.)+[^<>()[\]\.,;:\s@\"]{2,})$""")

#
# "respond(data: string)" is a shortcut for "await req.respond(data: string)"
#
proc showForm(req: Request) {.async.} = """
<!Doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width">
    <title>Sendmail</title>
  </head>
  <body>
    <form method="post" id="sendmail_form">
      <strong>SendMail</strong><br />
      To: <input type="text" name="to_address" value=""><br />
      Subject: <input type="text" name="subject" value=""><br />
      Message:<br />
      <textarea name="message" rows="4" cols="20"></textarea><br />
      <button onclick="sendmail();">Send</button>
      <div id="warning">Not send</div>
    </form>

    <script>
/*<![CDATA[*/

function sendmail() {
  var form = document.getElementById('sendmail_form');
  function onSubmit(event) {
    if (event) { event.preventDefault(); }
    console.log('submitted');
  }
  form.addEventListener('submit', onSubmit, false);
  form.submit = onSubmit;

  let to_address = document.getElementsByName("to_address")[0].value;
  let subject = document.getElementsByName("subject")[0].value;
  let message = document.getElementsByName("message")[0].value;

  fetch("/sendmail", {
    method: "post",
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      to_address: to_address,
      subject: subject,
      message: message
    })
  }).then(
    function(response) {
      if (response.status !== 200) {
        console.log('Looks like there was a problem. Status Code: ' + response.status);
        return;
      }

      // Examine the text in the response
      response.json().then(function(data) {
        console.log(JSON.stringify(data));
        if (data["status"] == "ok") {
          document.getElementsByName("to_address")[0].value = "";
          document.getElementsByName("subject")[0].value = "";
          document.getElementsByName("message")[0].value = "";
        } else {
          document.getElementById("warning").innerHTML = data["message"];
        }
      });
    }
  ).catch(function(err) {
    console.log('Fetch Error :-S', err);
  });
}

/*]]>*/
    </script>
  </body>
</html>
  """.respond


proc sendMail(req: Request) {.async.} =

  if req.body.data.len == 0:
    await req.respond(%* {
      "status": "error",
      "message": "No data has been submitted!"
    })
    return

  let jsonNode = parseJson(req.body.data)

  var errors: seq[string]
  if not (("to_address" in jsonNode) and validateEmail(getStr(jsonNode["to_address"]))):
    errors.add("To Address")

  if not (("subject" in jsonNode) and getStr(jsonNode["subject"]).len > 0):
    errors.add("Subject")

  if not (("message" in jsonNode) and getStr(jsonNode["message"]).len > 0):
    errors.add("Message")

  if errors.len > 0:
    await req.respond(%* {
      "status": "not ok",
      "message": "Error in $1!" % errors.join(", ")
    })
    return

  let msg = createMessage(
    getStr(jsonNode["subject"]),
    getStr(jsonNode["message"]),
    @[getStr(jsonNode["to_address"])])

  try:
    let smtpConn = newAsyncSmtp(useSsl = true, debug=true)
    await smtpConn.connect("smtp.gmail.com", Port 465)
    await smtpConn.auth(username, password)
    await smtpConn.sendmail(
      fromAddress,
      @[getStr(jsonNode["to_address"])],
      $msg
    )
    await smtpConn.close()
  except ReplyError as e:
    echo "We made an error: ", e.msg
    await req.respond(%* {
      "status": "error",
      "message": "An error occurred while sending the message, please try again later..."
    })
    return

  await req.respond(%* {
    "status": "ok",
    "message": "The message is successfully sent!"
  })


proc main() = 
  let app = newApp()

  app.config.port = 9000

  app.get("/sendmail", showForm)
  app.post("/sendmail", sendMail)

  app.run()

main()
