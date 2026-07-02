-- ============================================================================
-- LIVE DATA SEED + END-TO-END TEST
-- Run: snow sql --filename tests/e2e_test.sql
-- Prerequisites:
--   1. snow app run
--   2. snow sql --query "GRANT APPLICATION ROLE FINDATA_APP.APP_ADMIN TO ROLE ACCOUNTADMIN;"
-- ============================================================================

-- ============================================================================
-- PHASE 1: SEED LIVE DATA (via app procedure — avoids versioned schema DML issue)
-- ============================================================================
CALL FINDATA_APP.CORE.LOAD_SAMPLE_DATA();

SELECT '=== DATA SEED COMPLETE ===' AS STATUS,
    (SELECT COUNT(*) FROM FINDATA_APP.CORE.MARKET_PRICES) AS PRICES,
    (SELECT COUNT(*) FROM FINDATA_APP.CORE.COMPANY_FUNDAMENTALS) AS FUNDAMENTALS,
    (SELECT COUNT(*) FROM FINDATA_APP.CORE.RISK_METRICS) AS RISK_METRICS,
    (SELECT COUNT(*) FROM FINDATA_APP.CORE.BENCHMARK_RETURNS) AS BENCHMARKS;

-- ============================================================================
-- PHASE 2: END-TO-END TESTS
-- ============================================================================

-- E2E-1: Health check should now pass
CALL FINDATA_APP.CORE.HEALTH_CHECK();

-- E2E-2: Latest prices view returns all 5 symbols
SELECT 'E2E_LATEST_PRICES' AS TEST,
    CASE WHEN COUNT(*) = 5 THEN 'PASS' ELSE 'FAIL: got ' || COUNT(*) END AS RESULT
FROM FINDATA_APP.CORE.V_LATEST_PRICES;

-- E2E-3: Price history view has 50 rows
SELECT 'E2E_PRICE_HISTORY' AS TEST,
    CASE WHEN COUNT(*) = 50 THEN 'PASS' ELSE 'FAIL: got ' || COUNT(*) END AS RESULT
FROM FINDATA_APP.CORE.V_PRICE_HISTORY;

-- E2E-4: Company overview returns latest quarter for all companies
SELECT 'E2E_COMPANY_OVERVIEW' AS TEST,
    CASE WHEN COUNT(*) = 5 THEN 'PASS' ELSE 'FAIL: got ' || COUNT(*) END AS RESULT
FROM FINDATA_APP.CORE.V_COMPANY_OVERVIEW;

-- E2E-5: Sector summary (2 sectors: Technology + Financials)
SELECT 'E2E_SECTOR_SUMMARY' AS TEST,
    CASE WHEN COUNT(*) = 2 THEN 'PASS' ELSE 'FAIL: got ' || COUNT(*) END AS RESULT
FROM FINDATA_APP.CORE.V_SECTOR_SUMMARY;

-- E2E-6: Risk dashboard returns all 5 symbols with sector data
SELECT 'E2E_RISK_DASHBOARD' AS TEST,
    CASE WHEN COUNT(*) = 5 AND MIN(SECTOR) IS NOT NULL
        THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM FINDATA_APP.CORE.V_RISK_DASHBOARD;

-- E2E-7: Sector risk aggregation
SELECT 'E2E_SECTOR_RISK' AS TEST,
    CASE WHEN COUNT(*) = 2 THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM FINDATA_APP.CORE.V_SECTOR_RISK;

-- E2E-8: High risk alerts (NVDA volatility 0.38 > 0.3 = HIGH)
SELECT 'E2E_HIGH_RISK_ALERTS' AS TEST,
    CASE WHEN COUNT(*) >= 1 AND MAX(SYMBOL) = 'NVDA'
        THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM FINDATA_APP.CORE.V_HIGH_RISK_ALERTS
WHERE RISK_LEVEL IN ('EXTREME', 'HIGH');

-- E2E-9: Calculate returns for AAPL
CALL FINDATA_APP.ANALYTICS.CALC_RETURNS('AAPL', '2026-06-18', '2026-07-01');

SELECT 'E2E_CALC_RETURNS' AS TEST,
    CASE WHEN COUNT(*) = 10 THEN 'PASS' ELSE 'FAIL: got ' || COUNT(*) END AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- E2E-10: Correlation between AAPL and MSFT
CALL FINDATA_APP.ANALYTICS.CALC_CORRELATION('AAPL', 'MSFT', 30);

SELECT 'E2E_CORRELATION' AS TEST,
    CASE WHEN $1 BETWEEN -1 AND 1 THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- E2E-11: Stock screener (market cap > $1T, PE < 40)
CALL FINDATA_APP.ANALYTICS.STOCK_SCREENER(1000000000000, 40, NULL);

SELECT 'E2E_STOCK_SCREENER' AS TEST,
    CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL: got ' || COUNT(*) END AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- E2E-12: Stock screener with sector filter (Financials only)
CALL FINDATA_APP.ANALYTICS.STOCK_SCREENER(0, 100, 'Financials');

SELECT 'E2E_SCREENER_SECTOR' AS TEST,
    CASE WHEN COUNT(*) = 1 AND MAX(SYMBOL) = 'JPM'
        THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- E2E-13: Portfolio risk summary for 3 symbols
CALL FINDATA_APP.ANALYTICS.PORTFOLIO_RISK_SUMMARY(ARRAY_CONSTRUCT('AAPL', 'MSFT', 'NVDA'));

SELECT 'E2E_PORTFOLIO_RISK' AS TEST,
    CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL: got ' || COUNT(*) END AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- E2E-14: Config get/set roundtrip
CALL FINDATA_APP.CORE.SET_CONFIG('DATA_TIER', 'PREMIUM');
CALL FINDATA_APP.CORE.GET_CONFIG('DATA_TIER');

SELECT 'E2E_CONFIG_ROUNDTRIP' AS TEST,
    CASE WHEN $1 = 'PREMIUM' THEN 'PASS' ELSE 'FAIL: got ' || $1 END AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Reset config
CALL FINDATA_APP.CORE.SET_CONFIG('DATA_TIER', 'STANDARD');

-- E2E-15: Audit log records operations
CALL FINDATA_APP.CORE.VIEW_AUDIT_LOG(10);

SELECT 'E2E_AUDIT_LOG' AS TEST,
    CASE WHEN COUNT(*) >= 2 THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- E2E-16: Final health check (should be OK)
CALL FINDATA_APP.CORE.HEALTH_CHECK();

-- ============================================================================
-- SUMMARY
-- ============================================================================
SELECT '=== ALL E2E TESTS COMPLETE ===' AS STATUS;
