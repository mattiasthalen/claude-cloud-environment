#!/bin/bash
# An environment that deliberately requests no CLIs stays valid and says so
# explicitly, so an empty selection never reads like a mangled argument line.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

harness_run

assert_status 0
assert_output_contains "no tools requested"
