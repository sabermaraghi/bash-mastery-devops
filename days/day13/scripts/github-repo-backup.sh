#!/usr/bin/env bash
set -euo pipefail

ORG="ericvalijani"    # your actual GitHub username instead of "kubernetes"
TOKEN="ghp_yourtoken" # a real PAT from github.com/settings/tokens
BACKUP_DIR="/backup/github/$ORG"
MAX_PARALLEL=10 # bounded, to stay under GitHub's API rate limit
DRY_RUN="${DRY_RUN:-false}"

command -v curl &>/dev/null || {
  echo "ERROR: curl is not installed"
  exit 1
}
command -v jq &>/dev/null || {
  echo "ERROR: jq is not installed"
  exit 1
}

backup_repo() {
  local repo="$1"
  local url="https://api.github.com/repos/$ORG/$repo"
  local clone_url
  clone_url=$(curl -sH "Authorization: token $TOKEN" -H "User-Agent: bash-mastery-devops" "$url" | jq -r .clone_url)
  local dir="$BACKUP_DIR/$repo"

  [[ -d "$dir" ]] && return

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "Would clone: $repo -> $dir"
    return
  fi

  echo "Backup $repo ..."
  git clone --mirror "$clone_url" "$dir" >/dev/null 2>&1
}
export -f backup_repo
export ORG TOKEN BACKUP_DIR DRY_RUN

mkdir -p "$BACKUP_DIR"
# /user/repos returns the authenticated token owner's own repos (public + private).
# Personal accounts don't work with /orgs/{org}/repos - that endpoint is for real
# GitHub Organizations only.
repos=$(curl -sH "Authorization: token $TOKEN" -H "User-Agent: bash-mastery-devops" \
  "https://api.github.com/user/repos?per_page=100" | jq -r '.[].name')

echo "$repos" | xargs -n 1 -P "$MAX_PARALLEL" -I {} bash -c 'backup_repo "$@"' _ {}
echo "Completed the backup of all $ORG repos"
