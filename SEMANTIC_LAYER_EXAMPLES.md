# dbt Semantic Layer — Example Queries

## Prerequisites

`dbt sl` reads from a deployment job's artifacts for the project's environment, not from local/dev runs. Before any of these will work:

1. Confirm the deployment environment in dbt Cloud (**Deploy → Environments**).
2. Create a job for that environment if none exists (e.g. a "Build" job running `dbt build`).
3. Run that job successfully at least once.
4. Confirm the Semantic Layer is enabled/configured for the environment (**Account settings → Semantic Layer**).

You can validate your semantic model / metrics YAML compiles without any of the above:

```bash
dbt parse
```

## Discovery

```bash
dbt sl list metrics
dbt sl list dimensions --metrics order_total
```

## Example queries

```bash
# 1. Sanity check — simplest possible metric, no grouping
dbt sl query --metrics order_total

# 2. Simple metric grouped by a categorical dimension on the same semantic model
dbt sl query --metrics order_total --group-by is_food_order

# 3. Cross-semantic-model join — orders metric grouped by a customer dimension
dbt sl query --metrics order_total,customers --group-by customer__customer_type

# 4. Time series — exercises the project's time spine
dbt sl query --metrics order_total --group-by metric_time__day --order-by metric_time__day --limit 10

# 5. A metric with a built-in filter (Dimension() syntax)
dbt sl query --metrics large_order --group-by metric_time__month

# 6. Another filtered metric, traversing to the customer semantic model
dbt sl query --metrics new_customer --group-by metric_time__month

# 7. Percentile aggregation
dbt sl query --metrics order_value_p99 --group-by metric_time__month

# 8. Ratio metric (numerator/denominator)
dbt sl query --metrics food_order_pct --group-by metric_time__month

# 9. Derived metric (expr combining other metrics)
dbt sl query --metrics food_order_pct_cumulative --group-by metric_time__month

# 10. Cumulative metric with a trailing window
dbt sl query --metrics cumulative_order_ammount_l1m --group-by metric_time__day --order-by metric_time__day --limit 10

# 11. Multiple unrelated metrics in one query (tests metric-set join logic)
dbt sl query --metrics order_total,order_amount,order_cost --group-by metric_time__month
```

Skip `food_order_gross_profit` — it references a nonexistent `product` entity in `fct_orders.yml` and will error. Useful only if you want to see that specific validation failure.

## Exporting results

Query output is a normal tabular dataset. Export to CSV directly:

```bash
dbt sl query --metrics order_total --group-by metric_time__day --csv output.csv
```

## Clients that can query the semantic layer

- **dbt Cloud CLI / dbt Core** — `dbt sl query`, used above
- **JDBC/ODBC driver** — dbt Cloud exposes the Semantic Layer over JDBC/ODBC, so any BI tool with generic JDBC/ODBC support can connect
- **First-party BI integrations** — Tableau, Looker, Hex, Mode, Google Sheets, PowerBI (via JDBC connector)
- **GraphQL API** — for custom apps/dashboards
- **Python SDK** (`dbt-sl-client` / semantic-layer-fetch) — programmatic/notebook access
- **Spreadsheets** — Google Sheets integration for direct analyst pull

## Why use the semantic layer instead of raw SQL

1. **One definition, many consumers** — a metric like `order_total` is defined once (aggregation + joins + filters). Every tool gets the identical number, instead of every analyst/BI tool re-writing and drifting on its own `SUM(...)` logic.
2. **No join/grain bugs** — requesting `order_total` grouped by `customer__customer_type` lets MetricFlow resolve the correct join through the `customer` foreign entity and aggregate at the right grain first, avoiding fan-out double-counting that raw SQL joins are prone to.
3. **Reusable filters/derived logic** — metrics like `large_order`, `food_order_pct`, `cumulative_order_amount` encapsulate business logic (thresholds, ratios, window functions) behind a stable name instead of copy-pasted `CASE WHEN`/window functions.
4. **Governance** — metric definitions, descriptions, and ownership live in version-controlled YAML in this repo, not scattered across dashboards.
5. **Consistent time handling** — `metric_time` grain/granularity (day/week/month rollups) is handled uniformly instead of every query hand-rolling `DATE_TRUNC`.

Tradeoff: it's an extra abstraction layer with real setup cost. For a one-off analysis, plain SQL is still faster — it pays off when the same metrics need to stay consistent across many dashboards/tools.

## Querying in natural language — the dbt MCP Server

`dbt sl` itself only takes structured `--metrics`/`--group-by` flags — there's no NL query mode in the CLI. To ask questions in plain English, you put an LLM in front of the semantic layer instead of writing SQL or CLI flags yourself.

**dbt Labs' MCP (Model Context Protocol) server** is the direct fit for this, especially since you're already working inside an MCP-capable client (Claude Code):

- It exposes your project's dbt resources — including semantic layer metrics/dimensions — as tools an LLM can call directly, instead of the LLM guessing at SQL.
- Practical effect: you ask "what's total order revenue by customer type last month", and the LLM resolves that to a real call equivalent to `dbt sl query --metrics order_total --group-by customer__customer_type` using your actual metric and dimension names from `models/metrics/*.yml`.
- Because the LLM can only request metrics/dimensions that exist in your governed YAML, this preserves the same "one definition, many consumers" guarantee — it can't invent a `SUM(order_total)` that skips your defined joins/filters.
- Setup is a config-only step (adding an MCP server entry pointing at your dbt Cloud project/credentials) — no code changes to this repo required. Given the account/job configuration friction we've already hit (environment `468362`, no successful deploy job yet), the MCP server has the same hard prerequisite: it can only serve metrics for an environment that already has a working semantic manifest, so it's blocked on the same fix (see Prerequisites above) before it'll return real answers.

Once the deploy job prerequisite is resolved, this becomes the fastest way to demo the semantic layer's value to a non-technical stakeholder: same governed metric, asked in English, answered without touching SQL.
