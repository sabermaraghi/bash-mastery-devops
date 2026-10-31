#!/usr/bin/env bats
# Tests for the Day 22 real (Option 2) container tool. Tool-independent checks
# always run; podman/cosign-dependent checks skip gracefully when absent so the
# suite stays green on any machine (offline default is covered by container.bats).
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day22/scripts"
  R="$S/real-container.sh"
}

@test "real-container.sh is syntactically valid" {
  run bash -n "$R"
  assert_success
}

@test "no subcommand shows usage (exit 2)" {
  run bash "$R"
  [ "$status" -eq 2 ]
}

@test "unknown subcommand shows usage (exit 2)" {
  run bash "$R" frobnicate
  [ "$status" -eq 2 ]
}

@test "--help prints usage and exits 0" {
  run bash "$R" --help
  assert_success
  assert_output_contains "usage:"
}

@test "build with missing args shows usage (exit 2)" {
  run bash "$R" build
  [ "$status" -eq 2 ]
}

@test "build rejects an unpinned image before doing any work" {
  # Uses a real temp context so the failure is the pin check, not a missing dir.
  d="$BATS_TEST_TMPDIR/ctx"
  mkdir -p "$d"
  printf 'FROM alpine:3.19\nUSER app\n' >"$d/Containerfile"
  run bash "$R" build "$d" myimage
  assert_failure
  assert_output_contains "explicit tag"
}

@test "build fails closed when the Containerfile is insecure" {
  d="$BATS_TEST_TMPDIR/badctx"
  mkdir -p "$d"
  printf 'FROM ubuntu:latest\n' >"$d/Containerfile"
  run bash "$R" build "$d" myimage:1.0.0
  assert_failure
  assert_output_contains "audit failed"
}

@test "sign requires cosign; missing -> exit 3" {
  if command -v cosign >/dev/null 2>&1; then skip "cosign present"; fi
  run bash "$R" sign registry.example/app@sha256:deadbeef
  [ "$status" -eq 3 ]
}

@test "build/run/inspect require a real engine; missing -> exit 3" {
  if command -v podman >/dev/null 2>&1 || command -v buildah >/dev/null 2>&1 || command -v docker >/dev/null 2>&1; then
    skip "a container engine is installed"
  fi
  d="$BATS_TEST_TMPDIR/okctx"
  mkdir -p "$d"
  printf 'FROM alpine:3.19\nUSER app\n' >"$d/Containerfile"
  run bash "$R" build "$d" myimage:1.0.0
  [ "$status" -eq 3 ]
  run bash "$R" run myimage:1.0.0
  [ "$status" -eq 3 ]
  run bash "$R" inspect myimage:1.0.0
  [ "$status" -eq 3 ]
}

# ---- podman-guarded real round-trip (only where podman is installed) ----
@test "build -> inspect a real rootless image (podman)" {
  command -v podman >/dev/null 2>&1 || skip "podman not installed"
  d="$BATS_TEST_TMPDIR/realctx"
  mkdir -p "$d"
  {
    echo "FROM alpine:3.19"
    echo "RUN adduser -D app"
    echo "USER app"
    echo 'CMD ["echo","hi"]'
  } >"$d/Containerfile"
  run bash "$R" build "$d" day22-test:1.0.0
  assert_success
  run bash "$R" inspect day22-test:1.0.0
  assert_success
  assert_output_contains "non-root"
  podman image rm -f day22-test:1.0.0 || true
}
