# Financial Data Analytics - Snowflake Native App

A production-grade Snowflake Native App delivering real-time market data, company fundamentals, and risk analytics directly inside your Snowflake environment.

## Features

- **Market Data**: Daily OHLCV prices with moving averages (SMA 20/50/200)
- **Company Fundamentals**: Quarterly financials, P/E ratios, market cap
- **Risk Analytics**: Volatility, Beta, Sharpe Ratio, VaR, Max Drawdown
- **Stock Screener**: Filter stocks by market cap, P/E, sector
- **Portfolio Analysis**: Correlation matrices, portfolio risk summaries
- **Interactive Dashboard**: Streamlit-powered visual analytics

## Quick Start

1. After installation, grant the `APP_ADMIN` role to your admin user
2. Bind a warehouse via the app's configuration UI
3. Open the Streamlit dashboard from the app's UI

## Application Roles

| Role | Access Level |
|------|-------------|
| `APP_ADMIN` | Full management: config, health checks, audit logs |
| `APP_ANALYST` | Read data + run analytics procedures |
| `APP_VIEWER` | Read-only access to market data and views |

## Available Views

| View | Description | Minimum Role |
|------|-------------|-------------|
| `CORE.V_LATEST_PRICES` | Most recent prices per symbol | APP_VIEWER |
| `CORE.V_PRICE_HISTORY` | Full history with moving averages | APP_VIEWER |
| `CORE.V_COMPANY_OVERVIEW` | Latest quarter fundamentals | APP_VIEWER |
| `CORE.V_SECTOR_SUMMARY` | Sector-level aggregations | APP_VIEWER |
| `CORE.V_RISK_DASHBOARD` | Latest risk metrics | APP_ANALYST |
| `CORE.V_SECTOR_RISK` | Sector risk aggregation | APP_ANALYST |
| `CORE.V_HIGH_RISK_ALERTS` | High volatility alerts | APP_ANALYST |

## Available Procedures

| Procedure | Description |
|-----------|-------------|
| `ANALYTICS.CALC_RETURNS(symbol, start, end)` | Calculate daily/cumulative returns |
| `ANALYTICS.CALC_CORRELATION(sym_a, sym_b, days)` | Pairwise correlation |
| `ANALYTICS.STOCK_SCREENER(min_cap, max_pe, sector)` | Filter stocks |
| `ANALYTICS.PORTFOLIO_RISK_SUMMARY(symbols_array)` | Portfolio risk overview |
| `CORE.HEALTH_CHECK()` | App health status |
| `CORE.GET_CONFIG(key)` | Read configuration |
| `CORE.SET_CONFIG(key, value)` | Update configuration |

## Data Refresh

Data is refreshed by the provider pipeline. Refresh frequency depends on your subscription tier:
- **Standard**: Every 30 minutes during market hours
- **Premium**: Real-time (< 5 minute latency)

## Support

Contact your provider administrator for support inquiries.
