# REAL app-of-apps root (Option 2). Unlike root.app (offline), its `apps`
# directory holds *real* rendered ArgoCD Application YAMLs (see argo-apps/),
# produced by:
#   real-argo.sh render-children --repo-url "$REPO"
# Apply this root and ArgoCD reads those child Applications and creates them.
kind = Application
name = platform-root
apps = days/day27/examples/argo-apps
