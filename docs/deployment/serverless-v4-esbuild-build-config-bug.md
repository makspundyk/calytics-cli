# Serverless Framework v4 esbuild Build Config Bug — Full Investigation

## The Symptom

When running `serverless offline` locally for `calytics-be`, the banking orchestrator lambda crashes at runtime with:

```
Error [ERR_MODULE_NOT_FOUND]: Cannot find package '@infrastructure/dispute-recognition' imported from
/home/unknown/projects/calytics/calytics-be/src/domains/banking/services/banking_orchestrator_service.ts

    at Object.getPackageJSONURL (node:internal/modules/package_json_reader:268:9)
    at packageResolve (node:internal/modules/esm/resolve:768:81)
    at moduleResolve (node:internal/modules/esm/resolve:854:18)
    at defaultResolve (node:internal/modules/esm/resolve:984:11)
```

The error does NOT appear on sandbox or production deployments.

---

## The Failing Code

File: `src/domains/banking/services/banking_orchestrator_service.ts` (line ~891)

```typescript
private async getPaymentReconciliationPort(): Promise<IPaymentReconciliationPort> {
    if (!this.paymentReconciliationPort) {
        const { CalyticsPaymentReconciliationAdapter } = await import(
            "@infrastructure/dispute-recognition/adapters/CalyticsPaymentReconciliationAdapter"
        );
        this.paymentReconciliationPort = CalyticsPaymentReconciliationAdapter.getInstance();
    }
    return this.paymentReconciliationPort;
}
```

`@infrastructure/*` is a **tsconfig path alias** defined in `tsconfig.json`:

```json
"paths": {
    "@domains/banking/*": ["src/domains/banking/*"],
    "@infrastructure/*": ["src/infrastructure/*"],
    "@domains/*": ["src/domains/*"],
    "@core/*": ["src/core/*"],
    "@shared/*": ["src/shared/*"],
    "@src/*": ["src/*"],
    ...
}
```

This is NOT an npm package. It's a compile-time alias that maps `@infrastructure/*` to `src/infrastructure/*`. esbuild (the bundler) must resolve these aliases during bundling. If it doesn't, Node.js treats `@infrastructure/dispute-recognition` as an npm package name and fails because no such package exists.

---

## Why It Works on Production/Sandbox

Production and sandbox are deployed via **Terraform**, NOT via the Serverless Framework. The Terraform build script (`terraform/build-terraform-lambdas.sh`) uses `tsup` directly:

```bash
npx tsup src/domains/banking/lambdas/banking_orchestrator_layer2.ts \
  --format cjs \
  --target node22 \
  --minify \
  --keep-names \
  --out-dir dist/terraform-lambdas/banking-orchestrator-layer2 \
  --treeshake \
  --external jsonwebtoken
```

Key facts about the Terraform/production build:
- **Format is CJS** (`--format cjs`), not ESM
- `tsup` reads `tsconfig.json` automatically and resolves ALL path aliases
- Dynamic `import()` expressions are converted to synchronous `require()` and **fully inlined** into the bundle
- The SDK packages (`@calytics-sdk/*`, `@calytics/*`) are installed in `node_modules/` inside the Lambda zip alongside the bundled JS

You can verify this by downloading the deployed Lambda:
```bash
aws lambda get-function --function-name calytics-be-sandbox-banking-orchestrator --region eu-central-1 \
  --query 'Code.Location' | xargs curl -o /tmp/lambda.zip
unzip -p /tmp/lambda.zip banking_orchestrator_layer2.js | grep "reconcili"
```

The output shows `require('@calytics-sdk/payment-reconciliation')` at the top level — the dynamic import was completely compiled away and the adapter code was inlined.

---

## Root Cause: serverless.yml `build:` Config Structure Is Wrong

### The Broken Config (what was in serverless.yml)

```yaml
build:
    esbuild: true          # <-- This is a BOOLEAN
    minify: true
    sourcemap: true
    target: node22
    platform: node
    format: esm
    keepNames: true
    sourcesContent: false
    tsconfig: tsconfig.json
    external: ["jsonwebtoken"]
    concurrency: 10
```

### How SLS v4 Parses This

The Serverless Framework v4 esbuild integration lives in the compiled binary at:
`~/.serverless/releases/4.33.2/package/dist/sf-core.js`

The `_buildProperties()` method does this:

```javascript
async _buildProperties() {
    let defaultConfig = { bundle: true, minify: false, sourcemap: true };

    // Auto-detect ESM from package.json "type": "module"
    if ((await this._readPackageJson()).type === "module") {
        defaultConfig.format = "esm";
    }

    if (this.serverless.service.build &&
        this.serverless.service.build !== "esbuild" &&
        this.serverless.service.build.esbuild) {

        let jsConfig = {};
        // ... configFile handling ...

        let mergedOptions = lodash.merge(defaultConfig, jsConfig, this.serverless.service.build.esbuild);
        //                                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
        //                                                         THIS IS THE BOOLEAN `true`, NOT an object
        return mergedOptions;
    }
    return defaultConfig;
}
```

With the YAML structure `esbuild: true`, the JS object is:
```javascript
this.serverless.service.build = {
    esbuild: true,        // boolean
    minify: true,         // sibling property — NEVER read by the esbuild builder
    tsconfig: "tsconfig.json",  // sibling — NEVER read
    external: ["jsonwebtoken"], // sibling — NEVER read
    // ... all other options — NEVER read
}
```

`this.serverless.service.build.esbuild` is the boolean `true`.

Then `lodash.merge(defaultConfig, {}, true)` is called. Lodash converts primitive sources to objects: `Object(true)` = `Boolean{true}` which has **zero own enumerable properties**. Nothing is merged.

**Proof:**
```javascript
const _ = require('lodash');
let defaultConfig = { bundle: true, minify: false, sourcemap: true, format: 'esm' };
let result = _.merge(defaultConfig, {}, true);
console.log(result);
// => { bundle: true, minify: false, sourcemap: true, format: 'esm' }
// No tsconfig, no external, no target, no keepNames — ALL USER OPTIONS LOST
```

### What esbuild Actually Received

| Option | Expected | Actually Received |
|--------|----------|-------------------|
| `bundle` | `true` | `true` (from default) |
| `format` | `esm` | `esm` (auto-detected from package.json `"type": "module"`) |
| `sourcemap` | `true` | `true` (from default) |
| `minify` | `true` | `false` (default, user value lost) |
| `target` | `node22` | *missing* |
| `keepNames` | `true` | *missing* |
| `tsconfig` | `tsconfig.json` | *missing* (esbuild auto-discovers, but less reliable) |
| `external` | `["jsonwebtoken"]` | *missing* (only `@aws-sdk/*` from auto-detection for node22) |
| `platform` | `node` | `node` (overwritten by SLS v4 in `_build()`) |

### The Cascade of Failures

1. **`external` is lost** — `@calytics/*` and `@calytics-sdk/*` packages are NOT externalized. esbuild tries to bundle them.
2. **`@calytics/payment-reconciliation`** is defined as `"file:../calytics-payment-reconciliation"` in package.json. If the linked package isn't installed or has its own unresolvable deps, the build fails.
3. **Build failure in `_build()` catch block:**
   ```javascript
   } catch (err2) {
       if (this.serverless.devmodeEnabled === true) return; // swallowed in dev mode
       throw new serverless_error_default(err2.message, "ESBULD_BUILD_ERROR");
   }
   ```
4. If NOT in dev mode, the error propagates and `serverless offline` fails at build time. If somehow the build partially succeeds or serverless-offline has a fallback, it runs the **raw TypeScript source** where Node.js cannot resolve the `@infrastructure/*` tsconfig path alias at runtime.

### Why Static Imports Don't Fail But Dynamic Imports Do

Even with a broken config, esbuild **auto-discovers `tsconfig.json`** from the entry point's directory. This resolves path aliases for **static imports** (which are processed at bundle time). However:

- If the build fails entirely (due to missing `@calytics/*` externals), no bundled output is produced
- serverless-offline may fall back to executing source files directly
- Static imports in source files also use path aliases, but they may be handled by a different mechanism (SLS v4 or serverless-offline's own TypeScript loader)
- The **dynamic `import()`** is evaluated at **runtime**, where no bundler or tsconfig-paths resolver is active — so Node.js sees `@infrastructure/dispute-recognition` and tries to find an npm package with that name

---

## The Fix

### Correct serverless.yml Config Structure

Options must be nested **under `esbuild:` as an object**, not alongside `esbuild: true`:

```yaml
build:
    esbuild:
        minify: true
        sourcemap: true
        target: node22
        platform: node
        format: esm
        keepNames: true
        sourcesContent: false
        tsconfig: tsconfig.json
        external:
            - jsonwebtoken
            - "@calytics/*"
            - "@calytics-sdk/*"
        buildConcurrency: 10
```

Changes:
1. **`esbuild:` is now an object** (not boolean `true`) — `lodash.merge` correctly merges all properties
2. **Added `@calytics/*` and `@calytics-sdk/*` to external** — these SDK packages live in `node_modules` and must not be bundled (they have native/complex deps)
3. **Renamed `concurrency` to `buildConcurrency`** — SLS v4 code does `delete esbuildProps.buildConcurrency` before passing to esbuild (it's a plugin-level option controlling parallel builds). The name `concurrency` is not recognized and would be passed to esbuild as an invalid option.

### Verification

After the fix, run esbuild with the same options SLS v4 would use:

```bash
npx esbuild src/domains/banking/lambdas/banking_orchestrator_layer2.ts \
  --bundle --format=esm --platform=node --target=node22 \
  --minify --keep-names --sourcemap \
  --tsconfig=tsconfig.json \
  --external:jsonwebtoken \
  --external:'@calytics/*' \
  --external:'@calytics-sdk/*' \
  --external:'@aws-sdk/*' \
  --outfile=/tmp/test-bundle.mjs
```

Then verify no unresolved path aliases remain:
```bash
grep "@infrastructure" /tmp/test-bundle.mjs
# Should return nothing — all aliases resolved

grep "CalyticsPaymentReconciliationAdapter" /tmp/test-bundle.mjs
# Should show the adapter code inlined in the bundle
```

---

## Architecture Context: Two Separate Build Pipelines

```
                    calytics-be
                        |
            +-----------+-----------+
            |                       |
    LOCAL DEVELOPMENT         CLOUD DEPLOYMENT
    (Serverless Framework)    (Terraform)
            |                       |
    serverless.yml            terraform/build-terraform-lambdas.sh
    build.esbuild: {...}      npx tsup ... --format cjs
            |                       |
    SLS v4 internal esbuild   tsup (wraps esbuild)
    format: esm               format: cjs
    output: .serverless/      output: dist/terraform-lambdas/
            build/                    *.zip → S3 → Lambda
            |
    serverless-offline
    runs bundled code locally
```

The Terraform build uses `tsup --format cjs` which converts dynamic `import()` to `require()` and inlines everything. The SLS v4 build uses esbuild with `format: esm` which preserves dynamic `import()` but should still resolve and inline it when `bundle: true` and path aliases are configured.

---

## Key Files Reference

| File | Role |
|------|------|
| `serverless.yml` (lines 110-124) | SLS v4 build config — **this was the broken file** |
| `tsconfig.json` (lines 14-22) | Defines `@infrastructure/*`, `@domains/*`, etc. path aliases |
| `src/domains/banking/services/banking_orchestrator_service.ts` (~line 891) | The dynamic `import()` that fails |
| `src/infrastructure/dispute-recognition/adapters/CalyticsPaymentReconciliationAdapter.ts` | The target of the dynamic import |
| `terraform/build-terraform-lambdas.sh` (lines 96-157) | Production build — uses tsup, works correctly |
| `~/.serverless/releases/4.33.2/package/dist/sf-core.js` | SLS v4 compiled binary — contains `_buildProperties()` logic |
| `package.json` | Has `"type": "module"` (triggers ESM format auto-detection) |

---

## How to Debug Similar Issues in the Future

1. **Check what esbuild actually receives** — SLS v4 silently drops options if the YAML structure is wrong. Add `logLevel: "debug"` to the esbuild config or run esbuild manually with the same flags.

2. **Inspect the bundled output** — Check `.serverless/build/` for the actual bundled JS. Search for unresolved path aliases: `grep "@infrastructure\|@domains\|@shared" .serverless/build/**/*.js`

3. **Compare local vs deployed bundles** — Download the deployed Lambda zip and diff the import resolution.

4. **Test esbuild directly** — Strip the SLS v4 layer and run `npx esbuild` with the intended options to isolate whether the issue is esbuild itself or the config plumbing.

5. **Read the SLS v4 source** — The build logic is in `~/.serverless/releases/<version>/package/dist/sf-core.js`. Search for `_buildProperties`, `_build`, `_externals` to understand the option flow.

---

## Additional Finding: Shared Modules `file:` Links (April 2026)

### The Second Failure Mode

Even after fixing the `build:` YAML structure, the dynamic `import()` still fails locally with:

```
Error [ERR_MODULE_NOT_FOUND]: Cannot find module
'/home/unknown/projects/calytics/calytics-be/node_modules/@calytics/ais-connection/dist/index.js'
```

This is a separate issue from the esbuild config bug.

### Root Cause: `file:` Links vs Registry Packages

`package.json` has two kinds of shared dependencies:

```json
{
    "@calytics-sdk/ais-connection": "^1.0.28",          // GitLab npm registry (pre-built)
    "@calytics-sdk/dispute-recognition": "^1.0.35",     // GitLab npm registry (pre-built)
    "@calytics-sdk/payment-reconciliation": "^1.0.30",  // GitLab npm registry (pre-built)
    "@calytics/ais-connection": "file:../calytics-ais-connection",           // LOCAL symlink
    "@calytics/payment-reconciliation": "file:../calytics-payment-reconciliation"  // LOCAL symlink
}
```

The `.npmrc` configures BOTH `@calytics-sdk` and `@calytics` scopes to use the GitLab Package Registry:

```ini
@calytics-sdk:registry=https://gitlab.com/api/v4/projects/80031530/packages/npm/
@calytics:registry=https://gitlab.com/api/v4/projects/80031530/packages/npm/
```

**In CI/CD**: `npm install` fetches `@calytics/*` from the GitLab registry — these are **pre-built** packages with `dist/` included.

**Locally**: The `file:` link in `package.json` takes precedence over the registry. `npm install` creates a symlink:

```
node_modules/@calytics/ais-connection -> ../../../calytics-shared-modules/calytics-ais-connection
```

The symlink points to the **raw TypeScript source** — no `dist/` directory. When the dynamic `import()` resolves at runtime, Node looks for `dist/index.js` (as declared in the module's `package.json` `"main"` field) and fails.

### Why Static Imports Work But Dynamic Imports Fail (Revisited)

The SLS v4 native esbuild build (when configured correctly) resolves path aliases and bundles static imports at build time. The `@infrastructure/*` alias is resolved by esbuild reading `tsconfig.json`.

However, SLS v4 in dev mode (`serverless offline`) runs **source TypeScript directly** without fully bundling. Dynamic `import()` expressions are evaluated at runtime by Node's ESM loader, which:

1. Resolves `@infrastructure/dispute-recognition/adapters/CalyticsPaymentReconciliationAdapter`
2. esbuild resolves this at bundle time for static imports, but the dynamic `import()` hits Node's resolver
3. Node follows the `@infrastructure` → `src/infrastructure` path (via esbuild bundle for the containing file)
4. The adapter code imports from `@calytics/ais-connection`
5. Node resolves this to the symlink → `calytics-shared-modules/calytics-ais-connection/`
6. Reads its `package.json`: `"main": "dist/index.js"`
7. **Fails**: `dist/` doesn't exist because the local source was never compiled

### The Fix: Build Shared Modules Locally

The shared modules need to be compiled before running `serverless offline`. Each module uses `tsc && tsc-alias`:

```bash
# Build all shared modules that have a build script and are missing dist/
for mod_dir in calytics-shared-modules/*/; do
    [ ! -f "$mod_dir/package.json" ] && continue
    grep -q '"build"' "$mod_dir/package.json" || continue
    [ -d "$mod_dir/dist" ] && continue
    echo "Building $(basename "$mod_dir")..."
    (cd "$mod_dir" && npm install && npm run build)
done
```

This is automated in `local-deploy.sh` (Phase 3.5) — it auto-discovers all modules in `calytics-shared-modules/`, checks for a `build` script in their `package.json`, and builds any that are missing `dist/`.

### Shared Modules Status

| Module | Build script | Required by | Notes |
|--------|-------------|-------------|-------|
| `calytics-ais-connection` | `tsc && tsc-alias` | calytics-be, calytics-a2a | Must build locally |
| `calorics-payment-reconciliation` | `tsc && tsc-alias` | calytics-be, calytics-a2a | Must build locally |
| `calytics-dispute-recognition` | `tsc && tsc-alias` | calytics-be | Has pre-existing TS errors, builds with warnings |
| `calytics-sdk-orchestartor` | workspaces build | Publishes `@calytics-sdk/*` | Not needed locally (npm packages used instead) |
| `calytics-authorization` | none | — | No build needed |

### No Code Changes Required

This fix requires **zero changes** to `calytics-be` or any other service code. The original dynamic `import()` with `@infrastructure/*` alias works correctly because:

- **Production/Sandbox**: Terraform build uses `tsup --format cjs` which inlines everything
- **Local (SLS v4 native esbuild)**: esbuild resolves `@infrastructure/*` alias for static imports; the dynamic `import()` resolves at runtime → loads the adapter → adapter imports `@calytics/ais-connection` → follows symlink → finds `dist/index.js` (now exists because we built it)

### Key Files Reference (Updated)

| File | Role |
|------|------|
| `serverless.yml` (build section) | SLS v4 native esbuild config — must be object, not boolean |
| `package.json` (dependencies) | `file:` links for `@calytics/*` shared modules |
| `.npmrc` | Registry config — CI uses GitLab registry for pre-built packages |
| `calytics-shared-modules/*/package.json` | Each has `"main": "dist/index.js"` — needs `npm run build` |
| `local-deploy.sh` (Phase 3.5) | Auto-builds all shared modules missing `dist/` |
| `tsconfig.json` | Path aliases — resolved by esbuild at build time |

### Summary: Two Bugs, Two Fixes

| Bug | Symptom | Fix |
|-----|---------|-----|
| `build.esbuild: true` (boolean) | All esbuild options silently lost, path aliases unresolved | Change to `build.esbuild:` (object) with options nested inside |
| Shared modules not built locally | `Cannot find module .../dist/index.js` | Build shared modules before running `serverless offline` (automated in `local-deploy.sh`) |

---
---

# Chapter 2: The pino Symbol Duplication Bug — Serverless-Offline CJS Module Cache Invalidation

## Investigation Timeline (April 2026)

This chapter documents the third (and most insidious) bug in the local development pipeline. After fixing both the esbuild YAML config and the missing shared module builds, a new runtime error appeared when hitting the `POST /debit-guard/v1` endpoint:

```
TypeError: instance[setLevelSym] is not a function
    at pino (/home/unknown/projects/calytics/calytics-be/node_modules/pino/pino.js:207:24)
    at ../../../calytics-payment-reconciliation/dist/shared/utils/pino_logger.js
      (/home/unknown/projects/calytics/calytics-be/node_modules/@calytics-sdk/payment-reconciliation/dist/shared-module.js:356:37)
```

This error did **not** appear on production, sandbox, or even in standalone Node.js tests. It appeared **only** inside the Serverless Framework v4 (SLS v4) serverless-offline Lambda emulator.

---

## Step 1: Reproducing the Error

### What we tested

```bash
curl --location 'http://localhost:3333/debit-guard/v1' \
  --header 'x-api-key: ak_sand_21c0f785e49e88d7c7d5b6a8f19a2402bbb190e2198a6158a7aa30331aa0e2b2' \
  --header 'Content-Type: application/json' \
  --data-raw '{"iban":"DE70569831236423996860","full_name":"Jon Jons","tenant_id":"1454532323",...}'
```

### What the logs showed

The request authenticated successfully, created an idempotency lock, published the "Received" EventBridge event — then crashed during `BankingOrchestratorService.getPaymentReconciliationPort()` (line 891), which does:

```typescript
const { CalyticsPaymentReconciliationAdapter } = await import(
    "@infrastructure/dispute-recognition/adapters/CalyticsPaymentReconciliationAdapter"
);
```

### Why the first attempt at x-api-key didn't work

The initial curl had no `x-api-key` header. The endpoint returned 401. The correct API key was found in `scripts/seed-api-keys.sh` — the seed script creates API keys in LocalStack's API Gateway during Phase 3 of `local-deploy.sh`. The DebitGuard key is:

```
ak_sand_21c0f785e49e88d7c7d5b6a8f19a2402bbb190e2198a6158a7aa30331aa0e2b2
```

---

## Step 2: The Alias Shim Approach (First Attempt)

### Why shims are needed

SLS v4's native esbuild integration does **not** bundle code in dev mode (`serverless offline`). It runs TypeScript source files directly using a custom TypeScript loader. Static imports are resolved by this loader (which reads `tsconfig.json`), but **dynamic `import()` expressions hit Node's native ESM resolver** — which knows nothing about tsconfig path aliases.

So `import("@infrastructure/dispute-recognition/adapters/CalyticsPaymentReconciliationAdapter")` fails because Node.js tries to find an npm package called `@infrastructure/dispute-recognition`, which doesn't exist.

**Evidence:** Removing all shims produces:
```
Error [ERR_MODULE_NOT_FOUND]: Cannot find package '@infrastructure/dispute-recognition'
imported from /home/unknown/projects/calytics/calytics-be/src/domains/banking/services/banking_orchestrator_service.ts
```

Note the `.ts` source path — confirming SLS v4 runs source directly, not bundled output.

### The shim concept

Create fake packages in `node_modules/@infrastructure/`, `@core/`, `@shared/`, `@domains/` — each containing pre-bundled ESM JavaScript built by esbuild from the corresponding `src/` directories. When Node's ESM resolver encounters `import("@infrastructure/...")`, it finds the shim package in `node_modules/` and loads it.

### First shim problem: pino bundled as CJS inside ESM

The original shim script (`build-local-alias-shims.sh`) had individual `--external` flags:

```bash
--external:'@calytics/*' --external:'@calytics-sdk/*' --external:'@aws-sdk/*'
--external:jsonwebtoken --external:pino --external:crypto
```

But `pino-lambda` and `pino-std-serializers` were NOT listed. These are separate npm packages that start with "pino" but don't match `--external:pino`. They were bundled into the ESM shim, pulling in pino's CJS code:

```
Error: Dynamic require of "node:os" is not supported
    at chunk-HJQKDE4V.js:11:9
```

esbuild wraps CJS `require('node:os')` in a `__require()` shim that throws in ESM context.

**Fix:** Replace individual externals with `--packages=external` — externalizes ALL node_modules packages, not just the ones we list:

```bash
npx esbuild $ts_files --bundle --format=esm --packages=external ...
```

**Result:** @infrastructure shim went from 6 files (partial build, errors swallowed) to 78 files (complete build). Zero pino references, zero `__require` shims.

### Second shim problem: Node.js scoped package resolution

After fixing the externals, a new error:

```
Cannot find module '.../node_modules/@infrastructure/dispute-recognition/adapters/CalyticsPaymentReconciliationAdapter'
Did you mean to import "...CalyticsPaymentReconciliationAdapter.js"?
```

Node.js treats `@infrastructure/dispute-recognition` as a **scoped package name** (`@scope/name`), not as `@infrastructure` package + `dispute-recognition` subpath. It looks for `node_modules/@infrastructure/dispute-recognition/package.json` — which didn't exist.

**Fix:** Generate a `package.json` with wildcard exports in each first-level subdirectory:

```json
{
  "name": "@infrastructure/dispute-recognition",
  "type": "module",
  "exports": { ".": "./index.js", "./*": "./*.js" }
}
```

The `"./*": "./*.js"` pattern maps extensionless imports to `.js` files, e.g., `./adapters/CalyticsPaymentReconciliationAdapter` → `./adapters/CalyticsPaymentReconciliationAdapter.js`.

### Third shim problem: Cross-alias pino re-initialization

With both fixes applied, the module resolved correctly. But pino STILL crashed — this time with `instance[setLevelSym] is not a function`.

**Why:** The `@infrastructure` shim was bundling its own copy of `@shared/utils/pino_logger.ts` (because esbuild resolved the `@shared/*` tsconfig alias and inlined the code). This created a separate pino initialization inside the shim's ESM context.

**Fix attempt:** Build shims in dependency order (`@shared` first, then `@core`, then `@infrastructure`) and use filtered tsconfig files so each shim only resolves its OWN alias:

```bash
# When building @infrastructure, only map @infrastructure/* in tsconfig
# Other aliases (@shared/*, @core/*) are left as bare imports → externalized
cat > "$shim_tsconfig" << EOF
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "paths": { "@infrastructure/*": ["src/infrastructure/*"] }
  }
}
EOF
```

**Result:** `@infrastructure` shim no longer contained pino code. Imports of `@shared/utils/pino_logger` became external references to the `@shared` shim.

But pino STILL crashed.

---

## Step 3: Tracing the Real pino Crash

### Eliminated cause: it wasn't the transport + destination combination

The first hypothesis was that pino crashes when given both `transport: { target: 'pino-pretty' }` and a `pinoLambdaDestination()` simultaneously. Testing outside SLS v4:

```javascript
IS_OFFLINE=true node -e "
const pino = require('pino');
const { pinoLambdaDestination } = require('pino-lambda');
const dest = pinoLambdaDestination();
const logger = pino({ level: 'info', transport: { target: 'pino-pretty' } }, dest);
"
// Error: unable to determine transport target for "pino-pretty"
// (Different error — NOT setLevelSym)
```

And loading the SDK package directly:

```javascript
IS_OFFLINE=true node --input-type=module -e "
const pkg = await import('@calytics-sdk/payment-reconciliation');
console.log('SDK loaded OK');
"
// Output: SDK loaded OK (no crash!)
```

**Conclusion:** The pino crash is **specific to the SLS v4 serverless-offline runtime**. It does not reproduce in standalone Node.js.

### The diagnostic patch

We patched `node_modules/pino/pino.js` to log Symbol state before the crash:

```javascript
// Before: instance[setLevelSym](level)
// After:
if (typeof instance[setLevelSym] !== 'function') {
    const p2 = Object.getPrototypeOf(Object.getPrototypeOf(instance));
    const p2syms = p2 ? Object.getOwnPropertySymbols(p2) : [];
    console.error('[PINO-DIAG2] setLevelSym id:', setLevelSym.toString());
    console.error('[PINO-DIAG2] p2 has setLevel?', p2syms.some(s => s.toString() === setLevelSym.toString()));
    console.error('[PINO-DIAG2] p2 setLevel identical?', p2syms.some(s => s === setLevelSym));
}
instance[setLevelSym](level)
```

### The smoking gun

```
[PINO-DIAG2] setLevelSym id: Symbol(pino.setLevel)
[PINO-DIAG2] p2 has setLevel? true         ← A Symbol with the SAME description exists
[PINO-DIAG2] p2 setLevel identical? false   ← But it's a DIFFERENT Symbol instance!
[PINO-DIAG2] proto module: /home/.../node_modules/pino/lib/proto.js
[PINO-DIAG2] symbols module: /home/.../node_modules/pino/lib/symbols.js
```

The prototype chain has a `Symbol('pino.setLevel')` — same description string — but it's a **different Symbol object**. In JavaScript:

```javascript
Symbol('pino.setLevel') === Symbol('pino.setLevel')  // false — always unique!
Symbol.for('pino.setLevel') === Symbol.for('pino.setLevel')  // true — global registry
```

Pino uses `Symbol()` (not `Symbol.for()`), creating unique symbols per module load. If `pino/lib/symbols.js` is loaded **twice** into two different module instances, the Symbol values diverge. The pino function in `pino.js` imports `setLevelSym` from symbols.js (first load), but `proto.js` has already been loaded with a different `setLevelSym` (second load).

### Root cause: serverless-offline invalidates CJS module cache

**Both module paths resolve to the same file** — there's only one pino installation in `node_modules/`. But the Symbols are different instances, proving `symbols.js` was loaded twice.

Node.js CJS modules are cached in `Module._cache` by resolved filename. If the cache is cleared between loads, the module is re-executed, creating new `Symbol()` values.

**serverless-offline's Lambda emulator invalidates Node's `require.cache` between invocations** to simulate Lambda cold starts. When the handler function makes a dynamic `import()` that triggers a CJS `require('pino')` through the SDK module, pino's symbols.js is loaded into a fresh cache — producing new Symbols that don't match the ones created during the initial pino load (at process startup).

This is why:
- **Production works:** tsup bundles everything into a single CJS file. Symbols are created once.
- **Standalone Node.js works:** No cache invalidation. Symbols are created once.
- **SLS v4 serverless-offline fails:** Cache invalidated between invocations. Symbols created multiple times.

---

## Step 4: The Solution — Alias Shims + pino Symbol.for() Patch

### Why NOT tsup pre-build (the approach we tried first)

We initially solved the problem by pre-building all handlers with `tsup --format cjs` — identical to the Terraform production build. This worked perfectly (HTTP 202) but had two fatal DX problems:

1. **No hot reload.** Every code change required a full `tsup` rebuild. SLS v4's key dev benefit — running TypeScript source directly with instant reload — was lost.
2. **Extra command.** Team members would need to run `bash scripts/build-local-lambdas.sh` before `npm run offline:local`, or the handlers wouldn't be found.

These are unacceptable tradeoffs for a local development environment.

### The actual fix: two complementary patches

#### Patch 1: Alias shims (for dynamic import resolution)

SLS v4 runs TypeScript source directly. Static imports are resolved by its TypeScript loader. But dynamic `import("@infrastructure/...")` hits Node's native ESM resolver which doesn't know tsconfig path aliases.

The shim creates real packages in `node_modules/` so Node can resolve them natively:

```
node_modules/@infrastructure/
├── package.json                    ← { "type": "module", "exports": {...} }
├── dispute-recognition/
│   ├── package.json                ← wildcard exports: "./*": "./*.js"
│   └── adapters/
│       ├── CalyticsPaymentReconciliationAdapter.js
│       ├── CalyticsAisConnectionAdapter.js
│       └── AisConnectionDisputeRecognitionPortBridge.js
├── config/
│   └── config_service.js
├── aws/
│   ├── dynamo_client.js
│   └── sqs_client.js
└── ...
```

Key implementation details in `scripts/build-local-alias-shims.sh`:

1. **`--packages=external`** — externalizes ALL node_modules packages. The shim only resolves tsconfig aliases; pino, AWS SDK, etc. are loaded from node_modules at runtime.

2. **Filtered tsconfig per alias** — when building `@infrastructure`, only `@infrastructure/*` is mapped. Other aliases (`@shared/*`, `@core/*`) are left unmapped so esbuild treats them as package imports → externalized. This prevents cross-alias code duplication (e.g., pino_logger being bundled into every shim).

3. **Scoped package.json** — Node.js treats `@infrastructure/dispute-recognition` as a scoped package name (`@scope/name`). The shim creates `package.json` in each first-level subdirectory with wildcard exports (`"./*": "./*.js"`) so subpath imports resolve correctly.

#### Patch 2: pino Symbol.for() (for require.cache survival)

The root cause: serverless-offline invalidates `require.cache` between Lambda invocations. pino uses `Symbol('pino.setLevel')` — unique per module load. After cache invalidation, pino is loaded twice with different Symbol instances.

The fix: one `sed` command in the shim build script:

```bash
sed -i "s/Symbol('pino\./Symbol.for('pino./g" node_modules/pino/lib/symbols.js
```

Before:
```javascript
const setLevelSym = Symbol('pino.setLevel')     // unique per load
const getLevelSym = Symbol('pino.getLevel')     // unique per load
```

After:
```javascript
const setLevelSym = Symbol.for('pino.setLevel') // global, survives reload
const getLevelSym = Symbol.for('pino.getLevel') // global, survives reload
```

`Symbol.for()` uses Node's global Symbol registry — shared across all module instances, cache invalidation, and even across `vm` contexts. pino itself already uses `Symbol.for()` for its "public" symbols (serializers, formatters, hooks) — we simply extend this to the "private" ones.

The patch is:
- **Idempotent** — `grep -q "Symbol('pino\."` guards against re-patching
- **Applied by the shim script** — no separate command needed
- **Lost on `npm install`** — the shim script detects this and re-patches

### Hot reload behavior

| Code location | Hot reload? | Why |
|--------------|-------------|-----|
| Handler code (`src/domains/*/lambdas/`) | **Yes** | SLS v4 runs TypeScript source directly |
| Service code (`src/domains/*/services/`) | **Yes** | Static imports, resolved by SLS v4 loader |
| Infrastructure adapters (`src/infrastructure/`) | **No** — rebuild shims | Pre-bundled by esbuild into the shim |
| Shared modules (`calytics-shared-modules/`) | **No** — rebuild dist/ | Loaded from pre-built `dist/` |

In practice, infrastructure adapters and shared modules rarely change during feature development. The handler and service code (where 99% of edits happen) reloads instantly.

### Verification

```bash
# Verify pino symbols are patched:
grep "Symbol.for('pino\." node_modules/pino/lib/symbols.js | wc -l
# 31 (all symbols use Symbol.for)
grep "Symbol('pino\." node_modules/pino/lib/symbols.js | wc -l
# 0

# Verify shim has no bundled pino:
grep -r 'from "pino"' node_modules/@infrastructure/ | wc -l
# 0

# Verify shim externalizes @shared:
grep 'from "@shared' node_modules/@infrastructure/repositories/dynamodb/*.js
# import { getLogger } from "@shared/utils/pino_logger";   ← external, not bundled

# Test:
curl -s http://localhost:3333/debit-guard/v1 \
  -H "x-api-key: ak_sand_21c0f785e49e88d7c7d5b6a8f19a2402bbb190e2198a6158a7aa30331aa0e2b2" \
  -H "Content-Type: application/json" -d '{...}'
# HTTP 202 — {"transaction_id":"...","status":"PROCESSING","request_state":"NEW_REQUEST"}

# Second request (after cache invalidation) also works:
# HTTP 202 — no setLevelSym crash
```

---

## Step 5: What About calytics-a2a?

### Does a2a have the same problem?

**No.** Investigation showed:

| Factor | calytics-be | calytics-a2a |
|--------|-------------|--------------|
| Dynamic `import()` with tsconfig aliases | Yes (`@infrastructure/...`) | No (only `@aws-sdk/*` and relative paths) |
| SLS v4 native esbuild build | Yes (`build.esbuild: {...}`) | No (uses `tsc + tsc-alias`) |
| `offline:local` script | Runs `serverless offline` directly | Runs `npm run build` first, then `serverless offline` |
| Module format | ESM (package.json `"type": "module"`) | CJS after tsc build |

calytics-a2a's `offline:local` already pre-builds with `tsc` before starting serverless-offline. Its dynamic imports only reference `@aws-sdk/*` (external npm packages that Node resolves natively). No tsconfig path aliases are used in dynamic imports.

### Does a2a use shared modules?

**Yes** — it depends on:
- `@calytics-sdk/ais-connection` (^1.0.28)
- `@calytics-sdk/core` (^1.0.6)
- `@calytics-sdk/payment-reconciliation` (^1.0.33)
- `@calytics/ais-connection` (^1.0.8)
- `@calytics/payment-reconciliation` (^1.0.7)

But these are loaded via static `import` (resolved at build time by `tsc + tsc-alias`), not via dynamic `import()`. The pino Symbol duplication bug doesn't apply because:
1. `tsc` compiles to CJS (no ESM/CJS interop)
2. The compiled output is served to serverless-offline (no live TypeScript execution)
3. No `require.cache` invalidation affects static imports

---

## Approaches We Tried (and Why They Didn't Work)

### 1. ESM alias shims WITHOUT pino patch (shims alone)

**Approach:** Build shims in dependency order, each using a filtered tsconfig so cross-alias imports are externalized. Pino is externalized from all shims.

**Why it failed:** The shims correctly resolved the dynamic import path. But `@calytics-sdk/payment-reconciliation` (npm package, loaded from node_modules) initializes pino during CJS module loading. serverless-offline's cache invalidation caused pino's symbols.js to load twice → different Symbol instances → crash.

### 2. tsup pre-build (CJS, mirrors production)

**Approach:** Pre-build all handlers with `tsup --format cjs` to `dist/local-lambdas/`. Parameterize handler paths in `serverless.yml` via `${param:HANDLER_BASE}`.

**Why it was rejected:** It worked perfectly (HTTP 202). But it killed hot reload — every code change required a rebuild. Also required running an extra command or modifying `offline:local` script. Not acceptable for DX.

### 3. Custom Node.js ESM loader hook

**Approach:** Register a custom loader via `NODE_OPTIONS="--import ./scripts/tsconfig-paths-register.mjs"` that resolves tsconfig path aliases for dynamic imports.

```javascript
export async function resolve(specifier, context, nextResolve) {
    for (const { prefix, targetDir } of pathMappings) {
        if (specifier.startsWith(prefix + '/')) { /* resolve to file path */ }
    }
    return nextResolve(specifier, context);
}
```

**Why it failed:** SLS v4's Lambda emulator doesn't use Node's standard ESM loader pipeline for handler execution. The registered hooks were never invoked for the dynamic import inside the Lambda handler.

### 4. Changing `build.esbuild.format` to CJS in serverless.yml

**Approach:** Set `format: cjs` in the `build.esbuild` config.

**Why it failed:** SLS v4's native esbuild integration does NOT bundle code in dev mode. Regardless of format setting, serverless-offline runs TypeScript source directly. The format setting only affects `serverless package` / `serverless deploy`.

### 5. Patching the SDK's bundled pino_logger (transport + destination)

**Approach:** Edit `node_modules/@calytics-sdk/payment-reconciliation/dist/shared-module.js` to remove the `transport` + `destination` combination, or wrap pino init in try-catch.

**Why it failed:** The error isn't about transport + destination — it's about Symbol identity. Even `pino({ level: 'info' })` with no transport and no destination crashes if symbols.js was loaded twice. Confirmed by patching to simplest possible pino call — same crash.

### 6. Removing all shims (trusting SLS v4 native esbuild)

**Approach:** With the fixed `build.esbuild` config (object, not boolean), trust esbuild to resolve dynamic imports.

**Why it failed:** SLS v4 does NOT use esbuild in dev mode at all. Dynamic `import("@infrastructure/...")` goes straight to Node's ESM resolver → package not found.

---

## Architecture Diagram: Local vs Cloud Build Pipelines (Final)

```
                        calytics-be
                            |
        +-------------------+-------------------+
        |                                       |
   LOCAL DEVELOPMENT                     CLOUD DEPLOYMENT
   (serverless offline)                  (Terraform)
        |                                       |
   SLS v4 runs .ts source               terraform/build-terraform-lambdas.sh
   directly (no bundling)                npx tsup ... --format cjs
        |                                all aliases inlined
   Static imports:                       output: dist/terraform-lambdas/*.zip
     ✅ resolved by SLS v4                      |
     TypeScript loader                   S3 → Lambda
        |
   Dynamic imports:
     ❌ Node ESM resolver
     doesn't know tsconfig
        |
   FIX: alias shims in                  FIX: pino Symbol.for() patch
   node_modules/@infrastructure/         node_modules/pino/lib/symbols.js
   (pre-bundled ESM, all                 Symbol() → Symbol.for()
    node_modules externalized)           survives require.cache
        |                                invalidation
        +----------------+
                         |
                    ✅ WORKS
                    Hot reload for
                    handler/service code
```

---

## Key Takeaways

1. **`Symbol()` creates unique values per call.** If a module using `Symbol()` is loaded twice (e.g., due to cache invalidation), the symbols diverge and identity checks (`===`) fail silently. Use `Symbol.for()` for symbols that must survive module reloads.

2. **serverless-offline invalidates `require.cache`** to simulate Lambda cold starts. This has devastating side effects for libraries that rely on module-level `Symbol()` identity (like pino v9).

3. **SLS v4 native esbuild does NOT bundle in dev mode.** The `build.esbuild` config only affects `serverless package` / `serverless deploy`. In `serverless offline`, TypeScript source is executed directly. esbuild config options like `external`, `format`, and `tsconfig` have **zero effect** on local development.

4. **Don't sacrifice DX to fix infrastructure bugs.** The tsup pre-build approach worked but killed hot reload. The right fix addresses the root cause (Symbol uniqueness) without changing the development workflow.

5. **Dynamic `import()` is the weak link.** Static imports are resolved at compile time (by esbuild, tsc, or SLS v4's TypeScript loader). Dynamic imports are resolved at runtime by Node's native ESM resolver, which doesn't know about tsconfig path aliases. Shims bridge this gap.

6. **calytics-a2a is not affected** because it pre-builds with `tsc` before running serverless-offline, uses CJS output, and its dynamic imports only reference external npm packages (not tsconfig path aliases).

---

## Files Changed

| File | Repo | Change | Why |
|------|------|--------|-----|
| `scripts/build-local-alias-shims.sh` | calytics-be | New file | Builds alias shims + patches pino symbols. Run once after `npm install`. |
| `local-deploy.sh` | calytics (root) | Phase 3.6 updated | Calls `build-local-alias-shims.sh` automatically |

**`serverless.yml` is unchanged.** Zero application code changes. The only change in calytics-be is a new build script in `scripts/`.

### When to re-run the shim script

| Event | Re-run needed? |
|-------|---------------|
| Changed handler/service code | No — hot reload works |
| Changed `src/infrastructure/` adapter code | Yes — shims are pre-bundled |
| Ran `npm install` | Yes — shims and pino patch are in node_modules |
| Changed shared modules (calytics-shared-modules) | Yes — rebuild shared module dist/ |
| `local-deploy.sh` handles it | Yes — Phase 3.6 auto-runs if shims missing |
