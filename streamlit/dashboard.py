import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="FinData Analytics", page_icon="📊", layout="wide")

session = get_active_session()


def get_setting(key):
    result = session.sql(f"CALL CORE.GET_CONFIG('{key}')").collect()
    return result[0][0] if result else None


def main():
    st.title("Financial Data Analytics")
    st.markdown("Real-time market data, fundamentals, and risk analytics")

    tab1, tab2, tab3, tab4 = st.tabs(
        ["Market Overview", "Risk Dashboard", "Stock Screener", "Settings"]
    )

    with tab1:
        render_market_overview()

    with tab2:
        render_risk_dashboard()

    with tab3:
        render_stock_screener()

    with tab4:
        render_settings()


def render_market_overview():
    st.header("Market Overview")

    col1, col2, col3 = st.columns(3)

    stats = session.sql("""
        SELECT
            COUNT(DISTINCT SYMBOL) AS total_symbols,
            MAX(TRADE_DATE) AS latest_date,
            COUNT(*) AS total_records
        FROM CORE.MARKET_PRICES
    """).collect()

    if stats and stats[0]["TOTAL_SYMBOLS"]:
        col1.metric("Symbols Tracked", f"{stats[0]['TOTAL_SYMBOLS']:,}")
        col2.metric("Latest Data", str(stats[0]["LATEST_DATE"]))
        col3.metric("Total Records", f"{stats[0]['TOTAL_RECORDS']:,}")

    st.subheader("Sector Summary")
    sector_df = session.sql("SELECT * FROM CORE.V_SECTOR_SUMMARY ORDER BY TOTAL_MARKET_CAP DESC").to_pandas()
    if not sector_df.empty:
        st.dataframe(sector_df, use_container_width=True)

    st.subheader("Latest Prices")
    symbol_input = st.text_input("Filter by symbol (comma-separated)", "AAPL,MSFT,GOOGL")
    if symbol_input:
        symbols = [s.strip().upper() for s in symbol_input.split(",")]
        symbol_filter = ",".join([f"'{s}'" for s in symbols])
        prices_df = session.sql(f"""
            SELECT * FROM CORE.V_LATEST_PRICES
            WHERE SYMBOL IN ({symbol_filter})
            ORDER BY SYMBOL
        """).to_pandas()
        if not prices_df.empty:
            st.dataframe(prices_df, use_container_width=True)
        else:
            st.info("No data found for the selected symbols.")


def render_risk_dashboard():
    st.header("Risk Dashboard")

    risk_df = session.sql("SELECT * FROM CORE.V_RISK_DASHBOARD ORDER BY VOLATILITY_30D DESC LIMIT 50").to_pandas()

    if not risk_df.empty:
        col1, col2 = st.columns(2)
        with col1:
            st.subheader("Highest Volatility")
            st.dataframe(
                risk_df[["SYMBOL", "VOLATILITY_30D", "BETA", "SHARPE_RATIO"]].head(10),
                use_container_width=True,
            )
        with col2:
            st.subheader("Sector Risk")
            sector_risk_df = session.sql("SELECT * FROM CORE.V_SECTOR_RISK ORDER BY AVG_VOLATILITY_30D DESC").to_pandas()
            if not sector_risk_df.empty:
                st.dataframe(sector_risk_df, use_container_width=True)

        st.subheader("High Risk Alerts")
        alerts_df = session.sql("SELECT * FROM CORE.V_HIGH_RISK_ALERTS ORDER BY VOLATILITY_30D DESC LIMIT 20").to_pandas()
        if not alerts_df.empty:
            st.dataframe(alerts_df, use_container_width=True)
    else:
        st.info("No risk data available. Data will appear after the first refresh cycle.")


def render_stock_screener():
    st.header("Stock Screener")

    col1, col2, col3 = st.columns(3)
    with col1:
        min_market_cap = st.number_input("Min Market Cap ($B)", min_value=0.0, value=10.0, step=1.0)
    with col2:
        max_pe = st.number_input("Max P/E Ratio", min_value=0.0, value=30.0, step=1.0)
    with col3:
        sectors = session.sql("SELECT DISTINCT SECTOR FROM CORE.COMPANY_FUNDAMENTALS WHERE SECTOR IS NOT NULL ORDER BY SECTOR").to_pandas()
        sector_list = ["All"] + sectors["SECTOR"].tolist() if not sectors.empty else ["All"]
        sector = st.selectbox("Sector", sector_list)

    if st.button("Run Screener"):
        sector_param = "NULL" if sector == "All" else f"'{sector}'"
        results = session.sql(f"""
            CALL ANALYTICS.STOCK_SCREENER({min_market_cap * 1e9}, {max_pe}, {sector_param})
        """).to_pandas()
        if not results.empty:
            st.success(f"Found {len(results)} matching stocks")
            st.dataframe(results, use_container_width=True)
        else:
            st.warning("No stocks match the selected criteria.")


def render_settings():
    st.header("App Settings")

    settings_df = session.sql("SELECT * FROM CONFIG.APP_SETTINGS ORDER BY SETTING_KEY").to_pandas()
    if not settings_df.empty:
        st.dataframe(settings_df, use_container_width=True)

    st.subheader("Health Check")
    if st.button("Run Health Check"):
        health = session.sql("CALL CORE.HEALTH_CHECK()").collect()
        if health:
            st.json(health[0][0])

    st.subheader("Audit Log")
    audit_df = session.sql("CALL CORE.VIEW_AUDIT_LOG(20)").to_pandas()
    if not audit_df.empty:
        st.dataframe(audit_df, use_container_width=True)


if __name__ == "__main__":
    main()
