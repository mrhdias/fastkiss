#
#               FastKiss FormTable
#        (c) Copyright 2020 Henrique Dias
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import tables

export tables

type
  FormTableRef*[K,V] = ref object
    table*: TableRef[K, seq[V]]

func `$`*[T](form: FormTableRef[string, T]): string {.inline.} =
  $form.table

proc clear*(form: FormTableRef) {.inline.} =
  form.table.clear()

# proc `[]`*[T](form: FormTableRef[string, T], key: string): T =
#   return form.table[key][0]

proc `[]`*[T](form: FormTableRef[string, T], key: string, idx: int | BackwardsIndex = 0): var T =
  ## Returns the ``idx``'th value associated with the given key. If there are
  ## no values associated with the key or the ``idx``'th value doesn't exist,
  ## an exception is raised.
  runnableExamples:
    var formdata = newFormTable[string, string]()
    formdata["one"] = "um"
    doAssert formdata["one"] == "um"
    formdata["two"] = "dois"
    formdata["two"] = "dos"
    doAssert formdata["two"] == "dois"
    doAssert formdata["two", 0] == "dois"
    doAssert formdata["two", 1] == "dos"
    doAssert formdata["two", ^1] == "dos"
    formdata["three"] = "tres"
    doAssert formdata["three"] == "tres"
  
  return form.table[key][idx]

proc `[]=`*[T](form: FormTableRef, key: string, value: T) =
  ## Adds the specified value to the specified key. Appends to any existing
  ## values associated with the key.
  runnableExamples:
    var formdata = newFormTable[string, string]()
    formdata["one"] = "um"
    doAssert formdata["one"] == "um"
    formdata["two"] = "dois"
    formdata["two"] = "dos"
    doAssert formdata["two"] == "dois"
    formdata["three"] = "tres"
    doAssert formdata["three"] == "tres"

  if key notin form.table:
    form.table[key] = @[]
  form.table[key].add(value)


proc `[]=`*[T](form: FormTableRef, key: string, idx: int | BackwardsIndex, value: T) =
  ## Adds the specified value to the ``idx``'th associated with the given key.
  runnableExamples:
    var formdata = newFormTable[string, string]()
    formdata["one"] = "um"
    doAssert formdata["one"] == "um"
    formdata["two"] = "dois"
    formdata["two"] = "dos"
    doAssert formdata["two"] == "dois"
    formdata["two", 1] = "deux"
    doAssert formdata["two", 0] == "dois"
    doAssert formdata["two", 1] == "deux"
    doAssert formdata["two", ^1] == "deux"
    formdata["three"] = "tres"
    doAssert formdata["three"] == "tres"
 
  form.table[key][idx] = value


proc `[]=`*[T](form: FormTableRef, key: string, value: seq[T]) =
  ## Sets the header entries associated with ``key`` to the specified list of
  ## values.
  ## Replaces any existing values.
  runnableExamples:
    var formdata = newFormTable[string, string]()
    formdata["four"] = @["quatro", "cuatro", "quatre"]
    doAssert formdata["four"] == "quatro"
    doAssert formdata["four", 1] == "cuatro"
    doAssert formdata["four", ^1] == "quatre"

  form.table[key] = value

proc del*(form: FormTableRef, key: string) =
  ## Delete the header entries associated with ``key``
  form.table.del(key)

func contains*(form: FormTableRef, key: string): bool =
  return form.table.hasKey(key)

func hasKey*(form: FormTableRef, key: string): bool =
  return form.table.hasKey(key)

func len*(form: FormTableRef): int {.inline.} = form.table.len

proc len*(form: FormTableRef, key: string): int =
  form.table[key].len

proc last*[T](form: FormTableRef[string, T], key: string): T =
  return form.table[key][^1]

iterator pairs*[T](form: FormTableRef[string, T]): tuple[key: string, value: T] =
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

  ft["one"] = "um"
  echo "one => ", ft["one"]
  ft["two"] = "dois"
  ft["two"] = "dos"
  echo "two => ", ft["two"]
  echo "two => ", ft["two", 0]
  echo "two => ", ft["two", 1]
  ft["two", ^1] = "deux"
  echo "two => ", ft["two", ^1]
  ft["three"] = "tres"
  echo "three => ", ft["three"]

  ft["four"] = @["quatro", "cuatro", "quatre"]
  echo "four => ", ft["four"]
  echo "four => ", ft["four", 1]
  echo "four => ", ft["four", ^1]
