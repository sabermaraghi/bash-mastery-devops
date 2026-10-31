# WidgetSet custom resource for the capstone operator step (Day 26).
# `capstone.sh operate` feeds this to real-operator.sh, which reconciles the
# cluster toward it by managing a Deployment in the `widgets` namespace — the
# same reconcile pattern real Kubernetes operators use.
kind = WidgetSet
name = widgets
replicas = 2
image = nginx:1.25-alpine
