#!/usr/bin/env bash
# Sync shared protocol files from NousResearch/hermes-agent → this fork.
#
# Watermark: UPSTREAM.md "Last synced upstream commit"
# After copy: keep web-trimmed index.ts; re-apply known web patches (remint +
# open event-name typing). apps/desktop UI sync stays manual.
set -euo pipefail

HERMES_AGENT_REPO="${HERMES_AGENT_REPO:-https://github.com/NousResearch/hermes-agent.git}"
GH_REPO="${GH_REPO:-${GITHUB_REPOSITORY:-nowjon/hermes-ui}}"
PROTOCOL_FILES=(
  json-rpc-channel.ts
  json-rpc-gateway.ts
  gateway-events.ts
  gateway-contract.generated.ts
  reconnect-backoff.ts
  websocket-url.ts
)

DATE="$(date -u +%Y%m%d)"
BRANCH="chore/sync-hermes-shared-${DATE}"
TITLE_PREFIX="chore: sync hermes-agent shared protocol"
ISSUE_TITLE_PREFIX="hermes-agent shared drift"

gh_repo() {
  gh --repo "$GH_REPO" "$@"
}

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

WATERMARK="$(
  grep -E '^\s*- \*\*Last synced upstream commit:\*\*' UPSTREAM.md \
    | head -1 \
    | grep -Eo '[0-9a-f]{7,40}' \
    | head -1 \
  || true
)"
if [[ -z "$WATERMARK" ]]; then
  echo "::error::Could not parse watermark from UPSTREAM.md"
  exit 1
fi
echo "Watermark: ${WATERMARK}"
echo "Target repo: ${GH_REPO}"

EXISTING_PR="$(gh_repo pr list --state open --json number,url,headRefName,title \
  --jq "[.[] | select((.headRefName | startswith(\"chore/sync-hermes-shared-\")) or (.title | startswith(\"${TITLE_PREFIX}\")))] | .[0] // empty")"
if [[ -n "$EXISTING_PR" && "$EXISTING_PR" != "null" ]]; then
  echo "Open hermes-agent shared sync PR already exists: ${EXISTING_PR}"
  exit 0
fi

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

# --- known web patches (also used for equivalence checks) -----------------
# Writes patched content to stdout given an upstream protocol file path + name.
apply_web_patches() {
  local src="$1"
  local name="$2"
  python3 - "$src" "$name" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1])
name = sys.argv[2]
text = src.read_text()

if name == "json-rpc-gateway.ts":
    early = (
        "    if ((this.socket && this.socket.readyState === WebSocket.OPEN) || this.state === 'connecting') {\n"
        "      return\n"
        "    }\n"
    )
    remint = (
        "    if (this.socket && this.socket.readyState === WebSocket.OPEN) {\n"
        "      return\n"
        "    }\n"
        "\n"
        "    // A stuck handshake leaves state==='connecting' forever for callers that\n"
        "    // early-return on that flag (hermesweb: navigate → dead ticket → refresh).\n"
        "    // Tear down any non-open socket so a reminted ticket can redial.\n"
        "    if (this.socket || this.state === 'connecting' || this.state === 'error') {\n"
        "      this.close()\n"
        "    }\n"
    )
    if early in text:
        text = text.replace(early, remint, 1)
    # Loosen GatewayEventHub / client on() typing for open string event names.
    typed_on = (
        "  on<K extends GatewayEventName>(type: K, handler: (event: GatewayEvent<K>) => void): () => void {"
    )
    loose_on = (
        "  on<P = unknown>(type: GatewayEventName, handler: (event: GatewayEvent & { payload?: P }) => void): () => void {"
    )
    text = text.replace(typed_on, loose_on)

elif name == "gateway-events.ts":
    text = text.replace(
        "export type GatewayEventName = keyof GatewayEventMap\n",
        "export type GatewayEventName = keyof GatewayEventMap | (string & {})\n",
    )
    text = text.replace(
        "  payload?: GatewayEventMap[K]\n",
        "  payload?: K extends keyof GatewayEventMap ? GatewayEventMap[K] : unknown\n",
    )

sys.stdout.write(text)
PY
}

strip_web_patches_equiv() {
  # Exit 0 if fork file equals upstream after accounting for known web patches
  # (i.e. apply_web_patches(upstream) == fork).
  local fork="$1"
  local upstream="$2"
  local name="$3"
  local patched="$WORKDIR/patched-${name}"
  apply_web_patches "$upstream" "$name" >"$patched"
  cmp -s "$fork" "$patched"
}

echo "Shallow-cloning ${HERMES_AGENT_REPO} ..."
git clone --filter=blob:none --sparse "$HERMES_AGENT_REPO" "$WORKDIR/hermes-agent"
(
  cd "$WORKDIR/hermes-agent"
  git sparse-checkout set apps/shared/src
  if ! git cat-file -t "$WATERMARK" >/dev/null 2>&1; then
    git fetch --deepen=800 origin || true
  fi
  if ! git cat-file -t "$WATERMARK" >/dev/null 2>&1; then
    git fetch --unshallow origin 2>/dev/null || git fetch origin "$WATERMARK" || true
  fi
  if ! git cat-file -t "$WATERMARK" >/dev/null 2>&1; then
    echo "::error::Watermark ${WATERMARK} not found in ${HERMES_AGENT_REPO}"
    exit 1
  fi
)

AGENT="$WORKDIR/hermes-agent"
HEAD="$(git -C "$AGENT" rev-parse HEAD)"
echo "hermes-agent HEAD: ${HEAD}"

DIFF_SUMMARY="$WORKDIR/diff-summary.md"
{
  echo "## Protocol file status"
  echo
  echo "| File | fork vs watermark+web-patches | fork vs HEAD+web-patches |"
  echo "|---|---|---|"
} >"$DIFF_SUMMARY"

LOCAL_DIVERGED=0
HEAD_DIFFERS=0

for f in "${PROTOCOL_FILES[@]}"; do
  FORK_PATH="shared/src/${f}"
  AGENT_PATH="apps/shared/src/${f}"
  WM_FILE="$WORKDIR/wm-${f}"
  HEAD_FILE="$WORKDIR/head-${f}"

  if [[ ! -f "$FORK_PATH" ]]; then
    echo "::warning::Missing fork file ${FORK_PATH}"
    LOCAL_DIVERGED=1
    echo "| \`${f}\` | missing in fork | — |" >>"$DIFF_SUMMARY"
    continue
  fi
  if ! git -C "$AGENT" cat-file -e "${WATERMARK}:${AGENT_PATH}" 2>/dev/null; then
    echo "::warning::Missing ${AGENT_PATH} at watermark ${WATERMARK}"
    LOCAL_DIVERGED=1
    echo "| \`${f}\` | missing at watermark | — |" >>"$DIFF_SUMMARY"
    continue
  fi

  git -C "$AGENT" show "${WATERMARK}:${AGENT_PATH}" >"$WM_FILE"
  git -C "$AGENT" show "HEAD:${AGENT_PATH}" >"$HEAD_FILE"

  VS_WM="identical"
  VS_HEAD="identical"

  if ! strip_web_patches_equiv "$FORK_PATH" "$WM_FILE" "$f"; then
    VS_WM="**diverged**"
    LOCAL_DIVERGED=1
  elif ! cmp -s "$FORK_PATH" "$WM_FILE"; then
    VS_WM="watermark + web patches"
  fi

  if ! strip_web_patches_equiv "$FORK_PATH" "$HEAD_FILE" "$f"; then
    VS_HEAD="**differs**"
    HEAD_DIFFERS=1
  elif ! cmp -s "$FORK_PATH" "$HEAD_FILE"; then
    VS_HEAD="identical (modulo web patches)"
  fi

  echo "| \`${f}\` | ${VS_WM} | ${VS_HEAD} |" >>"$DIFF_SUMMARY"
done

{
  echo
  echo "- Watermark: \`${WATERMARK}\`"
  echo "- hermes-agent HEAD: \`${HEAD}\`"
  echo "- Upstream: ${HERMES_AGENT_REPO}"
  echo
  echo "### Diff vs HEAD+web-patches (unexpected local deltas only)"
  echo '```'
  for f in "${PROTOCOL_FILES[@]}"; do
    FORK_PATH="shared/src/${f}"
    HEAD_FILE="$WORKDIR/head-${f}"
    [[ -f "$FORK_PATH" && -f "$HEAD_FILE" ]] || continue
    PATCHED="$WORKDIR/expected-${f}"
    apply_web_patches "$HEAD_FILE" "$f" >"$PATCHED"
    if ! cmp -s "$FORK_PATH" "$PATCHED"; then
      diff -u "$PATCHED" "$FORK_PATH" | head -80 || true
    fi
  done
  echo '```'
} >>"$DIFF_SUMMARY"

if [[ "$HEAD_DIFFERS" -eq 0 ]]; then
  echo "Fork protocol files already match hermes-agent HEAD (plus web patches) — nothing to do."
  exit 0
fi

if [[ "$LOCAL_DIVERGED" -eq 1 ]]; then
  EXISTING_ISSUE="$(gh_repo issue list --state open --search "${ISSUE_TITLE_PREFIX} in:title" \
    --json number,url --jq '.[0] // empty' 2>/dev/null || true)"
  if [[ -n "${EXISTING_ISSUE:-}" && "$EXISTING_ISSUE" != "null" ]]; then
    echo "Open drift issue already exists: ${EXISTING_ISSUE}"
    exit 0
  fi
  ISSUE_TITLE="${ISSUE_TITLE_PREFIX}: watermark ${WATERMARK:0:8} vs HEAD ${HEAD:0:8} (${DATE})"
  if ! {
    echo "Automated sync found **local divergence** from the UPSTREAM.md watermark"
    echo "(beyond known web patches: stuck-handshake remint + open event-name typing),"
    echo "so a mechanical copy was **not** applied."
    echo
    echo "**Full \`apps/desktop\` UI sync remains manual** (see UPSTREAM.md deferred list)."
    echo
    cat "$DIFF_SUMMARY"
  } | gh_repo issue create --title "$ISSUE_TITLE" --body-file -; then
    echo "::warning::Could not open issue (issues may be disabled). Diff summary:"
    cat "$DIFF_SUMMARY"
  fi
  exit 0
fi

echo "Safe to copy protocol files from hermes-agent HEAD + re-apply web patches."
git checkout -B "$BRANCH" origin/main

cp shared/src/index.ts "$WORKDIR/fork-index.ts"

for f in "${PROTOCOL_FILES[@]}"; do
  apply_web_patches "$WORKDIR/head-${f}" "$f" >"shared/src/${f}"
done

cp "$WORKDIR/fork-index.ts" shared/src/index.ts

export HEAD
python3 - <<'PY'
import os, pathlib, re, datetime
path = pathlib.Path("UPSTREAM.md")
text = path.read_text()
head = os.environ["HEAD"]
iso = datetime.date.today().isoformat()
text2, n = re.subn(
    r"(\*\*Last synced upstream commit:\*\* `)[0-9a-f]{7,40}(`)",
    rf"\g<1>{head}\2",
    text,
    count=1,
)
text2, _ = re.subn(
    r"(\*\*Last sync date:\*\* )[0-9]{4}-[0-9]{2}-[0-9]{2}",
    rf"\g<1>{iso}",
    text2,
    count=1,
)
marker = f"automated shared protocol sync from hermes-agent `{head[:8]}`"
if marker not in text2:
    entry = (
        f"\n\n### {iso} - {marker}\n\n"
        f"CI copied protocol files from [`NousResearch/hermes-agent`](https://github.com/NousResearch/hermes-agent) "
        f"`apps/shared` at `{head}` into `shared/src/`, kept web-trimmed `shared/src/index.ts`, "
        f"and re-applied web patches (stuck-handshake remint + open event-name typing).\n\n"
        f"**`apps/desktop` / `app/` UI sync remains manual** (see deferred list above).\n"
    )
    text2 = text2.rstrip() + entry
path.write_text(text2 if n else text)
print(f"watermark commit replaced: {bool(n)}")
PY

git add shared/src/ UPSTREAM.md
if git diff --cached --quiet; then
  echo "No staged changes after copy — exiting."
  exit 0
fi

SHORT_HEAD="${HEAD:0:8}"
git commit -m "chore: sync shared protocol from hermes-agent ${SHORT_HEAD}"
git push -u origin "$BRANCH"

BODY="$(cat <<EOF
## Summary
Automated sync of protocol files from [\`NousResearch/hermes-agent\`](${HERMES_AGENT_REPO}) \`apps/shared\`.

- Previous watermark: \`${WATERMARK}\`
- New watermark (HEAD): \`${HEAD}\`
- Copied into \`shared/src/\`: \`json-rpc-channel.ts\`, \`json-rpc-gateway.ts\`, \`gateway-events.ts\`, \`gateway-contract.generated.ts\`, \`reconnect-backoff.ts\`, \`websocket-url.ts\`
- Kept web-trimmed \`shared/src/index.ts\` (billing/desktop exports omitted)
- Re-applied web patches: stuck-handshake remint on \`connect()\`, open \`GatewayEventName\` typing

## Manual follow-up
**Full \`apps/desktop\` → \`app/\` UI sync remains manual** per the deferred list in \`UPSTREAM.md\` (tree layout, contrib/runtime-loader, billing, \`@assistant-ui\` bump, etc.). Review this PR for type/API breakage against local web-bridge code.

$(cat "$DIFF_SUMMARY")
EOF
)"

gh_repo pr create \
  --base main \
  --head "$BRANCH" \
  --title "${TITLE_PREFIX} ${SHORT_HEAD} (${DATE})" \
  --body "$BODY"
