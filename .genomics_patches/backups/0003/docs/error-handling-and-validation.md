# Error Handling & Validation

- Use `lib.errors` for domain-specific exceptions.
- Configure logging with `support/logging.ini`.
- Load env config via `support.config.Settings` (pydantic-settings).

**DB Safety Example**
```python
cur.execute("INSERT INTO snps (rsid, pos) VALUES (%s, %s)", (rsid, pos))
```
