#!/bin/bash
# Validation script for P0 fixes
# Run after each fix to ensure no regressions

set -e  # Exit on error

echo "🔍 Validating P0 Fixes..."
echo ""

cd "$(dirname "$0")/../cairo" || exit 1

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Gate 1: Specific failing tests should now pass
echo -e "${YELLOW}✅ Gate 1: Refund tests${NC}"
if snforge test test_refund_returns_exact_amount --exact 2>&1 | grep -q "PASS"; then
    echo -e "${GREEN}✓ test_refund_returns_exact_amount passes${NC}"
else
    echo -e "${RED}✗ test_refund_returns_exact_amount still failing${NC}"
    exit 1
fi

if snforge test test_refund_fails_with_insufficient_balance --exact 2>&1 | grep -q "PASS"; then
    echo -e "${GREEN}✓ test_refund_fails_with_insufficient_balance passes${NC}"
else
    echo -e "${RED}✗ test_refund_fails_with_insufficient_balance still failing${NC}"
    exit 1
fi

# Gate 2: No regressions in critical tests
echo ""
echo -e "${YELLOW}✅ Gate 2: No regressions in critical tests${NC}"
if snforge test test_e2e_dleq --exact 2>&1 | grep -q "PASS"; then
    echo -e "${GREEN}✓ test_e2e_dleq still passes${NC}"
else
    echo -e "${RED}✗ test_e2e_dleq regressed!${NC}"
    exit 1
fi

if snforge test test_security_audit --exact 2>&1 | grep -q "PASS"; then
    echo -e "${GREEN}✓ test_security_audit still passes${NC}"
else
    echo -e "${RED}✗ test_security_audit regressed!${NC}"
    exit 1
fi

# Gate 3: Contract still builds
echo ""
echo -e "${YELLOW}✅ Gate 3: Contract builds${NC}"
if scarb build > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Contract builds successfully${NC}"
else
    echo -e "${RED}✗ Contract build failed!${NC}"
    scarb build
    exit 1
fi

# Gate 4: Check test count improvement
echo ""
echo -e "${YELLOW}✅ Gate 4: Test count check${NC}"
TEST_OUTPUT=$(snforge test 2>&1)
PASS_COUNT=$(echo "$TEST_OUTPUT" | grep -c "PASS" || echo "0")
FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep -c "FAIL" || echo "0")

echo "  Passing: $PASS_COUNT"
echo "  Failing: $FAIL_COUNT"

if [ "$PASS_COUNT" -lt 80 ]; then
    echo -e "${RED}✗ Too few tests passing! Expected >= 80${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ All validation gates passed!${NC}"
echo ""
echo "Summary:"
echo "  - Refund tests: ✅ Fixed"
echo "  - Critical tests: ✅ No regressions"
echo "  - Contract build: ✅ Success"
echo "  - Test count: ✅ $PASS_COUNT passing"

