#!/usr/bin/env bash
# lib/utils.sh — small common helpers.
is_command() { command -v "$1" >/dev/null 2>&1; }
timestamp() { date +%Y%m%d-%H%M%S; }
