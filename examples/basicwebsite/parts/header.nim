#
# Header Demo File
#

let t = {
  "Home": "/",
  "FastKISS": "https://github.com/mrhdias/fastkiss",
  "Test": "/test",
  "Contacts": "/contacts"
}.toOrderedTable

resp &"""<!DOCTYPE html>
  <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width">
      <title>{title}</title>
    </head>
    <body>
      <h1>FastKISS Demo</h1>
      <strong>Menu:</strong>
      <ul>"""

for k, v in pairs(t):
  resp &"""<li><a href="{v}">{k}</a></li>"""

"</ul><hr>".resp
