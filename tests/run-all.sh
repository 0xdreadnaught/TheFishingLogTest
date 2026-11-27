#!/usr/bin/env bash
# Runs every check from the repository root. The Lua runner exits 0 even when a
# test fails, so this looks at the output instead.
cd "$(dirname "$0")/.." || exit 1
cli=tests/lua-parser/node_modules/fengari-node-cli/src/lua-cli.js
[ -f "$cli" ] || { echo "Run: (cd tests/lua-parser && npm ci)"; exit 1; }
bad=0
out=$(node tests/check-fishing-lua.cjs 2>&1); echo "$out"
echo "$out" | grep -q '^PASS' || bad=1
for t in sync sync-report sync-report-ui portrait isolation; do
  out=$(node "$cli" "tests/test-fishing-$t.lua" 2>&1); echo "$out"
  if echo "$out" | grep -qE '^FAIL|stack traceback' || ! echo "$out" | grep -q '^PASS'; then bad=1; echo ">>> test-fishing-$t FAILED"; fi
done
[ $bad -eq 0 ] && echo "ALL CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }
