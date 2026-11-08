"""
Build the SQLite database from data/raw/*.csv, run every analysis query in
sql/, and write each result set to outputs/<query_name>.csv.

    python scripts/build_db.py            # build + run everything
    python scripts/build_db.py --only 03  # run only sql/03_*.sql

Requires: Python 3.9+, pandas. No other dependencies.
"""

from __future__ import annotations

import argparse
import glob
import gzip
import os
import sqlite3
import sys
import time

import pandas as pd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "data", "raw")
DB = os.path.join(ROOT, "data", "ecommerce.db")
SQL_DIR = os.path.join(ROOT, "sql")
OUT = os.path.join(ROOT, "outputs")

LOAD_ORDER = ["customers", "products", "orders", "order_items", "payments", "reviews", "web_events"]


def read_csv_any(table: str) -> pd.DataFrame:
    """Read table.csv or table.csv.gz, whichever exists."""
    for ext in (".csv", ".csv.gz"):
        p = os.path.join(RAW, table + ext)
        if os.path.exists(p):
            opener = gzip.open if ext.endswith(".gz") else open
            with opener(p, "rt", encoding="utf-8") as f:
                return pd.read_csv(f, keep_default_na=True)
    raise FileNotFoundError(f"{table}.csv(.gz) not found in {RAW} - run data/generate_data.py first")


def build_database() -> sqlite3.Connection:
    if os.path.exists(DB):
        os.remove(DB)
    con = sqlite3.connect(DB)
    with open(os.path.join(SQL_DIR, "00_schema.sql"), encoding="utf-8") as f:
        con.executescript(f.read())
    for table in LOAD_ORDER:
        t0 = time.time()
        df = read_csv_any(table)
        df.to_sql(table, con, if_exists="append", index=False)
        print(f"  loaded {table:12s} {len(df):>8,} rows  ({time.time() - t0:.1f}s)")
    con.commit()
    return con


def run_queries(con: sqlite3.Connection, only: str | None) -> None:
    os.makedirs(OUT, exist_ok=True)
    files = sorted(glob.glob(os.path.join(SQL_DIR, "[0-9][0-9]_*.sql")))
    for path in files:
        name = os.path.splitext(os.path.basename(path))[0]
        if name.startswith("00_"):
            continue
        if only and not name.startswith(only):
            continue
        with open(path, encoding="utf-8") as f:
            sql = f.read()
        t0 = time.time()
        df = pd.read_sql_query(sql, con)
        out_path = os.path.join(OUT, f"{name}.csv")
        df.to_csv(out_path, index=False)
        print(f"  {name:38s} {len(df):>6,} rows  {time.time() - t0:5.2f}s -> outputs/{name}.csv")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="prefix of the query file to run, e.g. 03")
    ap.add_argument("--skip-build", action="store_true", help="reuse the existing data/ecommerce.db")
    args = ap.parse_args()

    if args.skip_build and os.path.exists(DB):
        con = sqlite3.connect(DB)
    else:
        print("Building database ...")
        con = build_database()
    print("Running analysis queries ...")
    run_queries(con, args.only)
    con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
