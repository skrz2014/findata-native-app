-- ============================================================================
-- UNIT TEST: Analytics Logic Validation
-- Tests individual procedures with known inputs/outputs
-- ============================================================================

-- Setup: Insert known test data
INSERT INTO FINDATA_APP.CORE.MARKET_PRICES
    (SYMBOL, EXCHANGE, TRADE_DATE, OPEN_PRICE, HIGH_PRICE, LOW_PRICE, CLOSE_PRICE, ADJ_CLOSE, VOLUME)
VALUES
    ('UNIT1', 'NYSE', '2026-01-02', 100.00, 105.00, 99.00, 102.00, 102.00, 1000000),
    ('UNIT1', 'NYSE', '2026-01-03', 102.00, 108.00, 101.00, 106.00, 106.00, 1200000),
    ('UNIT1', 'NYSE', '2026-01-06', 106.00, 110.00, 104.00, 108.00, 108.00, 900000),
    ('UNIT1', 'NYSE', '2026-01-07', 108.00, 109.00, 100.00, 101.00, 101.00, 1500000),
    ('UNIT1', 'NYSE', '2026-01-08', 101.00, 103.00, 98.00, 100.00, 100.00, 1100000),
    ('UNIT2', 'NYSE', '2026-01-02', 50.00, 52.00, 49.00, 51.00, 51.00, 500000),
    ('UNIT2', 'NYSE', '2026-01-03', 51.00, 54.00, 50.00, 53.00, 53.00, 600000),
    ('UNIT2', 'NYSE', '2026-01-06', 53.00, 55.00, 52.00, 54.00, 54.00, 450000),
    ('UNIT2', 'NYSE', '2026-01-07', 54.00, 55.00, 50.00, 50.50, 50.50, 700000),
    ('UNIT2', 'NYSE', '2026-01-08', 50.50, 51.00, 48.00, 49.00, 49.00, 550000);

INSERT INTO FINDATA_APP.CORE.COMPANY_FUNDAMENTALS
    (COMPANY_ID, SYMBOL, COMPANY_NAME, FISCAL_YEAR, FISCAL_QUARTER, REVENUE, NET_INCOME, EPS, PE_RATIO, MARKET_CAP, SECTOR, INDUSTRY)
VALUES
    ('UNIT1_ID', 'UNIT1', 'Unit Test Corp A', 2026, 1, 5000000000, 800000000, 3.50, 22.5, 100000000000, 'Technology', 'Software'),
    ('UNIT2_ID', 'UNIT2', 'Unit Test Corp B', 2026, 1, 2000000000, 300000000, 1.20, 35.0, 40000000000, 'Healthcare', 'Biotech');

INSERT INTO FINDATA_APP.CORE.RISK_METRICS
    (SYMBOL, CALC_DATE, VOLATILITY_30D, VOLATILITY_90D, SHARPE_RATIO, BETA, VAR_95, MAX_DRAWDOWN, SORTINO_RATIO)
VALUES
    ('UNIT1', '2026-01-08', 0.25, 0.22, 1.5, 1.1, -0.03, -0.07, 1.8),
    ('UNIT2', '2026-01-08', 0.18, 0.15, 0.9, 0.8, -0.02, -0.05, 1.1);

-- ============================================================================
-- T1: CALC_RETURNS returns correct values
-- ============================================================================
SELECT 'T1_CALC_RETURNS' AS TEST,
    CASE WHEN ABS(DAILY_RETURN - 0.0392) < 0.01 THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE TRADE_DATE = '2026-01-03';

-- Calling the actual procedure
CALL FINDATA_APP.ANALYTICS.CALC_RETURNS('UNIT1', '2026-01-02', '2026-01-08');

-- ============================================================================
-- T2: STOCK_SCREENER filters correctly
-- ============================================================================
-- Should return UNIT1 (market cap 100B > 50B, PE 22.5 < 30)
CALL FINDATA_APP.ANALYTICS.STOCK_SCREENER(50000000000, 30, NULL);
SELECT 'T2_SCREENER_FILTER' AS TEST,
    CASE WHEN COUNT(*) = 1 AND MAX(SYMBOL) = 'UNIT1' THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- ============================================================================
-- T3: STOCK_SCREENER with sector filter
-- ============================================================================
CALL FINDATA_APP.ANALYTICS.STOCK_SCREENER(0, 100, 'Technology');
SELECT 'T3_SCREENER_SECTOR' AS TEST,
    CASE WHEN COUNT(*) = 1 AND MAX(SYMBOL) = 'UNIT1' THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- ============================================================================
-- T4: PORTFOLIO_RISK_SUMMARY returns expected symbols
-- ============================================================================
CALL FINDATA_APP.ANALYTICS.PORTFOLIO_RISK_SUMMARY(ARRAY_CONSTRUCT('UNIT1', 'UNIT2'));
SELECT 'T4_PORTFOLIO_RISK' AS TEST,
    CASE WHEN COUNT(*) = 2 THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- ============================================================================
-- T5: CONFIG procedures work correctly
-- ============================================================================
CALL FINDATA_APP.CORE.SET_CONFIG('UNIT_TEST_KEY', 'test_value');
CALL FINDATA_APP.CORE.GET_CONFIG('UNIT_TEST_KEY');
SELECT 'T5_CONFIG_ROUNDTRIP' AS TEST,
    CASE WHEN $1 = 'test_value' THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- ============================================================================
-- T6: Views return correct data
-- ============================================================================
SELECT 'T6_LATEST_PRICES_VIEW' AS TEST,
    CASE WHEN COUNT(*) = 2 THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM FINDATA_APP.CORE.V_LATEST_PRICES
WHERE SYMBOL IN ('UNIT1', 'UNIT2');

-- ============================================================================
-- T7: Risk dashboard view joins correctly
-- ============================================================================
SELECT 'T7_RISK_DASHBOARD_VIEW' AS TEST,
    CASE WHEN COUNT(*) = 2 AND MAX(SECTOR) IS NOT NULL THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM FINDATA_APP.CORE.V_RISK_DASHBOARD
WHERE SYMBOL IN ('UNIT1', 'UNIT2');

-- ============================================================================
-- T8: Correlation calculation
-- ============================================================================
CALL FINDATA_APP.ANALYTICS.CALC_CORRELATION('UNIT1', 'UNIT2', 365);
SELECT 'T8_CORRELATION' AS TEST,
    CASE WHEN $1 IS NOT NULL AND $1 BETWEEN -1 AND 1 THEN 'PASS' ELSE 'FAIL' END AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- ============================================================================
-- Cleanup
-- ============================================================================
DELETE FROM FINDATA_APP.CORE.MARKET_PRICES WHERE SYMBOL IN ('UNIT1', 'UNIT2');
DELETE FROM FINDATA_APP.CORE.COMPANY_FUNDAMENTALS WHERE SYMBOL IN ('UNIT1', 'UNIT2');
DELETE FROM FINDATA_APP.CORE.RISK_METRICS WHERE SYMBOL IN ('UNIT1', 'UNIT2');
DELETE FROM FINDATA_APP.CONFIG.APP_SETTINGS WHERE SETTING_KEY = 'UNIT_TEST_KEY';
DELETE FROM FINDATA_APP.ANALYTICS.CORRELATION_CACHE WHERE SYMBOL_A IN ('UNIT1', 'UNIT2');
