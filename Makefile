.PHONY: generate test verify validate

generate:
	PYTHONDONTWRITEBYTECODE=1 python3 scripts/generate-workflows.py

test: generate
	PYTHONDONTWRITEBYTECODE=1 python3 tests/test_bundle.py
	bash -n scripts/download-model.sh scripts/start.sh

verify:
	PYTHONDONTWRITEBYTECODE=1 python3 tests/verify_upstream.py

validate: test verify

