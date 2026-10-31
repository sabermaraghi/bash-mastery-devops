#!/usr/bin/env bats
# capstone.sh tests — exercise the offline `validate` path and argument handling.
# No cluster required: these assert the project is internally consistent so CI
# stays green, exactly like every day's offline Option 1.
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/projects/devops-platform/capstone.sh"
}

@test "capstone.sh is syntactically valid" {
  run bash -n "$S"
  assert_success
}

@test "no subcommand -> usage, exit 2" {
  run bash "$S"
  assert_failure 2
}

@test "unknown subcommand -> exit 2" {
  run bash "$S" wat
  assert_failure 2
}

@test "validate confirms the capstone layout is complete" {
  run bash "$S" validate
  assert_success
  assert_output_contains "capstone layout is valid"
}

@test "validate checks the backend Bash service parses" {
  run bash "$S" validate
  assert_success
  assert_output_contains "backend server.sh parses"
}

@test "validate verifies every manifest declares a kind" {
  run bash "$S" validate
  assert_success
  # validate prints manifest paths relative to the capstone dir.
  assert_output_contains "manifest gitops/root.yaml"
  assert_output_contains "manifest services/backend/k8s/deployment.yaml"
}

@test "up requires a context" {
  run bash "$S" up
  assert_failure 2
}

@test "deploy requires a context" {
  run bash "$S" deploy
  assert_failure 2
}

@test "operate requires a context" {
  run bash "$S" operate
  assert_failure 2
}

@test "chaos requires a context" {
  run bash "$S" chaos
  assert_failure 2
}

@test "heal requires a context" {
  run bash "$S" heal
  assert_failure 2
}

@test "validate includes the WidgetSet CR for the operator step" {
  run bash "$S" validate
  assert_success
  assert_output_contains "ops/widgetset.cr"
}

@test "images requires a context" {
  run bash "$S" images
  assert_failure 2
}

@test "doctor requires a context" {
  run bash "$S" doctor
  assert_failure 2
}

@test "argocd-repair requires a context" {
  run bash "$REPO_ROOT/projects/devops-platform/capstone.sh" argocd-repair
  assert_failure
}

@test "usage lists the argocd-repair subcommand" {
  run bash "$REPO_ROOT/projects/devops-platform/capstone.sh"
  assert_output_contains "capstone.sh argocd-repair"
}

@test "usage lists the images and doctor subcommands" {
  run bash "$S"
  assert_failure 2
  assert_output_contains "capstone.sh images"
  assert_output_contains "capstone.sh doctor"
}

# --- operator namespace + repository hygiene ---------------------------------

@test "operate creates the widgets namespace before reconciling" {
  # Nothing owns the widgets namespace: the Day 26 operator step is not
  # GitOps-managed, so there is no CreateNamespace=true to lean on and
  # 'kubectl apply' fails with NotFound on a freshly built cluster.
  run bash -c 'sed -n "/^cmd_operate()/,/^}/p" "$REPO_ROOT/projects/devops-platform/capstone.sh" | grep -q "_ensure_ns"'
  assert_success
}

@test "teardown removes the widgets namespace it created" {
  run bash -c 'sed -n "/^cmd_down()/,/^}/p" "$REPO_ROOT/projects/devops-platform/capstone.sh" | grep -q "WIDGET_NS"'
  assert_success
}

@test "terraform state, provider binaries and kubeconfigs are gitignored" {
  # terraform.tfstate and <cluster>-config carry cluster admin credentials in
  # plaintext; .terraform/ is ~40MB of provider binaries.
  # Comment lines are stripped so this checks real patterns, not the comments
  # that explain them.
  for pattern in ".terraform/" "*.tfstate" "*-config"; do
    run bash -c 'grep -v "^[[:space:]]*#" "$REPO_ROOT/.gitignore" | grep -qF "$1"' _ "$pattern"
    assert_success
  done
}

@test "the terraform provider lock file stays tracked" {
  # .terraform.lock.hcl pins provider versions and must NOT be ignored.
  # Comments are stripped: the .gitignore documents this rule in prose, and
  # grepping raw would match that explanation instead of an actual pattern.
  run bash -c 'grep -v "^[[:space:]]*#" "$REPO_ROOT/.gitignore" | grep -qF ".terraform.lock.hcl"'
  assert_failure
}

# --- ArgoCD install path (client-side apply cannot install ArgoCD) -----------

@test "no install path client-side applies the ArgoCD manifest" {
  # ArgoCD's CRDs exceed the 262144-byte last-applied-configuration annotation
  # limit, so a client-side apply always fails with 'metadata.annotations: Too
  # long'. Both the Terraform and the capstone.sh route must stay server-side.
  # Comment lines are stripped first: those files *document* the broken command,
  # so grepping them raw would match the explanation instead of real code.
  run bash -c 'grep -hv "^[[:space:]]*#" "$REPO_ROOT/projects/devops-platform/infra/main.tf" "$REPO_ROOT/days/day27/scripts/real-argo.sh" | grep "apply -n argocd -f"'
  assert_failure
}

@test "the ArgoCD installer uses a server-side apply" {
  run grep -q -e "--server-side --force-conflicts" "$REPO_ROOT/days/day27/scripts/real-argo.sh"
  assert_success
}

@test "the Terraform install reuses the day27 ArgoCD script" {
  run grep -q "real-argo.sh" "$REPO_ROOT/projects/devops-platform/infra/main.tf"
  assert_success
}

@test "the backend Bash server script is valid bash" {
  run bash -n "$REPO_ROOT/projects/devops-platform/services/backend/app/server.sh"
  assert_success
}

# --- backend HTTP behaviour (no socket needed: the script is sourceable) -----

@test "backend answers 200 + JSON on /healthz" {
  run bash -c 'source "$REPO_ROOT/projects/devops-platform/services/backend/app/server.sh"; respond /healthz'
  assert_success
  assert_output_contains "HTTP/1.1 200 OK"
  assert_output_contains '{"status":"ok"}'
}

@test "backend answers 200 + JSON on /readyz" {
  run bash -c 'source "$REPO_ROOT/projects/devops-platform/services/backend/app/server.sh"; respond /readyz'
  assert_success
  assert_output_contains "HTTP/1.1 200 OK"
}

@test "backend serves its version payload on /" {
  run bash -c 'source "$REPO_ROOT/projects/devops-platform/services/backend/app/server.sh"; respond /'
  assert_success
  assert_output_contains '"service":"backend"'
}

@test "backend 404s an unknown path" {
  run bash -c 'source "$REPO_ROOT/projects/devops-platform/services/backend/app/server.sh"; respond /nope'
  assert_success
  assert_output_contains "HTTP/1.1 404 Not Found"
}

@test "backend parses a full kube-probe request read from the socket" {
  run bash -c 'source "$REPO_ROOT/projects/devops-platform/services/backend/app/server.sh"; printf "GET /readyz HTTP/1.1\r\nHost: 10.244.0.5:8080\r\nUser-Agent: kube-probe/1.31\r\n\r\n" | handle_request'
  assert_success
  assert_output_contains "HTTP/1.1 200 OK"
}

@test "backend never passes the busybox-incompatible nc -q flag" {
  # busybox nc has no -q; passing it made nc exit instantly and crash-looped the
  # pod. Guard the real invocation line, not the comments explaining it.
  run bash -c 'grep -F "\"\$NC_BIN\"" "$REPO_ROOT/projects/devops-platform/services/backend/app/server.sh" | grep -e "-q"'
  assert_failure
}

@test "sourcing the backend does not start the listener" {
  run bash -c 'source "$REPO_ROOT/projects/devops-platform/services/backend/app/server.sh"; echo sourced-ok'
  assert_success
  assert_output_contains "sourced-ok"
}
