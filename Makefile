# Output-repo Makefile — one-time setup + smoke shortcuts.
#
# After cloning the repo, run `make setup` once to:
#   - point git at the in-tree pre-push hook (.githooks/pre-push) so the
#     leak-check workflow's catches are also enforced locally before any
#     push reaches GitHub.
#   - verify the prerequisites (`node`, `npm`, `gh`) are installed.
#
# Smoke targets wrap the most common commands you'd run during a release
# cycle (thin shell wrappers — copy-paste the command if you lack make).

.PHONY: setup smoke-cli test-fixture-drift help

help:
	@echo "Output-repo make targets:"
	@echo "  make setup               One-time clone setup (hook + prereqs)."
	@echo "  make smoke-cli           Run scripts/smoke_cli.sh (CLI build + assertions)."
	@echo "  make test-fixture-drift  Run scripts/test_fixture_drift.sh (fixture branch sync check)."

setup:
	@echo "==> Setting git core.hooksPath to .githooks"
	@git config core.hooksPath .githooks
	@echo "    leak-check pre-push hook enabled."
	@echo ""
	@echo "==> Verifying prerequisites"
	@command -v node >/dev/null 2>&1 || { echo "    [missing] node"; exit 2; }
	@echo "    node:  $$(node --version)"
	@command -v npm  >/dev/null 2>&1 || { echo "    [missing] npm";  exit 2; }
	@echo "    npm:   $$(npm --version)"
	@command -v gh   >/dev/null 2>&1 || { echo "    [missing] gh (GitHub CLI) — needed for monitor scripts + release workflows"; exit 2; }
	@echo "    gh:    $$(gh --version | head -1)"
	@echo ""
	@echo "==> Setup complete."

smoke-cli:
	bash scripts/smoke_cli.sh


test-fixture-drift:
	bash scripts/test_fixture_drift.sh
