#
#               FastKiss FormTable
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import tables

type
  FormTableRef*[K,V] = ref object
    table*: TableRef[K, seq[V]]

func `$`*[T](form: FormTableRef[string, T]): string {.inline.} =
  $form.table

proc `[]`*[T](form: FormTableRef[string, T], key: string): T =
  return form.table[key][0]

proc `[]=`*[T](form: FormTableRef, key: string, value: T) =
  if key notin form.table:
    form.table[key] = @[]
  form.table[key].add(value)

proc `[]=`*[T](form: FormTableRef, key: string, value: seq[T]) =
  form.table[key] = value

func contains*(form: FormTableRef, key: string): bool =
  return form.table.hasKey(key)

func hasKey*(form: FormTableRef, key: string): bool =
  return form.table.hasKey(key)

func len*(form: FormTableRef): int {.inline.} = form.table.len

proc len*(form: FormTableRef, key: string): int =
  form.table[key].len

proc last*[T](form: FormTableRef[string, T], key: string): T =
  return form.table[key][^1]

iterator pairs*[T](form: FormTableRef[string, T]): tuple[key, value: T] =
  for k, v in form.table:
    for value in v:
      yield (k, value)

iterator allValues*[T](form: FormTableRef[string, T], key: string): T =
  for value in form.table[key]:
    yield value


proc newFormTable*[K, V](): FormTableRef[K, V] =
  new result
  result.table = newTable[K, seq[V]]()


when not defined(testing) and isMainModule:
  var ft = newFormTable[string, string]()

  ft["a"] = "1"
  ft["b"] = newSeq[string]()
  ft["b"] = "2"
  ft["b"] = "3"
  ft["c"] = "4"

  echo ft["a"]
  echo ft["b"]
  echo ft["c"]

  echo "Length of sequence: "
  echo "len a: ", ft.len("a")
  echo "len b: ", ft.len("b")
  echo "len c: ", ft.len("c")

  echo ">> Has Key:"
  if ft.hasKey("b"):
    echo "b => ", ft["b"]

  echo ">> Test in:"
  if "b" in ft:
    echo "Has Key: b => ", ft["b"]

  echo ">> Pairs:"
  for (k, v) in ft.pairs:
    echo k, " => ", v

  echo ">> All Values:"
  for v in ft.allValues("b"):
    echo "b => ", v
