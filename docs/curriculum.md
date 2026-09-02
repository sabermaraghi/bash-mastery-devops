# Curriculum — 30 Days to Principal

One concept per day. Every day ships a lesson (`README.md`), runnable
script(s), and a BATS suite. Pre-commit + BATS gate every day from Day 1.

## Phase 1 — Bash Foundations (1–5)
| Day | Topic |
|-----|-------|
| 01 | Shell basics & variables |
| 02 | Conditionals & test expressions |
| 03 | Loops |
| 04 | Functions & scope |
| 05 | Arguments & getopts |

## Phase 2 — Data, Files & Text (6–10)
| Day | Topic |
|-----|-------|
| 06 | File I/O & redirection |
| 07 | Text processing (grep/sed/awk) |
| 08 | Arrays & associative arrays |
| 09 | JSON & API integration |
| 10 | Environment variables & config |

## Phase 3 — Robust & Concurrent Scripting (11–15)
| Day | Topic |
|-----|-------|
| 11 | Error handling, logging & debugging |
| 12 | Process management & signals |
| 13 | Parallel & concurrent execution |
| 14 | Modular libraries |
| 15 | Unit testing with BATS |

## Phase 4 — Quality, Security & Performance (16–20)
| Day | Topic |
|-----|-------|
| 16 | Pre-commit hooks & linting |
| 17 | Security fundamentals |
| 18 | Zero-trust security pipeline |
| 19 | Performance optimization |
| 20 | Unix tooling at scale |

## Phase 5 — DevOps Automation (21–25)
| Day | Topic |
|-----|-------|
| 21 | Capstone I: Distributed Log Analyzer Pro |
| 22 | Rootless containers (Buildah/Podman/Cosign) |
| 23 | Modular CI/CD framework |
| 24 | Git-driven auto-deploy (GitOps) |
| 25 | Kubernetes automation with kubectl |

## Phase 6 — Platform Engineering / Principal (26–30)
| Day | Topic |
|-----|-------|
| 26 | Kubernetes Operators & CRDs |
| 27 | ArgoCD App of Apps |
| 28 | Chaos Engineering |
| 29 | Self-Healing systems |
| 30 | Cost Optimization / FinOps |

## Capstone project — devops-platform

After Day 30, the platform days come together in one runnable, end-to-end
project under [`projects/devops-platform/`](../projects/devops-platform/README.md):
a GitOps-managed, self-healing, cost-observable platform on Kubernetes, operated
with the scripts built during the course. Each of Days 22–30 maps to a real
command:

| Day | Skill | Capstone command |
|-----|-------|------------------|
| 22 | Containers & images | backend/frontend `Dockerfile` |
| 23 | CI/CD | `.github/workflows/capstone.yml` |
| 24 | GitOps foundations | `gitops/` app-of-apps |
| 25 | kubectl plumbing | all real commands + `status` |
| 26 | Operators / reconcile | `capstone.sh operate` |
| 27 | ArgoCD | `capstone.sh up` / `deploy` |
| 28 | Chaos engineering | `capstone.sh chaos` |
| 29 | Self-healing | `capstone.sh heal` |
| 30 | Cost & FinOps | `capstone.sh cost` |

Provision with the default scripts (`capstone.sh up`, needs only
Docker + kind + kubectl) or optionally with Terraform. No Helm or Vagrant
required. An offline `capstone.sh validate` keeps the project CI-green with no
cluster.
