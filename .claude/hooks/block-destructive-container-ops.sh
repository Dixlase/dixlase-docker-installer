#!/bin/bash
# Pre-tool hook: Block destructive operations against non-dev containers.
#
# Context: 2026-05-29 Brand MySQL DROP incident — a Claude Code session
# ran `docker exec dixlase-brand-app php artisan test ...`, which caused
# RefreshDatabase to issue migrate:fresh against the production MySQL
# instance and DROP every table. See the post-mortem at
# html/.claude/plans/test-incident-followup.md (task J).
#
# This hook is a defense-in-depth layer over the Core-level
# .claude/hooks/block-dangerous-commands.sh:
#   - Core hook blocks `migrate:fresh / migrate:reset / db:wipe`
#     unconditionally for ANY container.
#   - This installer-level hook additionally blocks `artisan test` and
#     `vendor/bin/phpunit` when the target docker container is NOT on
#     the allow-list (dev / sandbox).
#
# Allow-listed containers (safe to run destructive ops on):
#   - dixlase-dev-app, dixlase-dev-laravel.test
#   - dixlase-sandbox-app, dixlase-sandbox-laravel.test
#   - any container with prefix dixlase-dev- or dixlase-sandbox-
#
# Everything else (dixlase-brand-*, dixlase-docs-*, dixlase-demo-*,
# dixlase-keys-*, compose-php-*, etc.) is treated as production-class.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Skip if no command (e.g., other Bash tool invocations)
if [ -z "$COMMAND" ]; then
  exit 0
fi

# 1. Does the command run a destructive operation?
DESTRUCTIVE_PATTERN='\b(php artisan (test|migrate:(fresh|reset|refresh)|db:wipe)|vendor/bin/phpunit|composer (test|run-script test))\b'
if ! echo "$COMMAND" | grep -qE "$DESTRUCTIVE_PATTERN"; then
  exit 0
fi

# 2. Is it being run inside a container via docker exec?
if ! echo "$COMMAND" | grep -qE '\bdocker( compose)? exec\b'; then
  # Not a docker exec invocation. The host-level Core hook handles
  # destructive migrate:* / db:wipe unconditionally; pass through.
  exit 0
fi

# 3. Does the docker exec target an allow-listed dev/sandbox container?
#    Pattern matches both dixlase-dev-app and dixlase-dev-laravel.test
#    (and the same with sandbox).
ALLOWED_CONTAINER_PATTERN='\bdixlase-(dev|sandbox)-[a-zA-Z._-]+\b'
if echo "$COMMAND" | grep -qE "$ALLOWED_CONTAINER_PATTERN"; then
  exit 0
fi

# 4. Destructive + docker exec + non-dev container = BLOCK
REASON=$(cat <<'EOF'
🛑 BLOCKED: destructive operation appears to target a non-dev container.

Allow-listed containers: dixlase-dev-*, dixlase-sandbox-*
Detected as production-class: anything else (dixlase-brand-*, dixlase-keys-*,
compose-php-*, etc.).

If this is intentional:
  - Re-run on a dev/sandbox container if you just want to verify the test.
  - For a true production maintenance, run on the host directly
    (outside Claude Code) so this hook does not fire.

Background: 2026-05-29 Brand MySQL DROP incident. See
.claude/plans/test-incident-followup.md (task J post-mortem) for the
full chain and why this hook exists.
EOF
)

jq -n --arg reason "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
exit 0
