import fastkiss
import karax / [karaxdsl, vdom]


proc layout(inner : VNode) : string =
  let vnode = buildHtml(html):
    head:
      meta(charset="utf-8")
      link(href="", rel="stylesheet")
    body:
      inner
  "<!DOCTYPE html>\n" & $vnode


proc showPage(req: Request) {.async.} =
  const places = @["Apples", "Bananas", "Strawberry", "Oranges", "Melon"]

  let vnode = buildHtml(tdiv(class = "mt-3")):
    h1: text "My Web Page"
    p: text "Hello world"
    span: text "my favorite fruit"
    ul:
      for place in places:
        li: text place
    dl:
      dt: text "Can I use Karax for client side single page apps?"
      dd: text "Yes"

      dt: text "Can I use Karax for server side HTML rendering?"
      dd: text "Yes"

  respond $vnode.layout


proc main() =
  let app = newApp()
  app.config.port = 9000

  app.get("/", showPage)

  app.run()
