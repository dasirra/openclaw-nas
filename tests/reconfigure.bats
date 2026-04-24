#!/usr/bin/env bats
# Tests for _integration_status helper in install.sh

load test_helper

setup() {
  setup_tmpdir
  export SCRIPT_DIR="$TEST_TMPDIR"
  # Stub gum so lib.sh can be sourced without it installed
  gum() { :; }
  export -f gum
  source "$PROJECT_ROOT/installer/lib.sh"
  export -f _integration_status
}

teardown() {
  teardown_tmpdir
}

# ---------------------------------------------------------------------------
# discord
# ---------------------------------------------------------------------------

@test "_integration_status: discord configured when DISCORD_SCOUTER_TOKEN set" {
  echo "DISCORD_SCOUTER_TOKEN=some-token" > "$TEST_TMPDIR/.env"
  run _integration_status "scouter" "discord"
  [ "$output" = "configured" ]
}

@test "_integration_status: discord not configured when DISCORD_SCOUTER_TOKEN empty" {
  echo "DISCORD_SCOUTER_TOKEN=" > "$TEST_TMPDIR/.env"
  run _integration_status "scouter" "discord"
  [ "$output" = "not configured" ]
}

@test "_integration_status: discord not configured when DISCORD_SCOUTER_TOKEN absent" {
  run _integration_status "scouter" "discord"
  [ "$output" = "not configured" ]
}

# ---------------------------------------------------------------------------
# gws
# ---------------------------------------------------------------------------

@test "_integration_status: gws configured when credentials.json exists" {
  mkdir -p "$TEST_TMPDIR/home/.config/gws"
  touch "$TEST_TMPDIR/home/.config/gws/credentials.json"
  run _integration_status "scouter" "gws"
  [ "$output" = "configured" ]
}

@test "_integration_status: gws not configured when credentials.json absent" {
  run _integration_status "scouter" "gws"
  [ "$output" = "not configured" ]
}

@test "_integration_status: gws not configured when config dir exists but file missing" {
  mkdir -p "$TEST_TMPDIR/home/.config/gws"
  run _integration_status "scouter" "gws"
  [ "$output" = "not configured" ]
}

# ---------------------------------------------------------------------------
# xurl
# ---------------------------------------------------------------------------

@test "_integration_status: xurl configured when X_BEARER_TOKEN set" {
  echo "X_BEARER_TOKEN=bearer-xyz" > "$TEST_TMPDIR/.env"
  run _integration_status "scouter" "xurl"
  [ "$output" = "configured" ]
}

@test "_integration_status: xurl not configured when X_BEARER_TOKEN empty" {
  echo "X_BEARER_TOKEN=" > "$TEST_TMPDIR/.env"
  run _integration_status "scouter" "xurl"
  [ "$output" = "not configured" ]
}

@test "_integration_status: xurl not configured when X_BEARER_TOKEN absent" {
  run _integration_status "scouter" "xurl"
  [ "$output" = "not configured" ]
}

# ---------------------------------------------------------------------------
# unknown integration
# ---------------------------------------------------------------------------

@test "_integration_status: unknown integration returns not configured" {
  run _integration_status "scouter" "nonexistent"
  [ "$output" = "not configured" ]
}

@test "_integration_status: unknown integration with token in env still returns not configured" {
  echo "SOME_TOKEN=value" > "$TEST_TMPDIR/.env"
  run _integration_status "scouter" "unknown_intg"
  [ "$output" = "not configured" ]
}
