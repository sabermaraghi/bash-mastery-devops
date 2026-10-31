# Day 22 — Rootless Containers

Phase 5 goes container-native. The goal today: run workloads **without root**,
drop every capability by default, and catch privilege anti-patterns *before*
they ship. Everything here is runtime-optional — the scripts detect podman/docker
and fall back to dry-run/static analysis, so they work (and test) even with no
engine installed.

> **Two ways to run today**
> 1. **Offline (default)** — dry-run launch + static audit. No engine needed;
>    this is what CI and the tests exercise.
> 2. **Real (Option 2)** — actually build, run, inspect, and sign a rootless
>    container with `podman`/`buildah` + `cosign`. See
>    [🚀 Option 2 — real rootless containers](#-option-2--real-rootless-containers-podmanbuildah--cosign)
>    at the end. The offline path stays the default and the tested one.

---

## 📁 Scripts for today

| Script | Path | What it does |
|---|---|---|
| **Container lib** | `days/day22/scripts/container-lib.sh` | Sourced helpers: runtime detection, rootless check, tag pinning |
| **Run rootless** | `days/day22/scripts/run-rootless.sh` | Launch with hardened defaults (`--dry-run` prints the command) |
| **Containerfile audit** | `days/day22/scripts/containerfile-audit.sh` | Static linter for rootless/security anti-patterns |
| **Real container** *(Option 2)* | `days/day22/scripts/real-container.sh` | Really build/run/inspect/sign a rootless image (podman/buildah + cosign) |

---

## 1. Why rootless?

A container that runs as root *is* root on the host if it escapes. Rootless
flips the default: the process maps to an unprivileged host user via **user
namespaces**, so a breakout lands as nobody. Podman is rootless by design;
Docker needs rootless mode.

## 2. Secure-by-default launch

`run-rootless.sh` never trusts defaults — it *enforces* them:

```bash
bash days/day22/scripts/run-rootless.sh --dry-run nginx:1.25
# podman run --rm --read-only --cap-drop=ALL --security-opt=no-new-privileges \
#   --pids-limit=256 --memory=256m --network=none --user 1000 nginx:1.25
```

| Flag | Why |
|---|---|
| `--read-only` | immutable rootfs; writes go to explicit tmpfs/volumes |
| `--cap-drop=ALL` | start from zero Linux capabilities |
| `--security-opt=no-new-privileges` | block setuid escalation |
| `--user <uid>` (never 0) | non-root process; refuses uid 0 |
| `--network=none` (default) | deny network unless you opt in |
| `--pids-limit` / `--memory` | contain fork bombs and OOM blast radius |

Images **must be pinned** to an explicit tag — `:latest` earns a warning, no tag
is a hard error.

## 3. Catch it in review, not prod

`containerfile-audit.sh` statically flags the classics:

```bash
bash days/day22/scripts/containerfile-audit.sh Containerfile
```

| Finding | Severity |
|---|---|
| No non-root `USER` (or `USER root`) | VIOLATION |
| `FROM` without a tag / `:latest` | VIOLATION |
| Secret baked into an `ENV` layer | VIOLATION |
| `ADD https://...` remote fetch | WARN |
| `sudo` inside the image | WARN |

Exit code is non-zero if any VIOLATION is found — wire it straight into CI.

---

## ✅ Verify

```bash
bats days/day22/tests
bash days/day22/scripts/run-rootless.sh --dry-run alpine:3.19 -- sh -c 'echo hi'
```

---

## Recap

| Concept | One-liner |
|---|---|
| Rootless | breakout lands as an unprivileged host user |
| Drop caps | `--cap-drop=ALL`, add back only what's needed |
| No new privs | `--security-opt=no-new-privileges` |
| Pin tags | reproducible builds, no `:latest` |
| Shift left | audit the Containerfile in CI |

---

## 🚀 Option 2 — real rootless containers (podman/buildah + cosign)

Everything above is the **offline default**. When you actually have a container
engine, `real-container.sh` does the real thing — and it *composes* the offline
tools rather than duplicating them: it **audits the Containerfile before it
builds** (fail-closed), reuses `run-rootless.sh` for the exact same hardening,
and confirms the finished image really runs as a non-root user.

### Prerequisites

| Tool | Install |
|---|---|
| `podman` (rootless by design) or `buildah` | <https://podman.io/docs/installation> · <https://buildah.io/#install> |
| `cosign` *(only for image signing)* | <https://docs.sigstore.dev/cosign/installation> · `brew install cosign` |

Missing the tool a subcommand needs? It prints an install hint and exits `3` —
never a fake success.

### Run it (from scratch)

```bash
# 0. write a hardened, non-root Containerfile in a build context
mkdir -p app
cat > app/Containerfile <<'EOF'
FROM alpine:3.19
RUN adduser -D app
USER app
CMD ["echo", "hello from rootless"]
EOF

# 1. build it — audits the Containerfile FIRST, refuses to build if it fails
bash days/day22/scripts/real-container.sh build ./app myapp:1.0.0

# 2. prove the image really runs as a non-root user
bash days/day22/scripts/real-container.sh inspect myapp:1.0.0   # -> "USER is non-root: app"

# 3. run it for real with the full hardening (read-only, cap-drop=ALL, etc.)
bash days/day22/scripts/real-container.sh run myapp:1.0.0        # -> hello from rootless

# 4. clean up
podman image rm -f myapp:1.0.0
```

### Signing an image (advanced)

Unlike Day 18's blob signing, **image** signing works on a registry reference —
so push first, then sign the resulting digest (reuse Day 18's `cosign.key`):

```bash
podman push myapp:1.0.0 registry.example.com/myapp:1.0.0
export COSIGN_PASSWORD="..."
bash days/day22/scripts/real-container.sh sign   registry.example.com/myapp@sha256:<digest>
bash days/day22/scripts/real-container.sh verify registry.example.com/myapp@sha256:<digest>
```

The script tries the modern cosign invocation first and falls back for older
cosign, just like Day 18. Override key paths with `COSIGN_KEY` / `COSIGN_PUBKEY`.

### Offline vs. real, side by side

| | Offline (default) | Real (Option 2) |
|---|---|---|
| Build | *(n/a — audit only)* | `podman build` / `buildah bud` after a fail-closed audit |
| Launch | `--dry-run` prints the command | container actually runs, same hardened flags |
| Non-root check | static (`USER` in Containerfile) | live (`inspect` the built image's config) |
| Signing | *(n/a)* | `cosign sign`/`verify` an image by digest |
| Needs an engine? | no | yes (podman/buildah; cosign for signing) |
| Exit codes | `0` ok · `1` finding | `0` ok · `1` failure · `2` usage · `3` tool missing |

---

Next up: **Day 23 — CI/CD framework.**
