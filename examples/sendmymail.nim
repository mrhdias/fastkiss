#
# Sample app that shows how to send emails with attachments
# from a web form using the FastKiss Framework.
#
# nimble install https://github.com/mrhdias/fastkiss
# nim c -d:ssl -r sendmymail.nim
# http://example:8080/
#
# How to send email through your gmail account?
# For test purposes access this link:
# https://myaccount.google.com/lesssecureapps
# Allow less secure apps: OFF (Turn ON)
#
import fastkiss
import smtp
import re
import strutils, base64, encodings
import json
import asyncfile
import os
import random
import times

const
  fromAddress = "yourmail@gmail.com"
  username = "youremail@gmail.com"
  password = "********"

const debug = false

randomize()

func digitsAndLetters(): string =
  for c in Digits + Letters:
    result.add(c)

const chars = digitsAndLetters()

proc validateEmail(emailAddress: string): bool =
  return match(emailAddress, re"""^(([^<>()\[\]\.,;:\s@\"]+(\.[^<>()\[\]\.,;:\s@\"]+)*)|(\".+\"))@(([^<>()[\]\.,;:\s@\"]+\.)+[^<>()[\]\.,;:\s@\"]{2,})$""")

#
# https://en.wikipedia.org/wiki/Quoted-printable
#
const safeChars = IdentChars + {
  ' ', '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/',
  ':', ';', '<', '>', '?', '@', '[', '\\', ']', '^', '_', '`', '{', '|', '}', '~'
}

proc quotedPrintable(str, destEncoding: string, srcEncoding = "utf-8", lineLen = 76, newLine = "\r\n"): string =
  var count = 0
  for c in convert(str, destEncoding, srcEncoding):
    if count == lineLen - (1 + newLine.len): # lineLen - 1('=') - 2("\r\n")
      result.add('=')
      result.add(newLine)
      count = 0

    if c.char in safeChars:
      result.add(c)
      count += 1
    else:
      result.add('=')
      result.add(c.ord().toHex(2)) # 3(=XX) X = hex
      count += 3


proc genBoundary(): string =
  for _ in .. 52:
    result.add(chars[rand(0 .. (chars.len - 1))])


proc fileGetContents(filename: string): Future[string] {.async.} =
  try:
    let file = openAsync(filename, fmRead)
    let data = await file.readAll()
    file.close()
    return data
  except OSError as e:
    echo "$1: $2" % [e.msg, filename]


proc stringifyHeaders(headers: varargs[tuple[name, value: string]]): string =
  for header in headers:
    result.add("$1: $2\c\L" % [header.name, header.value])


#
# https://en.wikipedia.org/wiki/MIME
#
proc mimeMultipartMsg(
  boundary,
  message: string,
  files: seq[FileAttributes],
  workingDir: string): Future[string] {.async.} =

  var parts: seq[string]
  parts.add("This is a message with multiple parts in MIME format.\c\L")

  let msgHeaders = stringifyHeaders(
    ("Content-Type", "text/plain; charset=\"UTF-8\""),
    ("Content-Transfer-Encoding", "quoted-printable")
  )
  parts.add("\c\L$1\c\L$2\c\L" % [msgHeaders, quotedPrintable(message, "utf-8")])

  for file in files:
    let data = await fileGetContents(workingDir / file.filename)
    let attchHeaders = stringifyHeaders(
      ("Content-Type", if file.content_type == "text/plain": "text/plain; charset=\"UTF-8\"" else: file.content_type),
      ("Content-Transfer-Encoding", if file.content_type == "text/plain": "quoted-printable" else: "base64")
    )
    parts.add("\c\L$1\c\L$2\c\L" % [
      attchHeaders, if file.content_type == "text/plain": quotedPrintable(data, "utf-8") else: encodeMime(data)
    ])

  var message = parts.join("--$1" % boundary)
  message.add("--$1--" % boundary)

  return message


proc showForm(req: Request) {.async.} = """
<!Doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width">
    <title>Send May mail</title>
  </head>
  <body>
    <style>
form > div {
  width: fit-content;
  margin: 0 auto;
  border: 1px solid #000;
}

form > div > div {
  padding: 10px;
  background-color: #E0E0E0;
  margin: 1px;
}

form > div > div:nth-child(7) {
  text-align: center;
}

input, textarea {
  width: 250px;
}

label {
  display: inline-block;
  width: 150px;
  text-align: right;
}
    </style>
    <form method="post" id="sendmail_form">
      <div>
        <div>
          <strong>Send My Mail</strong>
        </div>
        <div>
          <label for="to_address">To:</label>
          <input id="to_address" type="text" name="to_address" value="">
        </div>
        <div>
          <label for="subject">Subject:</label>
          <input id="subject" type="text" name="subject" value="">
        </div>
        <div>
          <label style="vertical-align: top;" for="message">Message:</label>
          <textarea id="message" name="message" rows="4" cols="20"></textarea>
        </div>
        <div>
          <label for="attachment">Attachment:</label>
          <input id="attachment" type="file" name="attachment" accept="text/*">
        </div>
        <div>
          <label for="attachment">Attachment:</label>
          <input id="attachment" type="file" name="attachment" accept="text/*">
        </div>
        <div>
          <button onclick="sendmail();">Send</button>
        </div>
        <div id="warning">When you're ready, click send.</div>
      </div>
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

  const formData = new FormData()
  formData.append('to_address', to_address)
  formData.append('subject', subject)
  formData.append('message', message)

  for (let i = 0; i < document.getElementsByName("attachment").length; i++) {
    let attachments = document.getElementsByName("attachment")[i];
    if (attachments.files[i] !== undefined) {
      formData.append('attachment', attachments.files[i])
    }
  }

  fetch("/sendmail", {
    method: "post",
    // headers: { 'Content-Type': 'multipart/form-data' },
    body: formData
  }).then(
    function(response) {
      if (response.status !== 200) {
        console.log('Looks like there was a problem. Status Code: ' + response.status);
        if (response.status === 413) {
          document.getElementById("warning").innerHTML = "The message exceeds 2MB :(";
        }
        return;
      }

      // Examine the text in the response
      response.json().then(function(data) {
        console.log(JSON.stringify(data));
        if (data["status"] == "ok") {
          document.getElementsByName("to_address")[0].value = "";
          document.getElementsByName("subject")[0].value = "";
          document.getElementsByName("message")[0].value = "";
          document.getElementsByName("attachment")[0].value = "";
          document.getElementsByName("attachment")[1].value = "";
          document.getElementById("warning").innerHTML = "Message sent successfully :)";
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

  if formData.len == 0:
    respond(%* {
      "status": "error",
      "message": "No data has been submitted!"
    })
    return

  if debug:
    echo "Working Directory: ", $req.headers["working-directory"]
    echo "Data from Form: ", $formData
    echo "Files from Form: ", $formFiles

  var errors: seq[string]
  if not (("to_address" in formData) and validateEmail(formData["to_address"])):
    errors.add("To Address")

  if not (("subject" in formData) and (formData["subject"].len > 0)):
    errors.add("Subject")

  if not (("message" in formData) and (formData["message"].len > 0)):
    errors.add("Message")

  if errors.len > 0:
    await req.respond(%* {
      "status": "not ok",
      "message": "Error in the $1!" % errors.join(", ")
    })
    return

  var otherHeaders: seq[tuple[name, value: string]]
  otherHeaders.add(("Date", format(now().toTime(), "ddd, d MMM yyyy HH:mm:ss zzzz", utc())))

  var message = ""
  if (formFiles.len > 0) and ("attachment" in formFiles):
    let boundary = "_$1_FASTKISS_" % genBoundary()

    otherHeaders.add(("MIME-Version", "1.0"))
    otherHeaders.add(("Content-Type", "multipart/mixed; boundary=$1" % boundary))

    var files: seq[FileAttributes]
    for file in formFiles.allValues("attachment"):
      files.add(file)

    message = await mimeMultipartMsg(
      boundary,
      formData["message"],
      files,
      req.headers["working-directory"]
    )
  else:
    otherHeaders.add(("Content-Type", "text/plain; charset=\"UTF-8\""))
    otherHeaders.add(("Content-Transfer-Encoding", "quoted-printable"))

    message = quotedPrintable(formData["message"], "utf-8")

  let msg = createMessage(
    formData["subject"],
    message,
    @[formData["to_address"]],
    @[],
    otherHeaders
  )

  if debug:
    echo "Message:\c\L", $msg
    await req.respond(%* {
      "status": "error",
      "message": "The message was not sent the debug is set true!"
    })
    return

  try:
    let smtpConn = newAsyncSmtp(useSsl = true, debug=true)
    await smtpConn.connect("smtp.gmail.com", Port 465)
    await smtpConn.auth(username, password)
    await smtpConn.sendmail(
      fromAddress,
      @[formData["to_address"]],
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
  app.config.maxBody = 2097152 # 2MB = 2097152 Bytes

  app.get("/", showForm)
  app.post("/sendmail", sendMail)

  app.run()

main()
