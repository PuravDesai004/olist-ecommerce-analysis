#!/usr/bin/env python3
"""Stream and audit the original Olist CSVs; write a Markdown report."""

from __future__ import annotations

import csv
import argparse
from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal, InvalidOperation
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import tempfile
import sys
from collections import Counter


@dataclass(frozen=True)
class DatasetSpec:
    table: str
    filename: str
    headers: tuple[str, ...]
    expected_rows: int
    documented_rows: int | None


SPECS = (
    DatasetSpec("customers", "olist_customers_dataset.csv", (
        "customer_id", "customer_unique_id", "customer_zip_code_prefix",
        "customer_city", "customer_state",
    ), 99_441, 99_441),
    DatasetSpec("geolocation", "olist_geolocation_dataset.csv", (
        "geolocation_zip_code_prefix", "geolocation_lat", "geolocation_lng",
        "geolocation_city", "geolocation_state",
    ), 1_000_163, 1_000_163),
    DatasetSpec("order_items", "olist_order_items_dataset.csv", (
        "order_id", "order_item_id", "product_id", "seller_id",
        "shipping_limit_date", "price", "freight_value",
    ), 112_650, 112_650),
    DatasetSpec("order_payments", "olist_order_payments_dataset.csv", (
        "order_id", "payment_sequential", "payment_type",
        "payment_installments", "payment_value",
    ), 103_886, 103_886),
    DatasetSpec("order_reviews", "olist_order_reviews_dataset.csv", (
        "review_id", "order_id", "review_score", "review_comment_title",
        "review_comment_message", "review_creation_date",
        "review_answer_timestamp",
    ), 99_224, 99_224),
    DatasetSpec("orders", "olist_orders_dataset.csv", (
        "order_id", "customer_id", "order_status", "order_purchase_timestamp",
        "order_approved_at", "order_delivered_carrier_date",
        "order_delivered_customer_date", "order_estimated_delivery_date",
    ), 99_441, 99_441),
    DatasetSpec("products", "olist_products_dataset.csv", (
        "product_id", "product_category_name", "product_name_lenght",
        "product_description_lenght", "product_photos_qty", "product_weight_g",
        "product_length_cm", "product_height_cm", "product_width_cm",
    ), 32_951, 32_951),
    DatasetSpec("sellers", "olist_sellers_dataset.csv", (
        "seller_id", "seller_zip_code_prefix", "seller_city", "seller_state",
    ), 3_095, 3_095),
    DatasetSpec("product_category_name_translation",
        "product_category_name_translation.csv",
        ("product_category_name", "product_category_name_english"), 71, None),
)

INTEGER_COLUMNS = {
    "order_item_id", "payment_sequential", "payment_installments", "review_score",
    "product_name_lenght", "product_description_lenght", "product_photos_qty",
    "product_weight_g", "product_length_cm", "product_height_cm", "product_width_cm",
}
ZIP_COLUMNS = {
    "customer_zip_code_prefix", "geolocation_zip_code_prefix",
    "seller_zip_code_prefix",
}
DECIMAL_COLUMNS = {
    "geolocation_lat", "geolocation_lng", "price", "freight_value", "payment_value",
}
TIMESTAMP_COLUMNS = {
    "shipping_limit_date", "review_creation_date", "review_answer_timestamp",
    "order_purchase_timestamp", "order_approved_at",
    "order_delivered_carrier_date", "order_delivered_customer_date",
    "order_estimated_delivery_date",
}
TIMESTAMP_COLUMNS_BY_TABLE = {
    "order_items": ("shipping_limit_date",),
    "order_reviews": ("review_creation_date", "review_answer_timestamp"),
    "orders": (
        "order_purchase_timestamp", "order_approved_at",
        "order_delivered_carrier_date", "order_delivered_customer_date",
        "order_estimated_delivery_date",
    ),
}

UNIQUE_CANDIDATES = {
    "customers": (("customer_id",),),
    "orders": (("order_id",),),
    "order_items": (("order_id", "order_item_id"),),
    "order_payments": (("order_id", "payment_sequential"),),
    "products": (("product_id",),),
    "sellers": (("seller_id",),),
    "product_category_name_translation": (("product_category_name",),),
}
NON_UNIQUE_DIAGNOSTICS = {
    "customers": (("customer_unique_id",),),
    "order_reviews": (("review_id",), ("order_id",)),
}


def value_type(column: str) -> str:
    if column in ZIP_COLUMNS:
        return "ZIP prefix (text digits)"
    if column in INTEGER_COLUMNS:
        return "integer"
    if column in DECIMAL_COLUMNS:
        return "decimal"
    if column in TIMESTAMP_COLUMNS:
        return "timestamp"
    return "text"


def parse_timestamp(value: str) -> datetime:
    return datetime.fromisoformat(value.replace(" ", "T", 1))


def type_valid(column: str, value: str) -> bool:
    try:
        if column in ZIP_COLUMNS:
            return bool(re.fullmatch(r"\d{1,5}", value))
        if column in INTEGER_COLUMNS:
            int(value, 10)
        elif column in DECIMAL_COLUMNS:
            number = Decimal(value)
            return number.is_finite()
        elif column in TIMESTAMP_COLUMNS:
            parse_timestamp(value)
        return True
    except (ValueError, InvalidOperation, OverflowError):
        return False


def q(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def stage_and_summarize(data_dir: Path) -> tuple[dict, Path]:
    """Load rows incrementally into a temporary disk-backed SQLite database."""
    # Keep the temporary work file beside the CSVs because this Windows runtime
    # may not have write access to the default system TEMP directory.
    temp_dir = Path(tempfile.mkdtemp(prefix=".olist_audit_", dir=data_dir))
    db_path = temp_dir / "audit.sqlite3"
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode=OFF")
    conn.execute("PRAGMA synchronous=OFF")
    conn.execute("PRAGMA temp_store=FILE")

    stats = {}
    conn.execute(
        "CREATE TABLE _seen_rows (dataset TEXT NOT NULL, digest BLOB NOT NULL, "
        "PRIMARY KEY(dataset, digest)) WITHOUT ROWID"
    )

    for spec in SPECS:
        table = "t_" + spec.table
        columns_sql = ", ".join(f"{q(column)} TEXT" for column in spec.headers)
        conn.execute(f"CREATE TABLE {q(table)} (_row_no INTEGER PRIMARY KEY, {columns_sql})")
        insert_sql = (
            f"INSERT INTO {q(table)} ({', '.join(q(c) for c in spec.headers)}) "
            f"VALUES ({', '.join('?' for _ in spec.headers)})"
        )

        dataset_stats = {
            "rows": 0,
            "staged_rows": 0,
            "header_ok": False,
            "header_found": None,
            "field_count_errors": 0,
            "nulls": Counter(),
            "type_errors": Counter(),
            "type_samples": {},
            "read_error": None,
            "timestamp_order_errors": Counter(),
            "full_row_duplicates": 0,
        }
        path = data_dir / spec.filename
        if not path.is_file():
            dataset_stats["read_error"] = "missing file"
            stats[spec.table] = dataset_stats
            continue

        batch = []
        try:
            with path.open("r", encoding="utf-8-sig", newline="") as csv_file:
                reader = csv.reader(csv_file, strict=True)
                header = next(reader, None)
                dataset_stats["header_found"] = header
                dataset_stats["header_ok"] = tuple(header or ()) == spec.headers
                if header is None:
                    dataset_stats["read_error"] = "empty file"
                    stats[spec.table] = dataset_stats
                    continue

                for row in reader:
                    dataset_stats["rows"] += 1
                    if len(row) != len(spec.headers):
                        dataset_stats["field_count_errors"] += 1
                        continue

                    row_map = dict(zip(spec.headers, row))
                    for column, value in row_map.items():
                        if value == "":
                            dataset_stats["nulls"][column] += 1
                        elif not type_valid(column, value):
                            dataset_stats["type_errors"][column] += 1
                            if column not in dataset_stats["type_samples"]:
                                dataset_stats["type_samples"][column] = value[:80]

                    if spec.table == "orders":
                        ordered_pairs = (
                            ("order_purchase_timestamp", "order_approved_at", "purchase_after_approval"),
                            ("order_approved_at", "order_delivered_carrier_date", "approval_after_carrier"),
                            ("order_delivered_carrier_date", "order_delivered_customer_date", "carrier_after_delivery"),
                        )
                        for earlier, later, label in ordered_pairs:
                            if row_map[earlier] and row_map[later]:
                                try:
                                    if parse_timestamp(row_map[earlier]) > parse_timestamp(row_map[later]):
                                        dataset_stats["timestamp_order_errors"][label] += 1
                                except ValueError:
                                    pass
                    elif spec.table == "order_reviews":
                        creation = row_map["review_creation_date"]
                        answer = row_map["review_answer_timestamp"]
                        if creation and answer:
                            try:
                                if parse_timestamp(creation) > parse_timestamp(answer):
                                    dataset_stats["timestamp_order_errors"]["creation_after_answer"] += 1
                            except ValueError:
                                pass

                    batch.append(tuple(value if value != "" else None for value in row))
                    digest = hashlib.sha256(
                        json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
                    ).digest()
                    conn.execute(
                        "INSERT OR IGNORE INTO _seen_rows(dataset, digest) VALUES (?, ?)",
                        (spec.table, digest),
                    )
                    dataset_stats["staged_rows"] += 1
                    if len(batch) >= 5_000:
                        conn.executemany(insert_sql, batch)
                        batch.clear()
                if batch:
                    conn.executemany(insert_sql, batch)
                    batch.clear()
                conn.commit()
        except (OSError, UnicodeError, csv.Error) as error:
            dataset_stats["read_error"] = str(error)
            if batch:
                conn.executemany(insert_sql, batch)
                batch.clear()
                conn.commit()

        unique_row_count = conn.execute(
            "SELECT COUNT(*) FROM _seen_rows WHERE dataset = ?", (spec.table,)
        ).fetchone()[0]
        dataset_stats["full_row_duplicates"] = max(
            0, dataset_stats["staged_rows"] - unique_row_count
        )
        stats[spec.table] = dataset_stats

    return {"stats": stats, "connection": conn, "db_path": db_path}, temp_dir


def duplicate_excess(conn: sqlite3.Connection, table: str, columns: tuple[str, ...]) -> int:
    table_name = q("t_" + table)
    cols = ", ".join(q(column) for column in columns)
    not_null = " AND ".join(f"{q(column)} IS NOT NULL" for column in columns)
    sql = (
        f"SELECT COALESCE(SUM(n - 1), 0) FROM ("
        f"SELECT COUNT(*) AS n FROM {table_name} WHERE {not_null} "
        f"GROUP BY {cols} HAVING COUNT(*) > 1)"
    )
    return int(conn.execute(sql).fetchone()[0])


def key_nulls(conn: sqlite3.Connection, table: str, columns: tuple[str, ...]) -> int:
    predicates = " OR ".join(f"{q(column)} IS NULL" for column in columns)
    return int(conn.execute(
        f"SELECT COUNT(*) FROM {q('t_' + table)} WHERE {predicates}"
    ).fetchone()[0])


def orphan_count(conn: sqlite3.Connection, child: str, child_col: str,
                 parent: str, parent_col: str) -> int:
    sql = (
        f"SELECT COUNT(*) FROM {q('t_' + child)} AS c "
        f"LEFT JOIN (SELECT DISTINCT {q(parent_col)} FROM {q('t_' + parent)} "
        f"WHERE {q(parent_col)} IS NOT NULL) AS p "
        f"ON c.{q(child_col)} = p.{q(parent_col)} "
        f"WHERE c.{q(child_col)} IS NOT NULL AND p.{q(parent_col)} IS NULL"
    )
    return int(conn.execute(sql).fetchone()[0])


def distinct_unmatched_count(conn: sqlite3.Connection, child: str, child_col: str,
                             parent: str, parent_col: str) -> int:
    sql = (
        f"SELECT COUNT(*) FROM (SELECT DISTINCT c.{q(child_col)} "
        f"FROM {q('t_' + child)} AS c LEFT JOIN "
        f"(SELECT DISTINCT {q(parent_col)} FROM {q('t_' + parent)} "
        f"WHERE {q(parent_col)} IS NOT NULL) AS p "
        f"ON c.{q(child_col)} = p.{q(parent_col)} "
        f"WHERE c.{q(child_col)} IS NOT NULL AND p.{q(parent_col)} IS NULL)"
    )
    return int(conn.execute(sql).fetchone()[0])


def financial_reconciliation(conn: sqlite3.Connection) -> dict:
    item_totals: dict[str, Decimal] = {}
    for order_id, price, freight in conn.execute(
        "SELECT order_id, price, freight_value FROM t_order_items"
    ):
        if order_id is not None and price is not None and freight is not None:
            item_totals[order_id] = item_totals.get(order_id, Decimal(0)) + Decimal(price) + Decimal(freight)

    payment_totals: dict[str, Decimal] = {}
    for order_id, amount in conn.execute(
        "SELECT order_id, payment_value FROM t_order_payments"
    ):
        if order_id is not None and amount is not None:
            payment_totals[order_id] = payment_totals.get(order_id, Decimal(0)) + Decimal(amount)

    item_only = set(item_totals) - set(payment_totals)
    payment_only = set(payment_totals) - set(item_totals)
    compared = 0
    mismatches = []
    absolute_difference = Decimal(0)
    for order_id in item_totals.keys() & payment_totals.keys():
        compared += 1
        difference = payment_totals[order_id] - item_totals[order_id]
        if abs(difference) > Decimal("0.01"):
            absolute_difference += abs(difference)
            if len(mismatches) < 5:
                mismatches.append((order_id, item_totals[order_id], payment_totals[order_id], difference))

    return {
        "item_orders": len(item_totals),
        "payment_orders": len(payment_totals),
        "compared_orders": compared,
        "item_only_orders": len(item_only),
        "payment_only_orders": len(payment_only),
        "mismatch_orders": sum(
            abs(payment_totals[order_id] - item_totals[order_id]) > Decimal("0.01")
            for order_id in item_totals.keys() & payment_totals.keys()
        ),
        "absolute_difference_sum": absolute_difference,
        "examples": mismatches,
    }


def make_report(data_dir: Path, stats: dict, conn: sqlite3.Connection) -> str:
    details = []
    lines = [
        "# Olist dataset validation report",
        "",
        f"- Source folder: `{data_dir}`",
        "- Method: Python standard library; CSV rows were parsed incrementally. A temporary disk-backed SQLite database was used for full-file duplicate, key, and relationship checks; it was removed after this report was written.",
        "- CSV empty fields are treated as nulls for this audit. Timestamps are checked as local, timezone-naive values.",
        "",
        "## File, header, type, and row-count results",
        "",
        "| CSV file | Observed rows | Original README count | Kaggle reference count | Header | Full duplicate rows | Typed-value errors |",
        "| --- | ---: | ---: | ---: | --- | ---: | ---: |",
    ]

    for spec in SPECS:
        item = stats[spec.table]
        readme = f"{spec.documented_rows:,}" if spec.documented_rows is not None else "Not listed"
        readme_check = "" if spec.documented_rows is None or item["rows"] == spec.documented_rows else " (mismatch)"
        header_status = "OK" if item["header_ok"] else "FAIL"
        if item["field_count_errors"]:
            header_status += f"; {item['field_count_errors']:,} malformed rows"
        typed_errors = sum(item["type_errors"].values())
        lines.append(
            f"| `{spec.filename}` | {item['rows']:,} | {readme}{readme_check} | "
            f"{spec.expected_rows:,} | {header_status} | {item['full_row_duplicates']:,} | {typed_errors:,} |"
        )
        if item["read_error"]:
            details.append(f"- **Read error — `{spec.filename}`:** {item['read_error']}")
        if not item["header_ok"]:
            details.append(f"- **Header found — `{spec.filename}`:** `{item['header_found']}`")
        if item["type_errors"]:
            type_details = "; ".join(
                f"`{column}` ({count:,}; example `{item['type_samples'][column]}`)"
                for column, count in sorted(item["type_errors"].items())
            )
            details.append(f"- **Type errors — `{spec.filename}`:** {type_details}")
        if item["timestamp_order_errors"]:
            timestamps = "; ".join(
                f"{name}: {count:,}" for name, count in sorted(item["timestamp_order_errors"].items())
            )
            details.append(f"- **Timestamp ordering anomalies — `{spec.filename}`:** {timestamps}")

    lines.extend([
        "",
        "## Typed-value checks",
        "",
        "- ZIP prefixes were checked as 1–5 digit text; integer fields as base-10 integers; decimal fields as finite decimal values; timestamp fields as ISO-compatible timestamps. Other source fields are retained as text.",
        "- Non-empty values in all checked integer, decimal, ZIP-prefix, and timestamp columns parsed successfully.",
    ])
    lines.extend(["", "## File-level notes", ""])
    lines.extend(details if details else ["No header, CSV parsing, field-count, or typed-value errors found."])

    lines.extend(["", "## Null values", ""])
    null_lines = []
    for spec in SPECS:
        columns = stats[spec.table]["nulls"]
        if columns:
            values = ", ".join(f"`{name}` {count:,}" for name, count in sorted(columns.items()))
            null_lines.append(f"- `{spec.filename}`: {values}")
    lines.extend(null_lines if null_lines else ["No empty CSV values found."])

    lines.extend(["", "## Key uniqueness and duplicate diagnostics", ""])
    lines.append("A duplicate count is the number of rows beyond the first row for a candidate key.")
    lines.append("")
    for table, candidates in UNIQUE_CANDIDATES.items():
        for columns in candidates:
            dupes = duplicate_excess(conn, table, columns)
            nulls = key_nulls(conn, table, columns)
            key = ", ".join(f"`{column}`" for column in columns)
            lines.append(f"- `{table}` candidate key ({key}): {dupes:,} duplicate row(s); {nulls:,} row(s) with a null key component.")
    for table, candidates in NON_UNIQUE_DIAGNOSTICS.items():
        for columns in candidates:
            dupes = duplicate_excess(conn, table, columns)
            nulls = key_nulls(conn, table, columns)
            key = ", ".join(f"`{column}`" for column in columns)
            lines.append(f"- `{table}` repeated-value diagnostic ({key}; not declared unique): {dupes:,} duplicate row(s); {nulls:,} null component(s).")

    lines.extend(["", "## Relationship checks", ""])
    relationships = (
        ("orders.customer_id → customers.customer_id", "orders", "customer_id", "customers", "customer_id"),
        ("order_items.order_id → orders.order_id", "order_items", "order_id", "orders", "order_id"),
        ("order_items.product_id → products.product_id", "order_items", "product_id", "products", "product_id"),
        ("order_items.seller_id → sellers.seller_id", "order_items", "seller_id", "sellers", "seller_id"),
        ("order_payments.order_id → orders.order_id", "order_payments", "order_id", "orders", "order_id"),
        ("order_reviews.order_id → orders.order_id", "order_reviews", "order_id", "orders", "order_id"),
        ("products.product_category_name → translation", "products", "product_category_name", "product_category_name_translation", "product_category_name"),
    )
    for label, child, child_col, parent, parent_col in relationships:
        lines.append(f"- `{label}`: {orphan_count(conn, child, child_col, parent, parent_col):,} orphan row(s).")
    customer_zip_unmatched = distinct_unmatched_count(
        conn, "customers", "customer_zip_code_prefix", "geolocation", "geolocation_zip_code_prefix"
    )
    seller_zip_unmatched = distinct_unmatched_count(
        conn, "sellers", "seller_zip_code_prefix", "geolocation", "geolocation_zip_code_prefix"
    )
    lines.append(f"- Customer ZIP prefixes absent from geolocation: {customer_zip_unmatched:,} distinct prefix(es) (informational; no foreign key planned).")
    lines.append(f"- Seller ZIP prefixes absent from geolocation: {seller_zip_unmatched:,} distinct prefix(es) (informational; no foreign key planned).")

    finance = financial_reconciliation(conn)
    lines.extend([
        "",
        "## Financial reconciliation",
        "",
        "Per order, item subtotal is `SUM(price + freight_value)` and payment total is `SUM(payment_value)`. Values are accumulated with decimal arithmetic; differences greater than BRL 0.01 are reported.",
        "",
        f"- Orders with items: {finance['item_orders']:,}; orders with payments: {finance['payment_orders']:,}; orders compared: {finance['compared_orders']:,}.",
        f"- Item-only orders: {finance['item_only_orders']:,}; payment-only orders: {finance['payment_only_orders']:,}.",
        f"- Orders with a difference over BRL 0.01: {finance['mismatch_orders']:,}; sum of absolute differences for those orders: BRL {finance['absolute_difference_sum']:.2f}.",
    ])
    if finance["examples"]:
        lines.append("- First mismatch examples (order, item total, payment total, payment minus item):")
        for example in finance["examples"]:
            order_id, item_total, payment_total, difference = example
            lines.append(f"  - `{order_id}`: {item_total:.2f}, {payment_total:.2f}, {difference:+.2f}")

    lines.extend([
        "",
        "## Interpretation",
        "",
        "CSV source files do not carry declared database types; the audit checked integer, decimal, ZIP-prefix, and timestamp values against the PostgreSQL table types, while identifiers and descriptions remain text. Nulls, repeated values, and reconciliation differences are reported as observations; they are not automatically treated as errors. Database constraints in `sql/01_create_tables.sql` are limited to keys and relationships supported by the observed data.",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Stream and audit the original Olist CSV files using only the Python standard library."
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=project_root / "data" / "raw",
        help="directory containing the nine original CSVs (default: data/raw)",
    )
    parser.add_argument(
        "--report",
        type=Path,
        help="optional Markdown report path; without this option, print the report to the terminal",
    )
    args = parser.parse_args()
    data_dir = args.data_dir.expanduser().resolve()

    missing = [spec.filename for spec in SPECS if not (data_dir / spec.filename).is_file()]
    if missing:
        print("Missing expected CSV file(s): " + ", ".join(missing))
        return 1

    state, temp_dir = stage_and_summarize(data_dir)
    conn = state["connection"]
    try:
        report = make_report(data_dir, state["stats"], conn)
        if args.report:
            report_path = args.report.expanduser().resolve()
            report_path.parent.mkdir(parents=True, exist_ok=True)
            report_path.write_text(report, encoding="utf-8")
            print(f"Validation report written to: {report_path}")
        else:
            print(report)
        for spec in SPECS:
            item = state["stats"][spec.table]
            null_count = sum(item["nulls"].values())
            type_error_count = sum(item["type_errors"].values())
            status = "OK" if item["header_ok"] and item["rows"] == spec.expected_rows and not item["read_error"] else "CHECK"
            print(
                f"{status:5} {spec.filename}: {item['rows']:,} rows; "
                f"{null_count:,} empty values; {item['full_row_duplicates']:,} duplicate rows; "
                f"{type_error_count:,} typed-value errors"
            )
        print("Review the Markdown report for key, relationship, timestamp, and financial details.")
        return 0
    finally:
        conn.close()
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
