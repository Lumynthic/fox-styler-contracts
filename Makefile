.PHONY: deps static fmt build test fuzz gate clean

deps:
	./tools/bootstrap_dependencies.sh

static:
	python3 tools/static_checks.py

fmt:
	forge fmt --check

build:
	forge build --sizes

test:
	forge test -vvv

fuzz:
	forge test --fuzz-runs 10000

gate:
	./tools/run_quality_gate.sh

clean:
	forge clean
