.PHONY: build test test-ci coverage fmt fmt-check lint snapshot slither audit

build:
	forge build

test:
	forge test

test-ci:
	FOUNDRY_PROFILE=ci forge test

coverage:
	forge coverage --ir-minimum --report summary --report lcov

fmt:
	forge fmt

fmt-check:
	forge fmt --check

lint:
	forge lint

snapshot:
	forge snapshot

slither:
	slither . --config-file slither.config.json

audit:
	forge test --match-path 'test/exploits/*' -vvv
