# Makefile for package-audit
#
# Copyright (C) 2026  Anupam Sengupta
#
# Author: Anupam Sengupta <anupamsg@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This file is not part of GNU Emacs.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Emacs binary detection
# On macOS, prefer Emacs.app if available, otherwise fall back to CLI emacs
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    EMACS_APP := /Applications/Emacs.app/Contents/MacOS/Emacs
    ifneq ("$(wildcard $(EMACS_APP))","")
        EMACS ?= $(EMACS_APP)
    else
        EMACS ?= emacs
    endif
else
    EMACS ?= emacs
endif

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
        test/package-audit-core-test.el \
        test/package-audit-report-test.el \
        test/package-audit-remediate-test.el \
        test/package-audit-ui-test.el

# Compiled files
OBJS = $(SRCS:.el=.elc)
TEST_OBJS = $(TESTS:.el=.elc)

.PHONY: help test test-all test-parse test-core test-report test-remediate test-ui compile clean

# Default target
.DEFAULT_GOAL := help

help:
	@echo "Available targets:"
	@echo "  test              - Run all tests"
	@echo "  test-parse        - Run parsing tests only"
	@echo "  test-core         - Run core tests only"
	@echo "  test-report       - Run report tests only"
	@echo "  test-remediate    - Run remediation tests only"
	@echo "  test-ui           - Run UI tests only"
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
		-l test/package-audit-report-test.el \
		-l test/package-audit-remediate-test.el \
		-l test/package-audit-ui-test.el \
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

test-report:
	@echo "Running report tests..."
	$(BATCH) \
		-l test/package-audit-test.el \
		-l test/package-audit-report-test.el \
		-f ert-run-tests-batch-and-exit

test-remediate:
	@echo "Running remediation tests..."
	$(BATCH) \
		-l test/package-audit-test.el \
		-l test/package-audit-remediate-test.el \
		-f ert-run-tests-batch-and-exit

test-ui:
	@echo "Running UI tests..."
	$(BATCH) \
		-l test/package-audit-test.el \
		-l test/package-audit-ui-test.el \
		-f ert-run-tests-batch-and-exit

compile:
	@echo "Byte-compiling source files..."
	$(BATCH) \
		--eval "(setq byte-compile-error-on-warn t)" \
		-f batch-byte-compile $(SRCS)

clean:
	@echo "Removing compiled files..."
	rm -f $(OBJS) $(TEST_OBJS)
