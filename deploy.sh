#!/bin/bash
# ============================================================================
# FinData Native App — One-Shot Deployment Script
# Run from the findata-native-app/ directory
# ============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================"
echo " FinData Native App — One-Shot Deploy"
echo "============================================"
echo ""

# Step 1: Verify Snow CLI connection
echo -n "Checking connection... "
if snow connection test --format json > /dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "Run: snow connection test — and fix your ~/.snowflake/config.toml"
    exit 1
fi

# Step 2: Deploy the app
echo ""
echo "Deploying app..."
snow app run --no-interactive
echo ""

# Step 3: Grant app role
echo "Granting APP_ADMIN role..."
snow sql --query "GRANT APPLICATION ROLE FINDATA_APP.APP_ADMIN TO ROLE ACCOUNTADMIN;" > /dev/null 2>&1
echo -e "${GREEN}Done${NC}"

# Step 4: Seed data
echo "Loading sample data..."
snow sql --query "CALL FINDATA_APP.CORE.LOAD_SAMPLE_DATA();" > /dev/null 2>&1
echo -e "${GREEN}Done${NC}"

# Step 5: Health check
echo ""
echo "Running health check..."
snow sql --query "CALL FINDATA_APP.CORE.HEALTH_CHECK();"

# Step 6: Run E2E tests
echo ""
echo "Running E2E test suite..."
snow sql --filename tests/e2e_test.sql

echo ""
echo "============================================"
echo -e " ${GREEN}DEPLOYMENT COMPLETE${NC}"
echo "============================================"
echo ""
echo "App URL: https://app.snowflake.com — search for FINDATA_APP"
echo ""
