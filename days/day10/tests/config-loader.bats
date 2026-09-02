#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  LOADER="$REPO_ROOT/days/day10/scripts/config-loader.sh"
  APP="$REPO_ROOT/days/day10/scripts/app.sh"
  export CONFIG_FILE="$BATS_TEST_TMPDIR/.env"
}

write_valid_env() {
  cat >"$CONFIG_FILE" <<'ENV'
APP_ENV=staging
TARGET_HOST=localhost
TARGET_PORT=443
API_KEY=sk-secure-test-1234567890
DB_PASS=supersecret
ENV
}

@test "scripts are syntactically valid" {
  run bash -n "$LOADER"
  assert_success
  run bash -n "$APP"
  assert_success
}

@test "loads a valid .env and reports success" {
  write_valid_env
  run bash "$LOADER"
  assert_success
  assert_output_contains "Config loaded successfully"
  assert_output_contains "Target: localhost:443"
}

@test "exits with a clear error when config file is missing" {
  export CONFIG_FILE="$BATS_TEST_TMPDIR/nope.env"
  run bash "$LOADER"
  assert_failure
  assert_output_contains "Config file not found"
}

@test "names every missing required variable" {
  printf 'APP_ENV=dev\n' >"$CONFIG_FILE"
  run bash "$LOADER"
  assert_failure
  assert_output_contains "Missing required variables"
  assert_output_contains "TARGET_HOST"
  assert_output_contains "API_KEY"
}

@test "uses TARGET_HOST, not the old DB_HOST name (regression)" {
  printf 'APP_ENV=prod\nTARGET_HOST=10.0.0.10\nAPI_KEY=sk-live\n' >"$CONFIG_FILE"
  run bash "$LOADER"
  assert_success
  assert_output_contains "Target: 10.0.0.10:443"
}

@test "rejects an invalid APP_ENV" {
  printf 'APP_ENV=production\nTARGET_HOST=x\nAPI_KEY=y\n' >"$CONFIG_FILE"
  run bash "$LOADER"
  assert_failure
  assert_output_contains "APP_ENV must be one of"
}

@test "rejects a non-numeric TARGET_PORT" {
  printf 'APP_ENV=dev\nTARGET_HOST=x\nTARGET_PORT=https\nAPI_KEY=y\n' >"$CONFIG_FILE"
  run bash "$LOADER"
  assert_failure
  assert_output_contains "TARGET_PORT must be numeric"
}

@test "never sources the .env: an injected command is not executed" {
  cat >"$CONFIG_FILE" <<ENV
APP_ENV=dev
TARGET_HOST=x
API_KEY=y
\$(touch "$BATS_TEST_TMPDIR/pwned")
ENV
  run bash "$LOADER"
  assert_success
  [ ! -f "$BATS_TEST_TMPDIR/pwned" ]
}

@test "masks the API key instead of printing it" {
  write_valid_env
  run bash "$LOADER"
  assert_success
  assert_output_contains "API_KEY: sk"
  [[ "$output" != *"sk-secure-test-1234567890"* ]]
}

@test "app.sh sources the loader and connects" {
  write_valid_env
  run bash "$APP"
  assert_success
  assert_output_contains "Connecting to localhost:443 as staging"
  assert_output_contains "key present: yes"
}
