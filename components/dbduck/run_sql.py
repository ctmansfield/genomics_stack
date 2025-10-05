#!/usr/bin/env python3
import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))
from components.dbduck.duck import conn

if len(sys.argv) != 2:
    print("usage: run_sql.py <sql_file>", file=sys.stderr)
    raise SystemExit(2)

sql_path = sys.argv[1]
with open(sql_path, "r", encoding="utf-8") as f:
    sql = f.read()

with conn() as con:
    con.execute(sql)
print("sql_ok")
