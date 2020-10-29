#
# nimble install https://github.com/mrhdias/fastkiss
# nim c -r uploads.nim 
# http://example:8080/
#
import fastkiss
import tables
from strutils import `%`

template formFiles(): FormTableRef[string, FileAttributes] =
  req.body.formfiles

template formData(): FormTableRef[string, string] =
  req.body.formdata


proc showPage(req: Request) {.async.} = """
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width">
    <title>Upload Test</title>
  </head>
  <body>
    <form action="/upload" method="post" enctype="multipart/form-data">
      File 1: <input type="file" name="testfile-1" accept="text/*"><br /><br />
      File 2: <input type="file" name="testfile-2" accept="text/*"><br /><br />
      File 2: <input type="file" name="testfile-2" accept="text/*"><br /><br />
      <hr>
      Input 1: <input type="text" name="testfield-1" value="Test A"><br /><br />
      Input 2: <input type="text" name="testfield-2" value="Test B"><br /><br />
      Input 2: <input type="text" name="testfield-2" value="Test C"><br /><br />
      <hr>
      <input type="checkbox" name="remove_upload_dir" value="yes" checked> Remove Upload Directory<br />
      <br />
      <input type="submit">
    </form>
  </body>
</html>
""".respond

proc showResult(req: Request) {.async.} =

  req.response.headers["content-type"] = "text/plain; charset=utf-8"

  resp "$1\c\L" % $req
  resp "Working Directory: $1\c\L" % $req.headers["working-directory"]

  resp "$1\c\L" % $formData
  resp "$1\c\L" % $formData["testfield-2"]

  for field in formData.allValues("testfield-2"):
    resp "Input text of \"testfield-2\": $1\c\L" % $field

  resp "Number of input file with diferent names: $1\c\L" % $formFiles.len
  resp "$1\c\L" % $formFiles
  resp "Number of files with same input name \"testfile-2\": $1\c\L" % $formFiles.len("testfile-2")
  resp "Filename: $1\c\L" % $formFiles["testfile-2"].filename
  resp "Content Type: $1\c\L" % $formFiles["testfile-2"].content_type
  resp "Filesize: $1\c\L" % $formFiles["testfile-2"].filesize

  for file in formFiles.allValues("testfile-2"):
    resp "File: $1\c\L" % $file

proc main() =
  let app = newApp()
  app.config.port = 9000 # optional if default port
  app.config.autoCleanTmpUploadDir = true

  app.get("/", showPage)
  app.post("/upload", showResult)

  app.run()

main()
