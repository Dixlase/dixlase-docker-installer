#!/bin/bash
# Verification harness for block-destructive-container-ops.sh.
# Runs a matrix of sample inputs through the hook and reports
# expected-vs-actual decisions.
#
# Not invoked by Claude Code itself — run manually:
#   bash .claude/hooks/test-block-destructive-container-ops.sh

set -u
HOOK="$(dirname "$0")/block-destructive-container-ops.sh"

pass=0
fail=0

run_case() {
  local expected="$1" cmd="$2"
  local result decision

  result=$(printf '%s' "$cmd" | jq -nRc --arg cmd "$cmd" '{tool_input: {command: $cmd}}' | "$HOOK" 2>/dev/null)
  if [ -n "$result" ]; then
    decision=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecision')
  else
    decision="allow"
  fi

  if [ "$decision" = "$expected" ]; then
    printf "  PASS  %-58s  [expected=%s actual=%s]\n" "${cmd:0:56}" "$expected" "$decision"
    pass=$((pass + 1))
  else
    printf "  FAIL  %-58s  [expected=%s actual=%s]\n" "${cmd:0:56}" "$expected" "$decision"
    fail=$((fail + 1))
  fi
}

echo "=== BLOCK cases (expected: deny) ==="
# Destructive op on non-dev container — the original incident pattern
run_case "deny"  "docker exec dixlase-brand-app php artisan test"
run_case "deny"  "docker exec dixlase-brand-app vendor/bin/phpunit"
run_case "deny"  "docker exec dixlase-brand-app php artisan migrate:fresh"
run_case "deny"  "docker exec dixlase-keys-app php artisan test"
run_case "deny"  "docker exec dixlase-docs-app php artisan migrate:reset"
run_case "deny"  "docker exec dixlase-demo-app php artisan db:wipe"
# Compose-style production container
run_case "deny"  "docker exec compose-php-1 php artisan test"
# Docker flags before container name
run_case "deny"  "docker exec --user www-data dixlase-brand-app php artisan test"
# docker compose form
run_case "deny"  "docker compose exec dixlase-brand-app php artisan test"

echo ""
echo "=== ALLOW cases (expected: allow) ==="
# Dev container — explicitly allow-listed
run_case "allow" "docker exec dixlase-dev-app php artisan test"
run_case "allow" "docker exec dixlase-sandbox-app php artisan test"
run_case "allow" "docker exec dixlase-dev-app php artisan migrate:fresh"
# Non-destructive op even on production container — out of scope
run_case "allow" "docker exec dixlase-brand-app ls /tmp"
run_case "allow" "docker exec dixlase-brand-app php artisan cache:clear"
# Flags + dev container
run_case "allow" "docker exec --user www-data dixlase-dev-app php artisan test"
# Alternate dev naming (Sail-style laravel.test)
run_case "allow" "docker exec dixlase-dev-laravel.test php artisan test"
# Host-level destructive — Core hook handles this case; out of scope here
run_case "allow" "php artisan tinker"
run_case "allow" "git status"

echo ""
echo "=== Summary ==="
echo "  passed: $pass"
echo "  failed: $fail"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
