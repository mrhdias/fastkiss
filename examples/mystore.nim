#
# mysql -u test -p
# MariaDB [(none)]> CREATE DATABASE MyStore
# MariaDB [(none)]> GRANT ALL PRIVILEGES ON MyStore.* TO 'test'@'localhost';
# MariaDB [(none)]> FLUSH PRIVILEGES;
# MariaDB [(none)]> exit
#
# nimble install amysql
# nimble install https://github.com/mrhdias/fastkiss
# nim c -r mystore.nim
# http://example:8080/
#
# "respond(data: string)" is a shortcut for "await req.respond(data: string)"
# "resp(data: string)" is a shortcut for "await req.resp(data: string)"
#
import asyncdispatch
import fastkiss
import sugar
import amysql
import strutils
import system/ansi_c

const
  dbname = "MyStore"
  hostname = "localhost"
  username = "test"
  password = "mytest"


proc validatePrice(price: string): bool =
  if price.len == 0: return false
  try:
    discard parseFloat(price)
    return true
  except ValueError as e:
    echo "Price Error: ", e.msg
    return false


proc validateQuantity(quantity: string): bool =
  if quantity.len == 0: return false
  try:
    discard parseInt(quantity)
    return true
  except ValueError as e:
    echo "Quantity Error: ", e.msg
    return false


proc addProduct(
  req: Request,
  dbConn: Connection) {.async.} =

  var errors: seq[string]
  if not ("sku" in req.body.formdata and req.body.formdata["sku"].len > 0):
    errors.add("sku")
  if not ("title" in req.body.formdata and req.body.formdata["title"].len > 0):
    errors.add("title")
  if not ("quantity" in req.body.formdata and validateQuantity(req.body.formdata["quantity"])):
    errors.add("quantity")
  if not ("price" in req.body.formdata and validatePrice(req.body.formdata["price"])):
    errors.add("price")
  
  if errors.len > 0:
    respond "Errors: $1<br /><a href=\"/\">Back</a>" % errors.join(", ")
    return

  try:
    let queryResult = await dbConn.rawQuery("insert into products (sku, title, quantity, price) VALUES ('$1', '$2', $3, $4)" % [
      req.body.formdata["sku"],
      req.body.formdata["title"],
      req.body.formdata["quantity"],
      req.body.formdata["price"]
    ])
    echo queryResult
  except:
    let
      e = getCurrentException()
      msg = getCurrentExceptionMsg()
    echo "Got exception ", repr(e), " with message ", msg
    "An error happen when adding the records!<br /><a href=\"/\">Back</a>".respond
    return

  "Record added successfully :-)<br /><a href=\"/\">Back</a>".respond


proc delProduct(
  req: Request,
  dbConn: Connection) {.async.} =

  if "bookId" in req.body.formdata:
    var ids: seq[string]
    for id in req.body.formdata.allValues("bookId"):
      ids.add(id)
    if ids.len > 0:
      try:
        let queryResult = await dbConn.rawQuery("delete from products where id in ($1)" % ids.join(","))
        echo queryResult
        "Records deleted successfully :-)<br /><a href=\"/\">Back</a>".respond
      except:
        let
          e = getCurrentException()
          msg = getCurrentExceptionMsg()
        echo "Got exception ", repr(e), " with message ", msg
        "An error happen when deleting the records!<br /><a href=\"/\">Back</a>".respond

      return

  "No records to delete!<br /><a href=\"/\">Back</a>".respond



proc showProducts(
  req: Request,
  dbConn: Connection) {.async.} =

  """
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width">
    <title>DB Test</title>
  </head>
  <body>
  """.resp

  let queryResult = await dbConn.rawQuery("select * from products")
  if queryResult.rows.len() > 0 and queryResult.columns.len() == 6:

    """
<form method="post" action="/del">
<table>
<tr>
<th>ID</th>
<th>SKU</th>
<th>Title</th>
<th>Quantity</th>
<th>Price</th>
<th>Date Added</th>
</tr>""".resp

    for row in queryResult.rows:
      "<tr>".resp
      var first = true
      for col in row:
        resp (if first: """<td><input type="checkbox" name="bookId" value="$1"></td>""" else: "<td>$1</td>") % col
        first = false
      "<tr>".resp
    """
<tr>
<td colspan="6"><input type="submit" value="Delete Books"></td>
</tr>
</table>
</form>""".resp

  else:
    "No Books!".resp

  """
<form method="post" action="/add">
<table>
<tr>
<th>SKU</th>
<th>Title</th>
<th>Quantity</th>
<th>Price</th>
</tr>
<tr>
<td><input type="text" size="10" maxlength="10" name="sku" value="AA00000000"></td>
<td><input type="text" size="64" maxlength="128" name="title" value="Unknown"></td>
<td><input type="number" size="4" name="quantity" value="0"></td>
<td><input type="text" size="8" maxlength="8" name="price" value="0.00"></td>
</tr>
<tr>
<td colspan="4"><input type="submit" value="Add Book"></td>
</tr>
</table>
</form>  
  """.resp

  "<body></html>".resp

proc setupDatabase(dbConn: Connection) {.async.} =
  discard await dbConn.selectDatabase(dbname)
  discard await dbConn.rawQuery("drop table if exists products")
  discard await dbConn.rawQuery("""create table products (
id int(10) unsigned NOT NULL AUTO_INCREMENT,
sku char(10) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
title varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
quantity int(10) unsigned NOT NULL DEFAULT 0,
price decimal(7,2) NOT NULL DEFAULT 99999.99,
reg_date timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
PRIMARY KEY (id)
)""")


proc connect2db(): Future[Connection] {.async.} =
  try:
    return await open(hostname, username, password, dbname)
  except OSError as e:
    echo "MySQL/MariaDB server is down :( ", e.msg
    quit(QuitFailure)


proc main() {.async.} =

  let dbConn = await connect2db()

  await dbConn.setupDatabase()

  let app = newApp()
  app.config.port = 9000 # optional if default port

  # Catch ctrl-c
  addSignal(SIGINT, proc(fd: AsyncFD): bool =
    asyncCheck dbConn.close()
    app.close()
    echo "App shutdown completed! Bye-Bye Kisses :)"
    quit(QuitSuccess)
  )

  app.get("/", (req: Request) => showProducts(req, dbConn))
  app.post("/add", (req: Request) => addProduct(req, dbConn))
  app.post("/del", (req: Request) => delProduct(req, dbConn))

  app.run()

waitFor main()
