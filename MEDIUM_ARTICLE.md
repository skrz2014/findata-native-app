# I Shipped a Snowflake Native App in a Day. Here's Every Wall I Hit.

---

## Title Options

1. I Shipped a Snowflake Native App in a Day. Here's Every Wall I Hit.
2. The 7 Things Snowflake's Native App Docs Don't Tell You (But Deployment Will)
3. From Empty Folder to Marketplace-Ready: Building a Financial Data Native App
4. Versioned Schemas Nearly Broke My Native App — And 6 Other Surprises
5. What Actually Happens When You `snow app run` Against Production

---

## Hero Image Concept

**Visual:** Dark navy background (#0D1B2A) with a stylized terminal window showing `snow app run` output — the successful "Application FINDATA_APP created successfully" line highlighted in Snowflake cyan (#29B5E8). Behind the terminal, faded architectural boxes representing the app's schema structure. An amber (#F59E0B) warning icon floats near one of the boxes, hinting at the "gotchas" theme.

**Text on image:** "I Shipped a Snowflake Native App in a Day. Here's Every Wall I Hit." in clean sans-serif, high contrast.

---

## Inline Visual Recommendations

1. **After "The First Deploy" section:** Screenshot of actual `snow app run` terminal output showing the file diff and successful upgrade message
2. **After "Versioned Schemas Own Everything" section:** Annotated Snowsight screenshot showing the INFORMATION_SCHEMA.TABLES query proving objects exist in the CORE schema
3. **After "The Test Suite That Saved Us" section:** Screenshot of the 16/16 E2E test results in terminal

---

## Article

---

I spent a full day building a Snowflake Native App from scratch — a financial data platform with market prices, risk analytics, and a Streamlit dashboard. The docs made it look straightforward. The actual deployment taught me seven lessons that would have saved hours if someone had written them down.

This is that write-up. I'm sharing the exact project structure, the exact errors, and the exact fixes. Not the happy path — the real one.

**What this covers:** Building, deploying, and testing a production-grade Native App using Snow CLI and `manifest_version: 2`. **What it doesn't:** Marketplace listing creation, monetization configuration, or cross-cloud auto-fulfillment setup. Those are separate workflows once the app itself is solid.

### TL;DR

- Versioned schemas are owned by the app itself — external roles (even ACCOUNTADMIN) cannot INSERT directly. All writes must go through internal procedures.
- `manifest_version: 2` changes everything about debugging and privilege management. The migration from v1 isn't documented well.
- Snow CLI 3.19's Python connector chokes on `NUMBER(p,s)` return types. Use `FLOAT` and `BIGINT` or your test harness will crash before assertions run.
- Secure views have stricter query plan constraints than regular views. Nested correlated subqueries that work fine in normal views will throw cryptic "Error in secure object" failures.
- The edit-deploy-test loop with `snow app run` + SQL test files takes under 15 seconds end-to-end. Once it works, iteration is genuinely fast.

---

## Why I Picked the Native App Framework

I had financial data — market prices, company fundamentals, pre-computed risk metrics — and I needed to get it into customer environments without building API infrastructure. The usual options were S3 exports (stale on arrival) or a hosted REST layer (expensive to maintain, compliance headaches).

Native Apps offered something different: ship the data *and* the analytics logic as one installable unit. Customers get a Streamlit dashboard, stored procedures for portfolio analysis, and secure views over the data. They run it on their own warehouse. I don't manage infrastructure. The part that convinced me was versioned schemas — I can push new versions and consumers keep their existing data intact.

### What the Framework Actually Gives You

For anyone unfamiliar: the **Snowflake Native App Framework** (GA on all supported cloud platforms) lets you bundle data with business logic — Streamlit UIs, stored procedures, Snowpark functions — and distribute the whole thing as a single installable application through the Snowflake Marketplace or private listings. Free or paid, your choice.

What sold me beyond the data-sharing angle was the developer experience. You work locally with your preferred tools and source control, test from a single account without needing a separate consumer environment, then ship versioned releases with patches. Consumers upgrade automatically (or on your release schedule). Structured event logging means you can actually debug issues in production without asking consumers to run diagnostics.

It's not just "share a table." It's share a table, the logic that transforms it, the UI that visualizes it, and the versioning system that keeps it all evolving — inside the consumer's governance perimeter.

The framework is GA. Everything in this article uses generally available features. Snow CLI 3.19+, `manifest_version: 2`, warehouse-runtime Streamlit.

---

## The First Deploy — And the First Three Errors

My initial `snowflake.yml` had `src: .` for artifacts, mapping the entire project directory. Snow CLI refused with `Unacceptable pattern: PosixPath('.')`. Not a helpful error message — it took me a few minutes to realize you need explicit paths for each artifact group.

I also had `debug: true` in the application entity definition, which is what the older tutorials show. With `manifest_version: 2`, this throws: *"Cannot use debug mode on an application when manifest version is 2 or above."* You're supposed to use session debugging now (`SYSTEM$BEGIN_DEBUG_APPLICATION`). The fix is simply removing the line.

The working `snowflake.yml` uses explicit artifact mappings and skips the debug flag entirely:

```yaml
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
```

Once these were fixed, `snow app run` succeeded on the first try. The app installed in about 8 seconds.

---

## Versioned Schemas Own Everything

This was the most consequential lesson. I created `CORE` as a versioned schema (`CREATE OR ALTER VERSIONED SCHEMA CORE`) because I wanted upgrade-safe data persistence. What I didn't fully understand: the app *owns* those tables. Not the consumer. Not ACCOUNTADMIN. The app.

When I tried to seed test data with a direct INSERT, Snowflake returned: *"Insufficient privileges to operate on table 'MARKET_PRICES'."* I was running as ACCOUNTADMIN. Didn't matter.

The correct pattern is wrapping all data operations in procedures that live inside the app. The procedure runs in the app's context and has write access:

```sql
CREATE OR REPLACE PROCEDURE CORE.LOAD_SAMPLE_DATA()
RETURNS STRING
LANGUAGE SQL
AS
BEGIN
    DELETE FROM CORE.MARKET_PRICES;
    INSERT INTO CORE.MARKET_PRICES
        (SYMBOL, EXCHANGE, TRADE_DATE, CLOSE_PRICE, ADJ_CLOSE, VOLUME)
    VALUES
        ('AAPL', 'NASDAQ', '2026-07-01', 198.50, 198.50, 54100000),
        ('MSFT', 'NASDAQ', '2026-07-01', 450.90, 450.90, 24300000);
    RETURN 'Data loaded';
END;
```

This isn't just a testing concern. In production, your data ingestion pipeline — whether it's shared content from the provider or a scheduled task — must operate through app-internal procedures. External consumers interact through views and read-only interfaces.

---

## Secure Views Are Pickier Than You Think

I had a `V_COMPANY_OVERVIEW` view that worked perfectly as a regular view during development. The moment I made it secure (required for Native Apps — all consumer-facing views must be secure), it crashed with *"Error in secure object."*

The culprit was a nested correlated subquery — two levels deep, referencing the outer table at both levels. Regular views handle this fine. Secure views apparently have stricter optimizer constraints, and the query plan that Snowflake generates under secure mode can't handle certain correlation patterns.

The broken version looked like this:

```sql
WHERE (cf.FISCAL_YEAR, cf.FISCAL_QUARTER) = (
    SELECT MAX(FISCAL_YEAR), MAX(FISCAL_QUARTER)
    FROM table WHERE SYMBOL = cf.SYMBOL AND FISCAL_YEAR = (
        SELECT MAX(FISCAL_YEAR) FROM table WHERE SYMBOL = cf.SYMBOL
    )
)
```

I replaced it with a pre-aggregated JOIN, which secure views handle without issue:

```sql
INNER JOIN (
    SELECT SYMBOL, MAX(FISCAL_YEAR * 10 + FISCAL_QUARTER) AS MAX_YQ
    FROM CORE.COMPANY_FUNDAMENTALS
    GROUP BY SYMBOL
) latest ON cf.SYMBOL = latest.SYMBOL
    AND (cf.FISCAL_YEAR * 10 + cf.FISCAL_QUARTER) = latest.MAX_YQ
```

My rule now: in secure views, avoid correlated subqueries entirely. Pre-aggregate, then JOIN.

---

## Snow CLI's NUMBER Parsing Problem

This one wasted 30 minutes because the error looked like a data issue, not a tooling bug. When I called a stored procedure that returned `NUMBER(20,2)` columns through `snow sql`, the CLI crashed:

```
Failed to convert: field MARKET_CAP: FIXED::3320000000000.00
Error: invalid literal for int() with base 10: '3320000000000.00'
```

The Python connector inside Snow CLI 3.19 attempts to convert Snowflake's `NUMBER` type to Python `int`. When the number has decimal places (even `.00`), the conversion fails. This only happens when consuming results through the CLI — Snowsight handles it fine.

The fix is declaring all procedure return types as `FLOAT` or `BIGINT` instead of `NUMBER`:

```sql
RETURNS TABLE(
    SYMBOL VARCHAR,
    MARKET_CAP BIGINT,
    PE_RATIO FLOAT,
    VOLATILITY_30D FLOAT
)
```

And casting inside the SELECT to match:

```sql
SELECT
    cf.SYMBOL,
    cf.MARKET_CAP::BIGINT AS MARKET_CAP,
    cf.PE_RATIO::FLOAT AS PE_RATIO
```

One additional gotcha: if you declare `RETURNS TABLE(... DAILY_RETURN FLOAT)` but the SELECT computes a division that produces `NUMBER`, Snowflake throws *"data type of returned table does not match expected returned table type."* You need explicit `::FLOAT` casts on every computed expression, not just the column references.

---

## The Test Suite That Saved Us

I wrote tests in pure SQL — no external framework, no Python, no pytest. Just `.sql` files that `snow sql --filename` can execute directly. Three tiers:

**Install tests** validate that all objects exist after a fresh `snow app run`. Tables, views, procedures, the Streamlit app, default config values — eight assertions total.

**Permission tests** verify role isolation. `APP_VIEWER` can read market data but not risk analytics. `APP_ANALYST` can run procedures but not modify config. `APP_ADMIN` gets everything. These caught a missing GRANT early.

**End-to-end tests** seed data through `CORE.LOAD_SAMPLE_DATA()`, then exercise every view and procedure with concrete assertions. Sixteen tests covering returns calculation, correlation, stock screening, portfolio risk, config roundtrips, and audit logging.

The entire suite runs in one command and takes about 25 seconds:

```bash
snow sql --filename tests/e2e_test.sql
```

Having this made the iterative fixing process fast. Every time I changed a procedure's return type or rewrote a view, I'd run the full suite. Edit, `snow app run`, test. Under 30 seconds total. That tight loop is what made it possible to find and fix seven issues in a single day.

---

## What I'd Do Differently

**Start with `manifest_version: 2` from day one.** I initially read older tutorials that used v1 patterns. The migration isn't just changing a number — it affects how privileges work, how debugging works, and how the CLI interacts with your app. Don't mix signals from old blog posts.

**The versioned schema behavior is the single most important concept to understand before writing any code.** It dictates your entire data access architecture. If I'd internalized "the app owns its schemas, consumers interact only through procedures and views" at the start, I'd have saved three of my seven issues.

**Use FLOAT for all procedure return types from the beginning.** Even if your underlying tables use `NUMBER(18,6)`, declare the procedure interface as `FLOAT`. You'll avoid both the CLI parsing bug and the return-type mismatch error. This is a Snow CLI-specific workaround, not a general Snowflake best practice — but if you're using Snow CLI for testing (and you should be), it matters.

One limitation the docs don't emphasize: **`EXECUTE IMMEDIATE FROM` paths are relative to the stage root, not the manifest location.** This is obvious in retrospect, but I initially tried relative paths from the setup script's directory and got confusing "file not found" errors.

---

## Wrapping Up

The Native App Framework is mature enough for production. The dev loop is fast, the testing story is clean, and `snow app run` genuinely makes iterating pleasant. But the gap between the documentation's happy path and actual deployment is real — seven issues in one build session is a lot of friction that could be avoided with better error messages and more explicit documentation about versioned schema ownership.

The full source code — 18 files, all tested and passing — is available for reference. If you're starting a Native App build, clone it and rip out the financial domain logic. The structure, the testing pattern, and the CI/CD pipeline are reusable regardless of what data you're packaging.

---

*This article represents the author's personal views and experience, not those of any employer.*

---

👏 Give it a clap if it added value
🔗 Share it with your team
➕ Follow for more
📘 Medium: @SnowflakeChronicles
🔗 LinkedIn: satishkumar-snowflake

See you in the next one! 👋
