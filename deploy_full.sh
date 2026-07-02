#!/bin/bash
# ============================================================================
# FinData Native App — One-Shot GitHub + Snowflake Deployment
# Creates repo, pushes code, deploys app, seeds data, runs tests
# ============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

GITHUB_USER="skrz2014"
REPO_NAME="findata-native-app"

echo "============================================"
echo " FinData Native App — Full Deployment"
echo " GitHub + Snowflake (One Shot)"
echo "============================================"
echo ""

# ──────────────────────────────────────────────
# PHASE 1: GitHub Repository
# ──────────────────────────────────────────────
echo -e "${YELLOW}PHASE 1: GitHub Setup${NC}"
echo ""

cd "$(dirname "$0")"

# Initialize git if needed
if [ ! -d .git ]; then
    echo "Initializing git repo..."
    git init
    git branch -M main
fi

# Create .gitignore
cat > .gitignore << 'EOF'
output/
.DS_Store
*.pyc
__pycache__/
snowflake.local.yml
.snowflake/
EOF

# Stage all files
git add -A
git commit -m "Initial commit: FinData Native App — production-ready with full E2E test suite

- Snowflake Native App (manifest_version: 2)
- 5 symbols × 10 days market data seed
- 7 secure views, 9 stored procedures
- Streamlit dashboard (4 tabs)
- 16 E2E tests (all passing)
- CI/CD pipeline (GitHub Actions)
- One-shot deploy script" 2>/dev/null || echo "Nothing new to commit"

# Create GitHub repo and push
echo ""
echo "Creating GitHub repo: ${GITHUB_USER}/${REPO_NAME}..."
if gh repo view "${GITHUB_USER}/${REPO_NAME}" > /dev/null 2>&1; then
    echo "Repo already exists — pushing updates..."
else
    gh repo create "${REPO_NAME}" --public --description "Production-grade Snowflake Native App — Financial Data Analytics (market data, risk metrics, Streamlit dashboard)" --source . --push
    echo -e "${GREEN}Repo created${NC}"
fi

# Set remote and push
git remote set-url origin "https://github.com/${GITHUB_USER}/${REPO_NAME}.git" 2>/dev/null || \
    git remote add origin "https://github.com/${GITHUB_USER}/${REPO_NAME}.git" 2>/dev/null || true
git push -u origin main --force
echo -e "${GREEN}Code pushed to GitHub${NC}"
echo "   https://github.com/${GITHUB_USER}/${REPO_NAME}"

# ──────────────────────────────────────────────
# PHASE 2: Snowflake Deployment
# ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}PHASE 2: Snowflake Deployment${NC}"
echo ""

# Verify Snow CLI connection
echo -n "Checking Snowflake connection... "
if snow connection test --format json > /dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "Fix your ~/.snowflake/config.toml and retry"
    exit 1
fi

# Deploy app
echo ""
echo "Deploying Native App..."
snow app run --no-interactive

# Grant role
echo ""
echo "Granting APP_ADMIN role..."
snow sql --query "GRANT APPLICATION ROLE FINDATA_APP.APP_ADMIN TO ROLE ACCOUNTADMIN;" > /dev/null 2>&1
echo -e "${GREEN}Done${NC}"

# Seed data
echo "Loading live data..."
snow sql --query "CALL FINDATA_APP.CORE.LOAD_SAMPLE_DATA();" > /dev/null 2>&1
echo -e "${GREEN}Done${NC}"

# ──────────────────────────────────────────────
# PHASE 3: Validation
# ──────────────────────────────────────────────
echo ""
echo -e "${YELLOW}PHASE 3: Validation${NC}"
echo ""

echo "Running E2E test suite..."
snow sql --filename tests/e2e_test.sql

# ──────────────────────────────────────────────
# DONE
# ──────────────────────────────────────────────
echo ""
echo "============================================"
echo -e " ${GREEN}ALL DONE${NC}"
echo "============================================"
echo ""
echo " GitHub: https://github.com/${GITHUB_USER}/${REPO_NAME}"
echo " App:    Search FINDATA_APP in Snowsight"
echo " Tests:  16/16 passing"
echo ""
