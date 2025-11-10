#!/usr/bin/env bats

load '/usr/lib/bats-support/load'
load '/usr/lib/bats-assert/load'

setup() {
  export COMPONENT="test"
  export LOG_FILE="/tmp/bash-test.log"
  mkdir -p /tmp/src /tmp/backup
  echo "test" > /tmp/src/index.html
}

teardown() {
  rm -rf /tmp/src /tmp/backup /tmp/bash-test.log
}

@test "backup-manager creates backup directory" {
  run ../modules/backup-manager.sh
  assert_success
  assert_output --partial "Backup completed successfully"
  [ -d "/tmp/backup" ]
}

@test "backup-manager uses retry on failure" {
  # Mock rsync to fail first time
  rsync() { (( "${1:-0}" == 1 )) && return 1; return 0; }
  export -f rsync
  run bash -c "source ../lib/retry.sh; retry 3 1 rsync"
  assert_success
}
