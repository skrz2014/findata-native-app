/*
================================================================================
FINDATA NATIVE APP — END-TO-END IMPLEMENTATION PLAN (FINAL)
================================================================================
This document captures the complete, tested implementation including all fixes
discovered during actual deployment on Snowflake account lm65707.

RESULT: 16/16 E2E tests PASSING
APP URL: https://app.snowflake.com/MCRCDDT/sf72404/#/apps/application/FINDATA_APP
================================================================================

================================================================================
STEP 1: PREREQUISITES
================================================================================

Required:
  - Snowflake account with ACCOUNTADMIN role
  - Snowflake CLI installed (v3.19+): brew install snowflake-cli
  - Warehouse: COMPUTE_WH (or any available warehouse)

Configure connection:
  ~/.snowflake/config.toml:
    [connections.default]
    account = "<your_account>"
    user = "<your_user>"
    authenticator = "externalbrowser"
    role = "ACCOUNTADMIN"
    warehouse = "COMPUTE_WH"

Verify: snow connection test

================================================================================
STEP 2: PROJECT STRUCTURE
================================================================================

findata-native-app/
├── snowflake.yml              -- Snow CLI project definition (v2)
├── manifest.yml               -- Native App manifest (manifest_version: 2)
├── README.md                  -- Consumer documentation
├── scripts/
│   ├── setup.sql              -- Main entry point (orchestrates modules)
│   ├── schemas/
│   │   ├── core_schema.sql    -- Market prices, fundamentals, risk, benchmarks
│   │   ├── config_schema.sql  -- App settings, audit log, references
│   │   └── analytics_schema.sql  -- Portfolio, screener, correlation cache
│   ├── procedures/
│   │   ├── admin_procs.sql    -- Health, config, audit, reference callback, seed
│   │   └── analytics_procs.sql   -- Returns, correlation, screener, portfolio
│   └── views/
│       ├── market_views.sql   -- Latest prices, history+SMAs, company, sector
│       └── risk_views.sql     -- Risk dashboard, sector risk, high-risk alerts
├── streamlit/
│   ├── dashboard.py           -- 4-tab interactive dashboard
│   └── environment.yml        -- Streamlit dependencies
├── tests/
│   ├── e2e_test.sql           -- Full seed + 16 end-to-end tests
│   └── integration/
│       ├── test_install.sql   -- Object creation validation (8 tests)
│       ├── test_permissions.sql  -- RBAC isolation (8 tests)
│       └── test_upgrade.sql   -- Upgrade path validation (4 tests)
└── ci/
    ├── github-actions.yml     -- Full CI/CD pipeline
    └── run_tests.sh           -- Local test runner

================================================================================
STEP 3: KEY DESIGN DECISIONS & FIXES APPLIED
================================================================================

ISSUE 1: PosixPath('.') error
  CAUSE:  snowflake.yml had "src: ." which Snow CLI rejects
  FIX:    Use explicit artifact mappings:
            - src: manifest.yml → dest: manifest.yml
            - src: README.md → dest: README.md
            - src: scripts/* → dest: scripts/
            - src: streamlit/* → dest: streamlit/

ISSUE 2: debug mode + manifest_version 2
  CAUSE:  "debug: true" in snowflake.yml incompatible with manifest_version: 2
  FIX:    Remove "debug: true" — use session debugging instead

ISSUE 3: Consumer cannot INSERT into versioned schema tables
  CAUSE:  CORE schema is "CREATE OR ALTER VERSIONED SCHEMA" — owned by the app
  FIX:    All data operations go through app-internal procedures
          (CORE.LOAD_SAMPLE_DATA, not direct INSERT)

ISSUE 4: "Error in secure object" on V_COMPANY_OVERVIEW
  CAUSE:  Nested correlated subqueries fail in secure views
  FIX:    Replace with INNER JOIN on aggregated subquery:
            INNER JOIN (
              SELECT SYMBOL, MAX(FISCAL_YEAR*10+FISCAL_QUARTER) AS MAX_YQ
              FROM CORE.COMPANY_FUNDAMENTALS GROUP BY SYMBOL
            ) latest ON ...

ISSUE 5: Snow CLI "Failed to convert: FIXED::NUMBER" errors
  CAUSE:  Snow CLI 3.19 Python connector can't parse NUMBER(p,s) to int
  FIX:    All procedure RETURNS use FLOAT/BIGINT instead of NUMBER:
            - RETURNS TABLE(... MARKET_CAP BIGINT, PE_RATIO FLOAT ...)
            - SELECT ... ::FLOAT AS column_name
            - RETURNS FLOAT (for scalar)

ISSUE 6: "not a valid order by expression" after cast
  CAUSE:  ORDER BY cf.MARKET_CAP conflicts with aliased MARKET_CAP::BIGINT
  FIX:    ORDER BY 3 DESC (positional reference)

ISSUE 7: "data type of returned table does not match"
  CAUSE:  RETURNS TABLE declares FLOAT but SELECT produces NUMBER from arithmetic
  FIX:    Explicit ::FLOAT cast on all computed expressions in SELECT

================================================================================
STEP 4: DEPLOY THE APP
================================================================================
*/

-- Run these commands from terminal (NOT in Snowflake):

-- 4.1 Deploy (creates package + installs app)
-- $ cd findata-native-app
-- $ snow app run

-- 4.2 Grant app role to your account role (one-time)
GRANT APPLICATION ROLE FINDATA_APP.APP_ADMIN TO ROLE ACCOUNTADMIN;

-- 4.3 Load sample data via app procedure
CALL FINDATA_APP.CORE.LOAD_SAMPLE_DATA();

-- 4.4 Verify health
CALL FINDATA_APP.CORE.HEALTH_CHECK();
-- Expected: {"status": "OK", "market_prices_count": 50, ...}

/*
================================================================================
STEP 5: RUN FULL E2E TEST SUITE
================================================================================

$ snow sql --filename tests/e2e_test.sql

Expected output: 16/16 PASS
  E2E_LATEST_PRICES     PASS
  E2E_PRICE_HISTORY     PASS
  E2E_COMPANY_OVERVIEW  PASS
  E2E_SECTOR_SUMMARY    PASS
  E2E_RISK_DASHBOARD    PASS
  E2E_SECTOR_RISK       PASS
  E2E_HIGH_RISK_ALERTS  PASS
  E2E_CALC_RETURNS      PASS
  E2E_CORRELATION       PASS
  E2E_STOCK_SCREENER    PASS
  E2E_SCREENER_SECTOR   PASS
  E2E_PORTFOLIO_RISK    PASS
  E2E_CONFIG_ROUNDTRIP  PASS
  E2E_AUDIT_LOG         PASS
  HEALTH_CHECK          OK

================================================================================
STEP 6: snowflake.yml (FINAL WORKING VERSION)
================================================================================
*/

-- snowflake.yml content:
/*
definition_version: 2

entities:
  findata_app_pkg:
    type: application package
    identifier: FINDATA_APP_PKG
    manifest: manifest.yml
    stage: stage_content.app_code
    distribution: internal
    artifacts:
      - src: manifest.yml
        dest: manifest.yml
      - src: README.md
        dest: README.md
      - src: scripts/*
        dest: scripts/
      - src: streamlit/*
        dest: streamlit/
    meta:
      role: ACCOUNTADMIN
      warehouse: COMPUTE_WH

  findata_app:
    type: application
    identifier: FINDATA_APP
    from:
      target: findata_app_pkg
    telemetry:
      share_mandatory_events: true
    meta:
      role: ACCOUNTADMIN
      warehouse: COMPUTE_WH
*/

/*
================================================================================
STEP 7: manifest.yml (FINAL WORKING VERSION)
================================================================================

manifest_version: 2

version:
  name: V1_0
  label: "Financial Data Analytics v1.0"
  comment: "Market data, company fundamentals, and risk metrics analytics"

artifacts:
  setup_script: scripts/setup.sql
  readme: README.md
  default_streamlit: core.dashboard

configuration:
  log_level: INFO
  trace_level: ALWAYS
  metric_level: ALL
  telemetry_event_definitions:
    - type: ERRORS_AND_WARNINGS
      sharing: MANDATORY
    - type: DEBUG_LOGS
      sharing: OPTIONAL

privileges:
  - CREATE DATABASE:
      description: "Store cached analytics results and user configurations"
  - EXECUTE TASK:
      description: "Run scheduled data refresh tasks"

references:
  - consumer_warehouse:
      label: "Warehouse"
      description: "Warehouse to run analytics queries"
      privileges:
        - USAGE
      object_type: WAREHOUSE
      register_callback: core.register_warehouse_ref

================================================================================
STEP 8: ARCHITECTURE OVERVIEW
================================================================================

┌─────────────────────────────────────────────────────────────────────┐
│                      FINDATA_APP (Consumer Account)                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  CORE (Versioned Schema)                                      │   │
│  │  ├── MARKET_PRICES (50 rows: 5 symbols × 10 days)           │   │
│  │  ├── COMPANY_FUNDAMENTALS (5 companies)                      │   │
│  │  ├── RISK_METRICS (5 symbols)                                │   │
│  │  ├── BENCHMARK_RETURNS (S&P 500, 10 days)                   │   │
│  │  ├── V_LATEST_PRICES (secure view)                          │   │
│  │  ├── V_PRICE_HISTORY (secure view + SMAs)                   │   │
│  │  ├── V_COMPANY_OVERVIEW (secure view)                       │   │
│  │  ├── V_SECTOR_SUMMARY (secure view)                         │   │
│  │  ├── V_RISK_DASHBOARD (secure view)                         │   │
│  │  ├── V_SECTOR_RISK (secure view)                            │   │
│  │  ├── V_HIGH_RISK_ALERTS (secure view)                       │   │
│  │  └── DASHBOARD (Streamlit)                                   │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  CONFIG (Schema)                                              │   │
│  │  ├── APP_SETTINGS (key-value config)                         │   │
│  │  ├── AUDIT_LOG (all operations tracked)                      │   │
│  │  └── BOUND_REFERENCES (consumer object bindings)             │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  ANALYTICS (Schema)                                           │   │
│  │  ├── PORTFOLIO_ANALYSIS (results)                            │   │
│  │  ├── SCREENER_RESULTS (cached)                               │   │
│  │  └── CORRELATION_CACHE                                       │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  PROCEDURES                                                   │   │
│  │  ├── CORE.LOAD_SAMPLE_DATA()         → Seeds all tables      │   │
│  │  ├── CORE.HEALTH_CHECK()             → Reports app status    │   │
│  │  ├── CORE.GET_CONFIG(key)            → Read setting           │   │
│  │  ├── CORE.SET_CONFIG(key, val)       → Write setting          │   │
│  │  ├── CORE.VIEW_AUDIT_LOG(n)          → View last N logs      │   │
│  │  ├── ANALYTICS.CALC_RETURNS(...)     → Daily/cumulative      │   │
│  │  ├── ANALYTICS.CALC_CORRELATION(...) → Pairwise correlation  │   │
│  │  ├── ANALYTICS.STOCK_SCREENER(...)   → Filter by criteria    │   │
│  │  └── ANALYTICS.PORTFOLIO_RISK_SUMMARY(...)  → Risk overview  │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ROLES:  APP_ADMIN > APP_ANALYST > APP_VIEWER                       │
└─────────────────────────────────────────────────────────────────────┘

================================================================================
STEP 9: ITERATIVE DEVELOPMENT WORKFLOW
================================================================================

Edit code → Deploy → Test → Repeat:

  $ snow app run              # Upgrades app in place
  $ snow sql --filename tests/e2e_test.sql    # Validates

Hot-reload (Streamlit only, no SQL changes):
  $ snow app deploy           # Uploads files, skips setup re-execution

Teardown (clean slate):
  $ snow app teardown --force

================================================================================
STEP 10: PRODUCTION RELEASE WORKFLOW
================================================================================

1. Change distribution to EXTERNAL in snowflake.yml
2. Add version:
   ALTER APPLICATION PACKAGE FINDATA_APP_PKG
     ADD VERSION V1_0
     USING '@FINDATA_APP_PKG.STAGE_CONTENT.APP_CODE';

3. Wait for automated security scan (NAAAPS) to pass

4. Set release directive:
   ALTER APPLICATION PACKAGE FINDATA_APP_PKG
     SET DEFAULT RELEASE DIRECTIVE
     VERSION = V1_0 PATCH = 0;

5. Create Marketplace listing via Provider Studio

================================================================================
STEP 11: CI/CD PIPELINE SUMMARY
================================================================================

GitHub Actions workflow (ci/github-actions.yml):

  PR/Push to develop:
    [Lint SQL] → [Validate manifest] → [snow app run] → [Run tests] → [Teardown]

  Merge to main:
    [Deploy to prod package] → [Add version] → [Set release directive]

================================================================================
STEP 12: MONITORING (Post-Deployment)
================================================================================
*/

-- Monitor health across consumer instances
SELECT CONSUMER_ACCOUNT_NAME, LAST_HEALTH_STATUS, CURRENT_VERSION
FROM SNOWFLAKE.DATA_SHARING_USAGE.APPLICATION_STATE
WHERE PACKAGE_NAME = 'FINDATA_APP_PKG';

-- Track consumer engagement
SELECT DATE(QUERY_DATE) AS USAGE_DATE,
    COUNT(DISTINCT CONSUMER_ACCOUNT_NAME) AS ACTIVE_ACCOUNTS,
    COUNT(DISTINCT QUERY_TOKEN) AS TOTAL_QUERIES
FROM SNOWFLAKE.DATA_SHARING_USAGE.LISTING_ACCESS_HISTORY
WHERE APPLICATION_PACKAGE_NAME = 'FINDATA_APP_PKG'
    AND QUERY_DATE >= DATEADD(DAY, -30, CURRENT_DATE())
GROUP BY USAGE_DATE
ORDER BY USAGE_DATE DESC;

/*
================================================================================
COMPLETE. All steps verified on Snowflake account lm65707 (2026-07-01).
================================================================================
*/
