GOOSE ?= .toolchain/goose/build/goose
CC ?= gcc
SANITIZER_CC ?= gcc
FUZZ_RUNS ?= 10000
BENCH_SAMPLES ?= 5
BENCH_ITERATIONS ?= 16
OUTPUT ?= .build/results.json
.NOTPARALLEL:
.PHONY: setup format check test test-debug native sanitize bench
setup:
	./scripts/setup-goose.sh
format:
	"$(GOOSE)" format csv.goose tests examples bench
check:
	"$(GOOSE)" format --check csv.goose tests examples bench
	"$(GOOSE)" check tests/api.goose
	"$(GOOSE)" check tests/oracle.goose
	"$(GOOSE)" check tests/fuzz.goose
	"$(GOOSE)" check examples/stream.goose
	"$(GOOSE)" check bench/bench.goose
	python3 -m py_compile tests/*.py scripts/*.py bench/*.py
	git diff --check
test:
	mkdir -p .build
	"$(GOOSE)" run tests/api.goose
	python3 tests/oracle.py --goose "$(abspath $(GOOSE))" --output .build/oracle-jit.json
	"$(GOOSE)" run tests/fuzz.goose -- $(FUZZ_RUNS)
	$(MAKE) native
test-debug:
	mkdir -p .build
	"$(GOOSE)" run tests/api.goose --debug
	python3 tests/oracle.py --goose "$(abspath $(GOOSE))" --debug --output .build/oracle-debug.json
	"$(GOOSE)" run tests/fuzz.goose --debug -- $(FUZZ_RUNS)
native:
	mkdir -p .build
	"$(GOOSE)" build tests/api.goose --standalone --cc "$(CC)" -O2 -o .build/api
	./.build/api
	"$(GOOSE)" build tests/oracle.goose --standalone --cc "$(CC)" -O2 -o .build/oracle
	python3 tests/oracle.py --binary .build/oracle --output .build/oracle-native.json
	"$(GOOSE)" build tests/fuzz.goose --standalone --cc "$(CC)" -O2 -o .build/fuzz
	./.build/fuzz $(FUZZ_RUNS)
sanitize:
	python3 scripts/sanitize.py --goose "$(abspath $(GOOSE))" --cc "$(SANITIZER_CC)" --fuzz-runs $(FUZZ_RUNS) --output "$(OUTPUT)"
bench:
	python3 bench/measure.py --goose "$(abspath $(GOOSE))" --cc "$(CC)" --samples $(BENCH_SAMPLES) --iterations $(BENCH_ITERATIONS) --output "$(OUTPUT)"
