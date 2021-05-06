#
# It is possible to insert the content of one nim file into another nim file.
# nim c -r example.nim 
#
import fastkiss
import tables
from strformat import `&`

proc showHome(req: Request) {.async.} =
  const title = "Home"
  include "parts/header.nim"
  "Basic include example".resp
  include "parts/footer.nim"

proc showTest(req: Request) {.async.} =
  const title = "Test"
  include "parts/header.nim"
  "Test...".resp
  include "parts/footer.nim"

proc showContacts(req: Request) {.async.} =
  const title = "Contacts"
  include "parts/header.nim"
  """Example Corporation<br />
Example Street 23<br />
9876 Example City<br />
""".resp
  include "parts/footer.nim"

proc main() =
  let app = newApp()
  app.get("/", showHome)
  app.get("/test", showTest)
  app.get("/contacts", showContacts)
  app.run()

main()
