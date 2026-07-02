#!/bin/bash
# ============================================================================
# CI Test Runner for FinData Native App
# Deploys the app and runs all test suites via Snow CLI
# ============================================================================

set -euo pipefail

APP_NAME="FINDATA_APP"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$PROJECT_DIR/tests"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

run_sql_test() {
    local test_file="$1"
    local test_name="$(basename "$test_file" .sql)"
    
    log_info "Running test: $test_name"
    
    if snow sql --filename "$test_file" --format json 2>/dev/null; then
        log_info "  ✓ $test_name passed"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        log_error "  ✗ $test_name FAILED"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ============================================================================
# PHASE 1: Deploy the app
# ============================================================================
log_info "=========================================="
log_info "Phase 1: Deploying app via Snow CLI"
log_info "=========================================="

cd "$PROJECT_DIR"

log_info "Running: snow app run"
if snow app run --no-interactive 2>&1; then
    log_info "App deployed successfully"
else
    log_error "App deployment failed!"
    exit 1
fi

# ============================================================================
# PHASE 2: Run Integration Tests
# ============================================================================
log_info "=========================================="
log_info "Phase 2: Integration Tests"
log_info "=========================================="

for test_file in "$TEST_DIR"/integration/test_*.sql; do
    if [ -f "$test_file" ]; then
        run_sql_test "$test_file"
    fi
done

# ============================================================================
# PHASE 3: Run Unit Tests
# ============================================================================
log_info "=========================================="
log_info "Phase 3: Unit Tests"
log_info "=========================================="

for test_file in "$TEST_DIR"/unit/test_*.sql; do
    if [ -f "$test_file" ]; then
        run_sql_test "$test_file"
    fi
done

# ============================================================================
# PHASE 4: Summary
# ============================================================================
log_info "=========================================="
log_info "Test Summary"
log_info "=========================================="
echo ""
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo "  Total:  $((PASS_COUNT + FAIL_COUNT))"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
    log_error "Some tests failed!"
    exit 1
else
    log_info "All tests passed!"
    exit 0
fi
