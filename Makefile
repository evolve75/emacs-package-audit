# Makefile for package-audit

# Emacs binary (can be overridden)
EMACS ?= emacs

# Batch mode command prefix
BATCH = $(EMACS) --batch -Q -L . -L test

# Source files
SRCS = package-audit.el \
       package-audit-core.el \
       package-audit-parse.el \
       package-audit-report.el \
       package-audit-remediate.el \
       package-audit-ui.el

# Test files
TESTS = test/package-audit-test.el \
        test/package-audit-parse-test.el \
        test/package-audit-core-test.el

# Compiled files
OBJS = $(SRCS:.el=.elc)
TEST_OBJS = $(TESTS:.el=.elc)

.PHONY: help test test-all test-parse test-core compile clean

help:
	@echo "Available targets:"
	@echo "  test              - Run all tests"
	@echo "  test-parse        - Run parsing tests only"
	@echo "  test-core         - Run core tests only"
	@echo "  compile           - Byte-compile all source files"
	@echo "  clean             - Remove compiled files"
	@echo "  help              - Show this help message"

test: test-all

test-all:
	@echo "Running all tests..."
	$(BATCH) \
		-l test/package-audit-test.el \
		-l test/package-audit-parse-test.el \
		-l test/package-audit-core-test.el \
		-f ert-run-tests-batch-and-exit

test-parse:
	@echo "Running parsing tests..."
	$(BATCH) \
		-l test/package-audit-test.el \
		-l test/package-audit-parse-test.el \
		-f ert-run-tests-batch-and-exit

test-core:
	@echo "Running core tests..."
	$(BATCH) \
		-l test/package-audit-test.el \
		-l test/package-audit-core-test.el \
		-f ert-run-tests-batch-and-exit

compile:
	@echo "Byte-compiling source files..."
	$(BATCH) \
		--eval "(setq byte-compile-error-on-warn t)" \
		-f batch-byte-compile $(SRCS)

clean:
	@echo "Removing compiled files..."
	rm -f $(OBJS) $(TEST_OBJS)
