#!/bin/bash
set -e

# Analyze Ruby database
codeql database analyze --format=sarif-latest --output=codeql-ruby.sarif --sarif-add-snippets -- enroll/ruby

# Analyze JavaScript database
codeql database analyze --format=sarif-latest --output=codeql-js.sarif --sarif-add-snippets -- enroll/javascript