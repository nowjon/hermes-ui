# Upstream sync (hermes-agent)

This fork’s real protocol upstream is [`NousResearch/hermes-agent`](https://github.com/NousResearch/hermes-agent) (`apps/shared` + `apps/desktop`). The GitHub parent `przbadu/hermes-ui` is **not** actively tracked for updates.

Workflow: [`.github/workflows/sync-upstream.yml`](.github/workflows/sync-upstream.yml) — weekly (Mondays 14:00 UTC) + `workflow_dispatch`.

## What it does

1. Shallow-clones `https://github.com/NousResearch/hermes-agent`
2. Reads the watermark from [`UPSTREAM.md`](UPSTREAM.md) (**Last synced upstream commit**, currently `653bc4f2…`)
3. Compares protocol files `apps/shared/src` → `shared/src`:
   - `json-rpc-channel.ts`
   - `json-rpc-gateway.ts`
   - `gateway-events.ts`
   - `gateway-contract.generated.ts`
   - `reconnect-backoff.ts`
   - `websocket-url.ts`
4. If HEAD differs and the fork still matches watermark **plus known web patches**:
   - Copies HEAD versions into `shared/src/`
   - Keeps web-trimmed `shared/src/index.ts` (no billing/desktop barrel exports)
   - Re-applies web patches:
     - stuck-handshake remint on `connect()` (when upstream still early-returns on `connecting`)
     - open `GatewayEventName` / loose `on()` typing used by hermesweb
   - Bumps the watermark in `UPSTREAM.md`
   - Opens PR `chore/sync-hermes-shared-YYYYMMDD` (idempotent — no duplicate open PRs)
5. If the fork has unexpected local edits → opens an **issue** (watermark vs HEAD + diff) instead of auto-copying

**`apps/desktop` → `app/` UI sync stays manual** (see deferred list in UPSTREAM.md). The PR body always calls that out.

## Manual trigger

```bash
gh workflow run sync-upstream.yml --repo nowjon/hermes-ui
```

Or: GitHub → Actions → “Sync hermes-agent shared” → Run workflow.

Permissions: `contents: write`, `pull-requests: write`, `issues: write`.

## Repo settings required

GitHub → Settings → Actions → General → Workflow permissions:

- **Read and write permissions**
- **Allow GitHub Actions to create and approve pull requests** (required for \`gh pr create\`)

Without the second checkbox, the job can push a sync branch but fails at PR creation.
