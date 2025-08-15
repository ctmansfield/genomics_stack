# Refactor Playbook (SRP-first)

**Principles**
- Single Responsibility: each function does one thing.
- Pure helpers: isolate transformation logic from I/O.
- Dependency injection: pass in DB/session/clients instead of importing globals.

**Workflow**
1) Run `tools/complexity_audit.sh` to identify hotspots.
2) Extract pure helpers: `load_and_validate`, `transform`, `upsert_rows`.
3) Add unit tests around helpers before moving logic.
4) Keep I/O at the edges (`main()` orchestrates).

**Example**
```python
def load_and_validate(path: str) -> list[Record]: ...
def transform(records: list[Record]) -> list[Row]: ...
def upsert_rows(conn, rows: list[Row]) -> int: ...
def main(path: str, conn) -> int:
    return upsert_rows(conn, transform(load_and_validate(path)))
```
