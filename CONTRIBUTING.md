# Contributing

Thanks for contributing to **bash-mastery-devops**. This repo follows one strict
convention so every day stays consistent and equally weighted.

## The "day contract"

Every `days/dayNN/` folder has the **same shape**:

```
days/dayNN/
├── README.md      # the lesson (beautified, same structure as every other day)
├── scripts/       # that day's runnable script(s)
└── tests/         # a BATS suite that verifies the scripts
```

- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Shared helpers live in `/lib` — never copy a logger or retry loop into a day.
- Every script must be reachable from a BATS test. Trivial scripts get a
  smoke/output assertion; scripts with logic get full branch coverage.

## Local checks

```bash
# style + lint (installed via pre-commit)
pre-commit install

# run one day's gate on only that day's changed files
pre-commit run --files days/day01/scripts/*.sh days/day01/tests/*.bats

# run a day's tests
bats days/day01/tests
```

`pre-commit run --all-files` is reserved for the final pass once all days ship.
CI (`.github/workflows/ci.yml`) runs shfmt + shellcheck + all BATS on every push.
