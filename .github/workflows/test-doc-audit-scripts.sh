#!/usr/bin/env bash
# Local test for doc-audit workflow scripts. Uses mock env; no real API keys.
# Run from repo root: bash .github/workflows/test-doc-audit-scripts.sh
set -e
GITHUB_OUTPUT=$(mktemp 2>/dev/null || echo "$(pwd)/.github_output_test")
trap "rm -f $GITHUB_OUTPUT" EXIT
export GITHUB_OUTPUT

echo "=== 1. Cursor agent step (no API key) ==="
export CURSOR_API_KEY=""
export REPO_URL="https://github.com/owner/repo"
bash -c '
  if [ -z "${CURSOR_API_KEY}" ]; then
    echo "No CURSOR_API_KEY — skipping Cursor check, allowing launch."
    echo "cursor_agent_running=false" >> "$GITHUB_OUTPUT"
    exit 0
  fi
  resp_file=$(mktemp)
  code=$(curl -s -w "%{http_code}" -o "$resp_file" -u "${CURSOR_API_KEY}:" "https://api.cursor.com/v0/agents?limit=50")
  if [ "$code" != "200" ]; then
    echo "Cursor API returned $code — allowing launch (no double-check)."
    echo "cursor_agent_running=false" >> "$GITHUB_OUTPUT"
    rm -f "$resp_file"
    exit 0
  fi
  running=$(jq -c --arg repo "$REPO_URL" "[.agents[]? | select(.status == \"RUNNING\" and ((.source.repository // \"\") == \$repo))] | length" "$resp_file" 2>/dev/null || echo "0")
  rm -f "$resp_file"
  if [ "${running:-0}" -gt 0 ] 2>/dev/null; then
    echo "cursor_agent_running=true" >> "$GITHUB_OUTPUT"
  else
    echo "cursor_agent_running=false" >> "$GITHUB_OUTPUT"
  fi
'
export GITHUB_OUTPUT
echo "Outputs: $(cat "$GITHUB_OUTPUT")"
> "$GITHUB_OUTPUT"

echo ""
echo "=== 2. Cursor agent step (fake key → curl 401) ==="
export CURSOR_API_KEY="fake_key_for_test"
export REPO_URL="https://github.com/owner/repo"
export GITHUB_OUTPUT
bash -c '
  if [ -z "${CURSOR_API_KEY}" ]; then
    echo "cursor_agent_running=false" >> "$GITHUB_OUTPUT"
    exit 0
  fi
  resp_file=$(mktemp)
  code=$(curl -s -w "%{http_code}" -o "$resp_file" -u "${CURSOR_API_KEY}:" "https://api.cursor.com/v0/agents?limit=50")
  if [ "$code" != "200" ]; then
    echo "Cursor API returned $code — allowing launch (no double-check)."
    echo "cursor_agent_running=false" >> "$GITHUB_OUTPUT"
    rm -f "$resp_file"
    exit 0
  fi
  running=$(jq -c --arg repo "$REPO_URL" "[.agents[]? | select(.status == \"RUNNING\" and ((.source.repository // \"\") == \$repo))] | length" "$resp_file" 2>/dev/null || echo "0")
  rm -f "$resp_file"
  if [ "${running:-0}" -gt 0 ] 2>/dev/null; then
    echo "cursor_agent_running=true" >> "$GITHUB_OUTPUT"
  else
    echo "cursor_agent_running=false" >> "$GITHUB_OUTPUT"
  fi
'
echo "Outputs: $(cat "$GITHUB_OUTPUT")"
> "$GITHUB_OUTPUT"

echo ""
echo "=== 3. Check doc-relevant changes (git log) ==="
CHANGED=$(git log origin/main --since="24 hours ago" --name-only --pretty=format: 2>/dev/null | grep -E '^(StructuralSizer/src/|StructuralSynthesizer/src/|docs/)' | sort -u || true)
if [ -z "$CHANGED" ]; then
  echo "has_changes=false"
else
  echo "has_changes=true (sample): $(echo "$CHANGED" | head -3)"
fi

echo ""
echo "=== 4. Launch step: build JSON payload (no curl) ==="
PROMPT=$(cat scripts/prompts/doc-audit.md)
REPO_URL="https://github.com/owner/repo"
BRANCH="cursor/doc-audit-$(date +%Y-%m-%d)"
payload=$(jq -n \
  --arg prompt "$PROMPT" \
  --arg repo "$REPO_URL" \
  --arg branch "$BRANCH" \
  '{
    prompt: { text: $prompt },
    model: "gpt-5.2",
    source: { repository: $repo, ref: "main" },
    target: { autoCreatePr: true, branchName: $branch }
  }')
echo "Payload built OK (length $(echo "$payload" | wc -c) chars)"

echo ""
echo "All script snippets completed without errors."
