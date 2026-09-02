# Day 18 — Zero-Trust Security Pipeline

Today's goal: wire yesterday's building blocks into a **fail-closed pipeline**.
Zero-trust means *never trust, always verify* — every stage is a gate, and the
first failure halts everything so bad code or tampered artifacts can never flow
downstream. You'll verify artifact integrity with checksums and guard a deploy
behind independently-checked preconditions.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Verify Artifact** | `days/day18/scripts/verify-artifact.sh` | SHA-256 manifest generation + verification | `bash days/day18/scripts/verify-artifact.sh manifest .` |
| **Zero-Trust Pipeline** | `days/day18/scripts/zero-trust-pipeline.sh` | Fail-closed gates: syntax → secrets → integrity | `bash days/day18/scripts/zero-trust-pipeline.sh .` |
| **Deploy Guard** | `days/day18/scripts/deploy-guard.sh` | Authorizes a deploy only when every check passes | see §4 |
| **Real Sign** _(Option 2)_ | `days/day18/scripts/real-sign.sh` | Signs & verifies the manifest with real `cosign` | `bash days/day18/scripts/real-sign.sh sign ./build` |

> **Two ways to run this day.** **Option 1 (default)** is the offline, dependency-free
> pipeline above — tested by BATS and run in CI. **Option 2** upgrades the integrity
> gate with real cryptographic signing via `cosign`. See
> [Option 2](#-option-2--real-signing-with-cosign); shared real-mode helpers live in `platform/`.

---

## 1. The zero-trust principle

Traditional pipelines trust anything that got past the first step. Zero-trust
re-verifies at **every** boundary and denies by default:

- **Never trust input** — validate with allowlists (Day 17).
- **Verify artifacts** — check checksums before you deploy bytes.
- **Fail closed** — on any doubt, stop; don't "continue on error".
- **Least privilege** — each stage gets only what it needs.

## 2. Artifact integrity (checksums)

Build-time you record a manifest; before every downstream step you re-verify it.
A single changed byte fails the gate.

```bash
bash days/day18/scripts/verify-artifact.sh manifest ./build   # writes build/SHA256SUMS
bash days/day18/scripts/verify-artifact.sh verify   ./build   # exit 1 on any mismatch
```

## 3. The fail-closed pipeline

Stages run in order and **stop at the first failure**:

| # | Stage | Gate |
|---|---|---|
| 1 | `syntax` | every `*.sh` passes `bash -n` |
| 2 | `secrets` | Day 17's `secret-scanner.sh` finds nothing |
| 3 | `integrity` | `SHA256SUMS` verifies (skipped if absent) |

```bash
bash days/day18/scripts/zero-trust-pipeline.sh ./build
bash days/day18/scripts/zero-trust-pipeline.sh --list
```

Notice it **composes** yesterday's scanner rather than re-implementing it — one
tool, one responsibility.

## 4. The deploy guard

The last gate authorizes a deploy only when environment, target host, **and**
artifact integrity all check out. Every input is validated before use
(`lib/validator.sh`), and the host must be on an explicit allowlist.

```bash
DEPLOY_ENV=staging \
TARGET_HOST=web-01 \
ALLOWED_HOSTS=web-01,web-02 \
ARTIFACT_DIR=./build \
  bash days/day18/scripts/deploy-guard.sh          # -> "DEPLOY AUTHORIZED" (exit 0)
```

Drop any precondition (bad env, unknown host, tampered artifact) and it prints
the reason and exits 1 — **fail-closed**.

---

## 🚀 Option 2 — Real signing with cosign

The offline `verify-artifact.sh` proves **integrity** — a SHA-256 manifest tells
you the bytes didn't change. But it can't prove **who** produced them: anyone can
regenerate `SHA256SUMS`. Real supply-chain security adds **authenticity** by
*signing* the manifest with a private key. `real-sign.sh` does exactly that with
[`cosign`](https://github.com/sigstore/cosign), and it **composes** the offline
tool — it signs the very same `SHA256SUMS` manifest.

### Prerequisites

| Tool | Install |
|---|---|
| `cosign` | <https://github.com/sigstore/cosign/releases> · `brew install cosign` |

If cosign isn't installed, the script prints what's missing and exits `3`.

### Run it (from scratch — no build dir or key needed first)

```bash
# 0. make a demo artifact dir to sign (or point the commands at any real folder)
mkdir -p build
echo 'echo hello' > build/app.sh
echo 'v1.0.0'     > build/version.txt

# 1. one-time: generate a key pair (cosign.key is SECRET — never commit it)
export COSIGN_PASSWORD="a-strong-passphrase"
bash days/day18/scripts/real-sign.sh keygen .

# 2. sign the build: (re)builds SHA256SUMS, then writes the signature
#    (SHA256SUMS.bundle on newer cosign, or SHA256SUMS.sig on older — handled for you)
bash days/day18/scripts/real-sign.sh sign ./build

# 3. verify authenticity + integrity against the public key
bash days/day18/scripts/real-sign.sh verify ./build        # -> "signature OK"

# (optional) prove tamper-detection, then clean up the demo
echo 'sneaky' >> build/app.sh
bash days/day18/scripts/verify-artifact.sh verify ./build  # -> integrity FAILED (exit 1)
rm -f cosign.key cosign.pub && rm -rf build                # never commit cosign.key
```

You don't need to pass `--bundle` or any version-specific flags yourself — the
script **tries the modern cosign invocation first and falls back automatically**
if your cosign is older, so the same commands work on cosign v1/v2/v3. It stays
offline where the flags allow (no Rekor/network round-trip). Override key paths
with `COSIGN_KEY` / `COSIGN_PUBKEY`. Exit codes: `0` ok · `1` failure · `2` usage
· `3` cosign missing.

### Offline vs. real, side by side

| | Offline (default) | Real (Option 2) |
|---|---|---|
| Tool | `sha256sum` | `cosign` |
| Proves | integrity (unchanged bytes) | integrity **+** authenticity (who signed) |
| Artifact | `SHA256SUMS` | `SHA256SUMS` **+** signature (`.bundle`/`.sig`) |
| Tamper detected? | yes | yes |
| Forgery detected? | no (anyone can regenerate) | yes (needs the private key) |

> **Tip:** wire `real-sign.sh verify` into `deploy-guard.sh` (or the pipeline's
> `integrity` gate) to make a valid signature — not just a matching checksum — a
> hard precondition for deploy.

---

## ✅ Verify

```bash
bats days/day18/tests
bash days/day18/scripts/zero-trust-pipeline.sh --list
```

The Option 2 tests in `tests/real-sign.bats` **skip** the cosign-dependent cases
when cosign isn't installed, so the suite stays green everywhere.

---

## Recap

| Concept | One-liner |
|---|---|
| Zero-trust | never trust, always verify, at every stage |
| Integrity | `sha256sum` manifest → verify before deploy |
| Fail-closed | first gate failure halts the pipeline |
| Compose | pipeline reuses the Day 17 scanner |
| Deploy guard | env + host allowlist + verified artifact |

Next up: **Day 19 — Performance & optimization.**
