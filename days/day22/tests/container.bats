#!/usr/bin/env bats
load ../../../tests/test_helper

setup() { S="$REPO_ROOT/days/day22/scripts"; }

@test "all day22 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

# ---- container-lib.sh ----
@test "require_pinned_tag accepts a pinned tag, flags latest and missing" {
  run bash -c "source '$S/container-lib.sh'; require_pinned_tag nginx:1.25"
  assert_success
  run bash -c "source '$S/container-lib.sh'; require_pinned_tag nginx:latest"
  [ "$status" -eq 2 ]
  run bash -c "source '$S/container-lib.sh'; require_pinned_tag nginx"
  [ "$status" -eq 1 ]
}

@test "is_rootless returns 2 for an unknown runtime" {
  run bash -c "source '$S/container-lib.sh'; is_rootless bogus"
  [ "$status" -eq 2 ]
}

# ---- run-rootless.sh ----
@test "run-rootless --dry-run emits all hardening flags" {
  run bash "$S/run-rootless.sh" --dry-run alpine:3.19
  assert_success
  assert_output_contains "run --rm"
  assert_output_contains "--read-only"
  assert_output_contains "--cap-drop=ALL"
  assert_output_contains "no-new-privileges"
  assert_output_contains "--user 1000"
  assert_output_contains "--network=none"
  assert_output_contains "alpine:3.19"
}

@test "run-rootless passes through name, user, network and command" {
  run bash "$S/run-rootless.sh" --dry-run --name web --user 1500 --network bridge alpine:3.19 -- echo hi
  assert_success
  assert_output_contains "--name web"
  assert_output_contains "--user 1500"
  assert_output_contains "--network=bridge"
  assert_output_contains "alpine:3.19"
  assert_output_contains "echo hi"
}

@test "run-rootless refuses uid 0" {
  run bash "$S/run-rootless.sh" --dry-run --user 0 alpine:3.19
  assert_failure
}

@test "run-rootless rejects an unpinned image" {
  run bash "$S/run-rootless.sh" --dry-run alpine
  assert_failure
}

@test "run-rootless with no image shows usage" {
  run bash "$S/run-rootless.sh" --dry-run
  assert_failure
}

# ---- containerfile-audit.sh ----
@test "audit passes a hardened Containerfile" {
  f="$BATS_TEST_TMPDIR/Good.Containerfile"
  {
    echo "FROM alpine:3.19"
    echo "RUN adduser -D app"
    echo "USER app"
    echo 'CMD ["/bin/sh"]'
  } >"$f"
  run bash "$S/containerfile-audit.sh" "$f"
  assert_success
  assert_output_contains "violations: 0"
}

@test "audit flags root, latest, and baked secrets" {
  f="$BATS_TEST_TMPDIR/Bad.Containerfile"
  {
    echo "FROM ubuntu:latest"
    echo "ENV API_KEY=supersecretvalue"
    echo "RUN sudo apt-get update"
    echo "ADD https://example.com/app.tar /app"
  } >"$f"
  run bash "$S/containerfile-audit.sh" "$f"
  assert_failure
  assert_output_contains ":latest"
  assert_output_contains "secret baked"
  assert_output_contains "no non-root USER"
}

@test "audit flags an explicit USER root" {
  f="$BATS_TEST_TMPDIR/Root.Containerfile"
  {
    echo "FROM alpine:3.19"
    echo "USER root"
  } >"$f"
  run bash "$S/containerfile-audit.sh" "$f"
  assert_failure
  assert_output_contains "USER root"
}

@test "audit fails on a missing file" {
  run bash "$S/containerfile-audit.sh" "$BATS_TEST_TMPDIR/nope"
  assert_failure
}
