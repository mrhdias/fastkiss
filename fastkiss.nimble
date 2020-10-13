# Package

version     = "0.0.1"
author      = "Henrique Dias"
description = "FastKiss - Nim's FastCGI Web Framework"
license     = "MIT"

skipDirs = @["examples", "tests"]

# Deps

requires "nim >= 1.2.6"

task test, "Test Asynfastcgiserver":
  exec "nim c -r -d:release -d:usestd tests/app.nim"
