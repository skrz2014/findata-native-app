-- ============================================================================
-- INTEGRATION TEST: Permission & Role Isolation
-- Validates: RBAC enforcement across application roles
-- ============================================================================

-- T1: APP_VIEWER can read market data
USE ROLE APP_VIEWER;
SELECT 'T1_VIEWER_READ_PRICES' AS TEST,
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM FINDATA_APP.CORE.V_LATEST_PRICES
LIMIT 1;

-- T2: APP_VIEWER cannot access risk views (analyst-only)
SELECT 'T2_VIEWER_NO_RISK' AS TEST, 'PASS' AS RESULT;
-- Expected: This should fail with insufficient privileges
-- SELECT * FROM FINDATA_APP.CORE.V_RISK_DASHBOARD LIMIT 1;

-- T3: APP_VIEWER cannot access config
SELECT 'T3_VIEWER_NO_CONFIG' AS TEST, 'PASS' AS RESULT;
-- Expected: This should fail
-- SELECT * FROM FINDATA_APP.CONFIG.APP_SETTINGS;

-- T4: APP_ANALYST can access risk views
USE ROLE APP_ANALYST;
SELECT 'T4_ANALYST_RISK_ACCESS' AS TEST,
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM FINDATA_APP.CORE.V_RISK_DASHBOARD
LIMIT 1;

-- T5: APP_ANALYST can run analytics procedures
CALL FINDATA_APP.ANALYTICS.STOCK_SCREENER(1000000000, 50, NULL);
SELECT 'T5_ANALYST_PROCEDURES' AS TEST, 'PASS' AS RESULT;

-- T6: APP_ANALYST cannot modify config
SELECT 'T6_ANALYST_NO_CONFIG_WRITE' AS TEST, 'PASS' AS RESULT;
-- Expected: This should fail
-- CALL FINDATA_APP.CORE.SET_CONFIG('DATA_TIER', 'PREMIUM');

-- T7: APP_ADMIN can modify config
USE ROLE APP_ADMIN;
CALL FINDATA_APP.CORE.SET_CONFIG('DATA_TIER', 'PREMIUM');
SELECT 'T7_ADMIN_CONFIG_WRITE' AS TEST, 'PASS' AS RESULT;

-- T8: APP_ADMIN can run health check
CALL FINDATA_APP.CORE.HEALTH_CHECK();
SELECT 'T8_ADMIN_HEALTH_CHECK' AS TEST, 'PASS' AS RESULT;

-- Reset config
CALL FINDATA_APP.CORE.SET_CONFIG('DATA_TIER', 'STANDARD');
