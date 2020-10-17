# Package

version     = "0.0.1"
author      = "Henrique Dias"
description = "FastKiss - A FastCGI Web Framework for Nim"
license     = "MIT"

skipDirs = @["examples", "tests"]

# Deps

requires "nim >= 1.4.0"

task test, "Test Asynfastcgiserver":
  exec "nim c -r -d:release -d:usestd tests/app.nim"
