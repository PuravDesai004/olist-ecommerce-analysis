"""Reproduce Olist 2.0 in PostgreSQL with psql and Python's standard library.

No source records are written. The only DDL is the project-owned view layer.
Credentials come from libpq's environment/passfile, --prompt-password in a local
terminal, or an optional native Windows password dialog. Never from arguments.
"""
from __future__ import annotations

import argparse
import csv
import ctypes
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "sql" / "verification_results.json"
SOURCE_TABLES = (
    "customers", "geolocation", "order_items", "order_payments", "order_reviews",
    "orders", "products", "sellers", "product_category_name_translation",
)
LEGACY_REF = "c113389"
SCHEMA = "olist_analytics"


def stamp():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def split_sql(text):
    """Split only real semicolons; preserve quoted text and strip SQL comments."""
    out, chunk, pos = [], [], 0
    quote, dollar, block_depth = None, None, 0
    while pos < len(text):
        ch, two = text[pos], text[pos:pos+2]
        if block_depth:
            if two == "/*":
                block_depth += 1
                pos += 2
            elif two == "*/":
                block_depth -= 1
                pos += 2
            else:
                pos += 1
            continue
        if dollar:
            if text.startswith(dollar, pos):
                chunk.append(dollar)
                pos += len(dollar)
                dollar = None
            else:
                chunk.append(ch)
                pos += 1
            continue
        if quote:
            chunk.append(ch)
            pos += 1
            if ch == quote:
                if pos < len(text) and text[pos] == quote:
                    chunk.append(text[pos])
                    pos += 1
                else:
                    quote = None
            continue
        if two == "--":
            end = text.find("\n", pos)
            pos = len(text) if end == -1 else end
            chunk.append("\n")
        elif two == "/*":
            block_depth = 1
            pos += 2
            chunk.append(" ")
        elif ch in "'\"":
            quote = ch
            chunk.append(ch)
            pos += 1
        elif ch == "$" and (match := re.match(r"\$(?:[A-Za-z_]\w*)?\$", text[pos:])):
            dollar = match.group()
            chunk.append(dollar)
            pos += len(dollar)
        elif ch == ";":
            if statement := "".join(chunk).strip():
                out.append(statement)
            chunk = []
            pos += 1
        else:
            chunk.append(ch)
            pos += 1
    if quote or dollar or block_depth:
        raise ValueError("Unterminated SQL string/comment")
    if statement := "".join(chunk).strip():
        out.append(statement)
    return out


def analyses(text):
    matches = list(re.finditer(r"^-- (Q\d{2}) \| (.+)$", text, re.M))
    result = []
    for index, match in enumerate(matches):
        end = matches[index+1].start() if index+1 < len(matches) else len(text)
        body = text[match.end():end]
        legacy = re.search(r"^-- Legacy: ([BIA0-9,]+)\.", body, re.M)
        statements = [s for s in split_sql(body) if s.upper() not in ("COMMIT", "BEGIN TRANSACTION READ ONLY")]
        if len(statements) != 1 or not re.match(r"^(SELECT|WITH)\b", statements[0], re.I):
            raise ValueError(f"{match[1]} must contain exactly one SELECT/WITH")
        result.append(dict(id=match[1], title=match[2],
                           legacy=legacy[1].split(",") if legacy else [],
                           sql=statements[0]))
    expected = {f"B{x}" for x in range(1, 9)} | {f"I{x}" for x in range(1, 16)} | {f"A{x}" for x in range(1, 7)}
    if {x for item in result for x in item["legacy"]} != expected:
        raise ValueError("The corrected query set does not cover all 29 original IDs")
    if len({x["id"] for x in result}) != len(result):
        raise ValueError("Duplicate query identifiers")
    return result


def windows_password(user):
    if os.name != "nt":
        raise RuntimeError("Windows dialog is only available on Windows")
    from ctypes import wintypes
    class CREDUI_INFO(ctypes.Structure):
        _fields_ = [("cbSize", wintypes.DWORD), ("hwndParent", wintypes.HWND),
                    ("pszMessageText", wintypes.LPCWSTR), ("pszCaptionText", wintypes.LPCWSTR),
                    ("hbmBanner", wintypes.HBITMAP)]
    info = CREDUI_INFO()
    info.cbSize = ctypes.sizeof(info)
    info.pszCaptionText = "Olist 2.0 - local PostgreSQL authentication"
    info.pszMessageText = ("Enter the local PostgreSQL password. It is used only in memory "
                           "to execute and verify Olist SQL. No password will be saved.")
    username = ctypes.create_unicode_buffer(user, 514)
    password = ctypes.create_unicode_buffer(514)
    save = wintypes.BOOL(False)
    fn = ctypes.WinDLL("credui", use_last_error=True).CredUIPromptForCredentialsW
    fn.argtypes = [ctypes.POINTER(CREDUI_INFO), wintypes.LPCWSTR, ctypes.c_void_p,
                   wintypes.DWORD, wintypes.LPWSTR, wintypes.ULONG, wintypes.LPWSTR,
                   wintypes.ULONG, ctypes.POINTER(wintypes.BOOL), wintypes.DWORD]
    result = fn(ctypes.byref(info), "Olist2/localhost", None, 0, username, len(username),
                password, len(password), ctypes.byref(save), 0x40000 | 0x80 | 0x2)
    if result == 1223:
        raise RuntimeError("Local password dialog was cancelled")
    if result:
        raise RuntimeError(f"Windows credential dialog failed with code {result}")
    if username.value != user:
        raise RuntimeError("Use the configured PostgreSQL username in the local dialog")
    value = password.value
    ctypes.memset(ctypes.addressof(password), 0, ctypes.sizeof(password))
    return value


class Database:
    def __init__(self, args):
        self.args = args
        self.env = dict(os.environ)
        # Read only standard libpq configuration keys; no eval or shell sourcing.
        env_file = ROOT / ".env"
        if env_file.exists():
            allowed = {"PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD", "PGPASSFILE", "PGSERVICE", "PGSERVICEFILE"}
            for line in env_file.read_text(encoding="utf-8-sig").splitlines():
                if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                if key.strip() in allowed:
                    self.env.setdefault(key.strip(), value.strip().strip("'\""))
        local_passfile = ROOT / ".pgpass"
        if local_passfile.exists():
            self.env.setdefault("PGPASSFILE", str(local_passfile))
        if args.prompt_password:
            if not sys.stdin.isatty():
                raise RuntimeError("--prompt-password must run in your local interactive terminal")
            self.env["PGPASSWORD"] = getpass.getpass("Local PostgreSQL password (hidden): ")
        if args.windows_password_dialog:
            self.env["PGPASSWORD"] = windows_password(args.user)
        self.env["PGCLIENTENCODING"] = "UTF8"
        self.env["PGCONNECT_TIMEOUT"] = "10"
        self.env["PGOPTIONS"] = "-c statement_timeout=300000 -c lock_timeout=5000"
        candidate = args.psql or shutil.which("psql")
        if not candidate and os.name == "nt":
            candidate = r"C:\Program Files\PostgreSQL\18\bin\psql.exe"
        if not candidate or not Path(candidate).is_file():
            raise RuntimeError("psql not found; pass --psql with the executable path")
        self.command = [str(candidate), "-X", "-w", "-qAt", "-h", args.host,
                        "-p", str(args.port), "-U", args.user, "-d", args.database,
                        "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"]

    def clean_error(self, value):
        if password := self.env.get("PGPASSWORD"):
            value = value.replace(password, "[REDACTED]")
        return value.strip()

    def execute(self, sql, readonly=True, allow_error=False):
        wrapped = ("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;\n"
                   + sql.strip().rstrip(";") + ";\nCOMMIT;\n") if readonly else sql
        run = subprocess.run(self.command, input=wrapped, encoding="utf-8",
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             env=self.env, cwd=ROOT, timeout=1200)
        if run.returncode and not allow_error:
            raise RuntimeError(self.clean_error(run.stderr))
        return run

    def json(self, sql):
        run = self.execute(sql)
        return json.loads(run.stdout.strip())

    def sample(self, sql, limit=20):
        query = ("WITH result AS MATERIALIZED (" + sql.strip().rstrip(";") + ") "
                 "SELECT json_build_object('row_count',(SELECT COUNT(*) FROM result),"
                 "'sample',(SELECT COALESCE(json_agg(row_to_json(s)), '[]'::json) "
                 f"FROM (SELECT * FROM result LIMIT {int(limit)}) s))")
        return self.json(query)

    def script(self, path, readonly=True):
        text = Path(path).read_text(encoding="utf-8-sig")
        # The existing metrics file already owns its read-only transaction.
        return self.execute(text, readonly=readonly)


def snapshot(db):
    terms = [
        f"SELECT '{name}' AS table_name, COUNT(*) AS rows, "
        f"SUM(hashtextextended(to_jsonb(t)::text,0)::numeric)::text AS content_checksum "
        f"FROM public.{name} t" for name in SOURCE_TABLES
    ]
    return db.json("SELECT json_agg(x ORDER BY table_name) FROM (" + " UNION ALL ".join(terms) + ") x")


def catalog(db):
    return db.json("""SELECT json_build_object(
      'database',current_database(),'version',version(),
      'columns',(SELECT json_agg(x ORDER BY table_name,ordinal_position) FROM (
        SELECT table_name,column_name,data_type,is_nullable,ordinal_position
        FROM information_schema.columns WHERE table_schema='public'
      ) x),
      'constraints',(SELECT json_agg(x ORDER BY table_name,constraint_name) FROM (
        SELECT c.conrelid::regclass::text AS table_name,c.conname AS constraint_name,
               c.contype,pg_get_constraintdef(c.oid) AS definition,c.convalidated
        FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace
        WHERE n.nspname='public'
      ) x),
      'existing_project_objects',(SELECT COALESCE(json_agg(x),'[]'::json) FROM (
        SELECT c.relname,c.relkind,pg_get_userbyid(c.relowner) AS owner,
               CASE WHEN c.relkind='v' THEN pg_get_viewdef(c.oid,true) END AS definition
        FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='olist_analytics'
      ) x),
      'project_dependents',(SELECT COALESCE(json_agg(x),'[]'::json) FROM (
        SELECT DISTINCT sn.nspname AS source_schema,src.relname AS source_view,
               dn.nspname AS dependent_schema,dep.relname AS dependent_view
        FROM pg_depend d JOIN pg_rewrite rw ON rw.oid=d.objid
        JOIN pg_class dep ON dep.oid=rw.ev_class
        JOIN pg_class src ON src.oid=d.refobjid
        JOIN pg_namespace sn ON sn.oid=src.relnamespace
        JOIN pg_namespace dn ON dn.oid=dep.relnamespace
        WHERE sn.nspname='olist_analytics' AND dep.oid<>src.oid
      ) x)
    )""")


def save_report(report):
    report["updated_at_utc"] = stamp()
    temporary = REPORT.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    # OneDrive or antivirus can briefly hold the destination without delete
    # sharing. Retry the atomic replacement; never leave a partial JSON file.
    for attempt in range(8):
        try:
            temporary.replace(REPORT)
            break
        except PermissionError:
            if attempt == 7:
                raise
            time.sleep(min(0.1 * 2**attempt, 1.0))


def source_contract(actual):
    import audit_olist_dataset as audit
    expected = {spec.table: list(spec.headers) for spec in audit.SPECS}
    for table_name, columns in expected.items():
        observed = [c["column_name"] for c in actual["columns"] if c["table_name"] == table_name]
        if observed != columns:
            raise RuntimeError(f"Actual source columns differ from CSV/schema contract: {table_name}")
    if actual["database"] != "olist2":
        raise RuntimeError("Refusing to deploy reporting objects outside the existing olist2 database")
    if any(not item["convalidated"] for item in actual["constraints"] or []):
        raise RuntimeError("Unvalidated source constraints found; investigate before deploying")


def run_all(db, args):
    report = dict(status="RUNNING", started_at_utc=stamp(), legacy_ref=LEGACY_REF,
                  database=args.database, host=args.host, port=args.port,
                  definitions=dict(rfm_reference_date="2018-09-01",
                                   cohort_observation_end="2018-09-01"))
    try:
        report["catalog_before"] = catalog(db)
        source_contract(report["catalog_before"])
        view_file = ROOT / "sql/05_reporting_views.sql"
        view_text = view_file.read_text(encoding="utf-8")
        owned = re.findall(r"CREATE OR REPLACE VIEW olist_analytics\.(\w+) AS", view_text)
        if len(owned) != len(set(owned)):
            raise RuntimeError("Duplicate project view definitions")
        for existing in report["catalog_before"]["existing_project_objects"]:
            if existing["relkind"] != "v" or existing["relname"] not in owned:
                raise RuntimeError("Unrecognized existing object in analytical schema; preserve and inspect")
        external = [d for d in report["catalog_before"]["project_dependents"]
                    if d["dependent_schema"] != SCHEMA]
        if external:
            raise RuntimeError("External dependencies on analytical views require inspection before replacement")
        report["source_before"] = snapshot(db)
        raw = ROOT / "data/raw"
        report["csv_before"] = {p.name: sha(p) for p in sorted(raw.glob("*.csv"))}
        if len(report["csv_before"]) != 9:
            raise RuntimeError("Exactly the nine expected raw CSVs are required")
        report["sql_hashes"] = {str(p.relative_to(ROOT)).replace("\\", "/"): sha(p)
                                for p in [ROOT/"olist_queries.sql", *sorted((ROOT/"sql").glob("*.sql"))]}
        # Audit every original statement. Errors are recorded, not hidden.
        original = subprocess.run(["git", "show", f"{LEGACY_REF}:olist_queries.sql"],
                                  cwd=ROOT, capture_output=True, text=True, encoding="utf-8", check=True).stdout
        legacy_sql = split_sql(original)
        ids = [f"B{x}" for x in range(1,9)] + [f"I{x}" for x in range(1,16)] + [f"A{x}" for x in range(1,7)]
        if len(legacy_sql) != 29:
            raise RuntimeError("Legacy source does not contain the expected 29 statements")
        report["original_query_audit"] = []
        print("Auditing all 29 original SQL statements...", flush=True)
        for key, sql in zip(ids, legacy_sql):
            old = db.execute(sql, allow_error=True)
            report["original_query_audit"].append(dict(
                id=key, status="ERROR" if old.returncode else "EXECUTED",
                error=db.clean_error(old.stderr)[:900] if old.returncode else None,
                sql_sha256=hashlib.sha256(sql.encode()).hexdigest()))
        save_report(report)
        print("Applying project-owned reporting views in one transaction...", flush=True)
        db.script(view_file, readonly=False)
        report["views"] = owned
        checks = db.sample((ROOT/"sql/06_validate_analytics.sql").read_text(encoding="utf-8"), limit=1000)
        report["validation"] = checks["sample"]
        if checks["row_count"] != len(report["validation"]) or len(report["validation"]) < 100:
            raise RuntimeError("Validation coverage is incomplete")
        failures = [x for x in report["validation"] if x["status"] != "PASS"]
        save_report(report)
        if failures:
            raise RuntimeError("SQL quality gates failed: " + json.dumps(failures))
        report["analyses"] = []
        for item in analyses((ROOT/"olist_queries.sql").read_text(encoding="utf-8")):
            print(f"Executing {item['id']}: {item['title']}", flush=True)
            data = db.sample(item["sql"], limit=10 if item["id"] in {"Q13","Q14","Q21"} else 2000)
            report["analyses"].append(dict(
                id=item["id"], title=item["title"], legacy=item["legacy"],
                status="PASS", sql_sha256=hashlib.sha256(item["sql"].encode()).hexdigest(),
                **data, sample_truncated=data["row_count"]>len(data["sample"])))
            save_report(report)
        report["phase1_scripts"] = []
        for name in ("03_validate_import.sql", "04_validate_metrics.sql"):
            run = db.script(ROOT/"sql"/name, readonly=name!="04_validate_metrics.sql")
            report["phase1_scripts"].append(dict(file=name, status="PASS",
                output_sha256=hashlib.sha256(run.stdout.encode()).hexdigest()))
        if not args.skip_csv_audit:
            print("Running streaming source CSV audit...", flush=True)
            run = subprocess.run([sys.executable, str(ROOT/"scripts/audit_olist_dataset.py")],
                                 cwd=ROOT, capture_output=True, encoding="utf-8", timeout=1200)
            summary = re.findall(r"^(?:OK|CHECK)\s+.*$", run.stdout, re.M)
            report["csv_audit"] = dict(status="PASS", summary=summary,
                output_sha256=hashlib.sha256(run.stdout.encode()).hexdigest())
            if run.returncode or len(summary)!=9 or any(
                    x.startswith("CHECK") or not x.endswith("; 0 typed-value errors") for x in summary):
                report["csv_audit"]["status"]="FAIL"
                raise RuntimeError("CSV audit failed; rerun audit_olist_dataset.py to inspect details")
        else:
            report["csv_audit"] = dict(status="SKIPPED")
        report["source_after"] = snapshot(db)
        report["csv_after"] = {p.name: sha(p) for p in sorted(raw.glob("*.csv"))}
        report["source_unchanged"] = report["source_before"] == report["source_after"]
        report["csv_unchanged"] = report["csv_before"] == report["csv_after"]
        if not report["source_unchanged"] or not report["csv_unchanged"]:
            raise RuntimeError("Source table/CSV fingerprints changed; investigate concurrent changes")
        report["catalog_after"] = catalog(db)
        report["status"] = "PASS" if report["csv_audit"]["status"] == "PASS" else "PARTIAL"
        report["finished_at_utc"] = stamp()
        save_report(report)
        print(f"COMPLETE: {len(report['analyses'])} analyses; "
              f"{len(report['validation'])} SQL checks; {len(owned)} views; "
              f"source tables and CSVs unchanged. Evidence: {REPORT}", flush=True)
        return report["status"] == "PASS"
    except Exception as exc:
        report["status"]="FAIL"
        report["error"]=db.clean_error(str(exc))
        save_report(report)
        raise


def self_test():
    from unittest import mock
    assert split_sql("SELECT ';'; -- ;\nSELECT 2;") == ["SELECT ';'", "SELECT 2"]
    assert split_sql('SELECT "semi;colon"; /* a /* nested */ ; */ SELECT 2;') == [
        'SELECT "semi;colon"', "SELECT 2"]
    assert split_sql("SELECT $$a;b$$; SELECT 'it''s;ok';")==["SELECT $$a;b$$","SELECT 'it''s;ok'"]
    assert len(analyses((ROOT/"olist_queries.sql").read_text(encoding="utf-8"))) == 38
    db = object.__new__(Database)
    captured = []
    db.json = lambda sql: captured.append(sql) or {}
    db.sample("SELECT ';' AS value;\n")
    assert "MATERIALIZED (SELECT ';' AS value)" in captured[-1]
    db.command, db.env = ["psql-test-double"], {}
    completed = subprocess.CompletedProcess(db.command, 0, stdout="", stderr="")
    with mock.patch("subprocess.run", return_value=completed) as call:
        db.execute("SELECT 1;\n")
        assert call.call_args.kwargs["input"].endswith("SELECT 1;\nCOMMIT;\n")
        assert "READ ONLY" in call.call_args.kwargs["input"]
    with mock.patch.object(Path, "write_text", return_value=0):
        with mock.patch.object(Path, "replace", side_effect=[PermissionError("temporary lock"), None]) as replace:
            with mock.patch("time.sleep"):
                save_report({"status": "TEST"})
        assert replace.call_count == 2
    print("PASS: SQL splitting, 29 legacy mappings, trailing delimiters, read-only wrapping and transient file-lock retry")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host",default="localhost")
    parser.add_argument("--port",default=5432,type=int)
    parser.add_argument("--database",default="olist2")
    parser.add_argument("--user",default="postgres")
    parser.add_argument("--psql")
    parser.add_argument("--prompt-password",action="store_true")
    parser.add_argument("--windows-password-dialog",action="store_true")
    parser.add_argument("--watch",action="store_true",
                        help="After a failed run, retain credentials in process memory and retry only after SQL changes")
    parser.add_argument("--skip-csv-audit",action="store_true",help="Development-only; final status remains PARTIAL")
    parser.add_argument("--self-test",action="store_true")
    args=parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    db=Database(args)
    try:
        while True:
            watched=[ROOT/"olist_queries.sql",*sorted((ROOT/"sql").glob("*.sql"))]
            before=[sha(p) for p in watched]
            try:
                return 0 if run_all(db,args) else 1
            except Exception as exc:
                print("Verification stopped: "+db.clean_error(str(exc)),file=sys.stderr,flush=True)
                if not args.watch:
                    return 1
                print("Runner remains live. Waiting for SQL fixes; credentials stay only in memory.",flush=True)
                while before==[sha(p) for p in watched]:
                    time.sleep(3)
    finally:
        db.env.pop("PGPASSWORD",None)


if __name__=="__main__":
    raise SystemExit(main())
