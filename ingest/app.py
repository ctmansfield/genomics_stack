import os, io, re, hmac, hashlib, base64, secrets, pathlib, zipfile, time
from typing import Optional
from fastapi import FastAPI, UploadFile, File, Form, Header, HTTPException
from fastapi.responses import PlainTextResponse, JSONResponse
import aiofiles
import psycopg

PGHOST = os.getenv("PGHOST","db")
PGPORT = int(os.getenv("PGPORT","5432"))
PGUSER = os.getenv("PGUSER","genouser")
PGPASSWORD = os.getenv("PGPASSWORD","")
PGDATABASE = os.getenv("PGDATABASE","genomics")
DATA_DIR = pathlib.Path(os.getenv("DATA_DIR","/data"))
MAX_UPLOAD_BYTES = int(os.getenv("MAX_UPLOAD_BYTES","2147483648"))  # 2GB
GLOBAL_UPLOAD_TOKEN = os.getenv("UPLOAD_TOKEN","")  # optional
TOKEN_SECRET = os.getenv("TOKEN_SECRET","")         # required for email tokens

app = FastAPI()

def b64u(s: bytes) -> str:
    return base64.urlsafe_b64encode(s).decode().rstrip("=")

def b64u_dec(s: str) -> bytes:
    pad = '=' * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)

def norm_email(e: str) -> str:
    return e.strip().lower()

def issue_token(email: str) -> str:
    if not TOKEN_SECRET:
        raise HTTPException(500, "TOKEN_SECRET not configured")
    e = norm_email(email).encode()
    mac = hmac.new(TOKEN_SECRET.encode(), e, hashlib.sha256).digest()
    return f"{b64u(e)}.{b64u(mac)}"

def verify_token(token: str) -> Optional[str]:
    try:
        email_b64, mac_b64 = token.split(".", 1)
        e = b64u_dec(email_b64)
        mac = b64u_dec(mac_b64)
        if not TOKEN_SECRET:
            return None
        good = hmac.new(TOKEN_SECRET.encode(), e, hashlib.sha256).digest()
        if hmac.compare_digest(mac, good):
            return e.decode()
    except Exception:
        return None
    return None

def get_con():
    return psycopg.connect(host=PGHOST, port=PGPORT, user=PGUSER, password=PGPASSWORD, dbname=PGDATABASE)

# DB bootstrap: add columns we need
DDL = """
create table if not exists uploads(
  id bigserial primary key,
  original_name text,
  stored_path text,
  size_bytes bigint,
  sha256 text,
  kind text,
  status text,
  notes text,
  sample_label text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table uploads add column if not exists claim_code text;
alter table uploads add column if not exists user_email text;
create index if not exists uploads_claim_code_idx on uploads(claim_code);
create index if not exists uploads_user_email_idx on uploads(user_email);
"""
with get_con() as con:
    con.execute(DDL)

@app.get("/healthz", response_class=PlainTextResponse)
def healthz():
    return "ok"

def auth_email_from_header(authorization: Optional[str]) -> Optional[str]:
    """
    Accept either:
      - Global token (UPLOAD_TOKEN) → returns None (admin/system)
      - Per-user token "Bearer <email.mac>" → returns the email if valid
    """
    if not authorization:
        return None
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Bad Authorization header")
    token = authorization.split(None,1)[1]
    if GLOBAL_UPLOAD_TOKEN and token == GLOBAL_UPLOAD_TOKEN:
        return None
    email = verify_token(token)
    if not email:
        raise HTTPException(401, "Invalid token")
    return email

def short_code(n=8) -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "".join(secrets.choice(alphabet) for _ in range(n))

@app.post("/upload")
async def upload_file(
    file: UploadFile = File(...),
    sample_label: Optional[str] = Form(None),
    authorization: Optional[str] = Header(None),
    email: Optional[str] = Form(None)
):
    # auth (optional). If token is present and valid, we get user_email;
    # otherwise allow anonymous upload that must be claimed later.
    user_email = auth_email_from_header(authorization)

    # basic size guard (stream into tmp)
    tmp = DATA_DIR / f"tmp_{int(time.time())}_{secrets.token_hex(6)}_{file.filename}"
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    size = 0
    sha = hashlib.sha256()
    async with aiofiles.open(tmp, "wb") as out:
        while True:
            chunk = await file.read(1<<20)
            if not chunk:
                break
            size += len(chunk)
            if size > MAX_UPLOAD_BYTES:
                await out.close()
                try: tmp.unlink(missing_ok=True)
                except Exception: pass
                raise HTTPException(413, f"File too large; limit is {MAX_UPLOAD_BYTES} bytes")
            sha.update(chunk)
            await out.write(chunk)

    dest = DATA_DIR / file.filename
    # ensure unique name
    if dest.exists():
        dest = DATA_DIR / f"{int(time.time())}_{secrets.token_hex(3)}_{file.filename}"
    tmp.rename(dest)

    kind = "txt"
    extracted_to = None
    if dest.suffix.lower() == ".zip":
        kind = "zip"
        extracted_to = dest.with_suffix("")  # folder next to file
        extracted_to.mkdir(exist_ok=True)
        with zipfile.ZipFile(dest, 'r') as z:
            z.extractall(extracted_to)

    claim = short_code()
    with get_con() as con:
        row = con.execute(
            """insert into uploads(original_name,stored_path,size_bytes,sha256,kind,status,notes,sample_label,claim_code,user_email)
               values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
               returning id""",
            (
                file.filename,
                str(dest),
                size,
                sha.hexdigest(),
                kind,
                "unzipped" if extracted_to else "received",
                f"unzipped to {extracted_to}" if extracted_to else None,
                sample_label,
                claim,
                norm_email(user_email) if user_email else (norm_email(email) if email else None),
            )
        ).fetchone()
        upload_id = row[0]

    msg = {
        "upload_id": upload_id,
        "claim_code": claim,
        "message": "Save this claim_code. Use /claim to bind your email and receive a reusable token.",
        "stored": str(dest),
        "bytes": size,
        "sha256": sha.hexdigest(),
        "kind": kind,
        "unzipped_to": str(extracted_to) if extracted_to else None
    }
    return JSONResponse(msg)

@app.post("/claim")
def claim_upload(payload: dict):
    """
    Body JSON: { "upload_id": 123, "email": "you@example.com", "claim_code": "ABCD1234" }
    Returns: { "token": "...", "email": "...", "upload_id": 123 }
    """
    try:
        upload_id = int(payload.get("upload_id"))
        email = norm_email(payload.get("email",""))
        code = payload.get("claim_code","").strip().upper()
    except Exception:
        raise HTTPException(400, "Bad payload")

    if not re.match(r"[^@]+@[^@]+\.[^@]+", email):
        raise HTTPException(400, "Invalid email")
    if not re.match(r"^[A-Z0-9]{6,}$", code):
        raise HTTPException(400, "Invalid claim_code")

    with get_con() as con:
        row = con.execute("select id, claim_code, user_email from uploads where id=%s", (upload_id,)).fetchone()
        if not row:
            raise HTTPException(404, "upload not found")
        if row[1] != code:
            raise HTTPException(403, "claim_code mismatch")

        # bind email to this upload (idempotent)
        con.execute("update uploads set user_email=%s where id=%s", (email, upload_id))

    tok = issue_token(email)
    return {"token": tok, "email": email, "upload_id": upload_id}

@app.post("/recover")
def recover_token(payload: dict):
    """
    Recover a token using any prior claim_code for your email.
    Body: { "email": "...", "claim_code": "..." }
    """
    email = norm_email(payload.get("email",""))
    code = payload.get("claim_code","").strip().upper()
    if not re.match(r"[^@]+@[^@]+\.[^@]+", email):
        raise HTTPException(400, "Invalid email")
    if not re.match(r"^[A-Z0-9]{6,}$", code):
        raise HTTPException(400, "Invalid claim_code")

    with get_con() as con:
        row = con.execute(
            "select 1 from uploads where claim_code=%s and (user_email=%s or user_email is null) limit 1",
            (code, email)
        ).fetchone()
        if not row:
            raise HTTPException(403, "no matching upload+claim_code")
        # ensure the upload is marked with this email (so future recovers work)
        con.execute("update uploads set user_email=%s where claim_code=%s and user_email is null", (email, code))

    return {"token": issue_token(email), "email": email}

@app.get("/whoami")
def whoami(authorization: Optional[str] = Header(None)):
    email = auth_email_from_header(authorization)
    if email is None and authorization:
        # global token
        return {"global": True}
    if not authorization:
        raise HTTPException(401, "no token")
    return {"email": email}

from fastapi.responses import HTMLResponse

@app.get("/", response_class=HTMLResponse)
def home():
    return """<!doctype html>
<html>
  <head><meta charset="utf-8"><title>Genomics Upload</title>
  <style>body{font-family:system-ui;margin:2rem;max-width:760px}</style></head>
  <body>
    <h1>Genomics Upload</h1>
    <p>POST <code>/upload</code> with a file and optional <code>sample_label</code>.
       You can also use this form:</p>
    <form action="/upload" method="post" enctype="multipart/form-data">
      <div><label>File: <input type="file" name="file"></label></div>
      <div><label>Sample label: <input name="sample_label" placeholder="e.g. John_Doe"></label></div>
      <div><button type="submit">Upload</button></div>
    </form>
    <p>Health: <a href="/healthz">/healthz</a> • API docs: <a href="/docs">/docs</a></p>
  </body>
</html>"""

# --- Reports download endpoints (requires valid token) ---
from fastapi.responses import FileResponse
REPORTS_DIR = os.getenv("REPORTS_DIR","/reports")

def _report_path(upload_id: int, kind: str) -> str:
    # kind in {"html","tsv","pdf"}
    return os.path.join(REPORTS_DIR, f"upload_{upload_id}", f"top5.{kind}")

@app.get("/reports/{upload_id}/top5.{ext}")
async def get_top5_report(upload_id: int, ext: str, request: Request, auth: Optional[str] = Header(None)):
    if ext not in {"html","tsv","pdf"}:
        raise HTTPException(status_code=404, detail="Unsupported format")

    email = require_auth(auth)
    with get_con() as con, con.cursor() as cur:
        cur.execute("select user_email from uploads where id=%s", (upload_id,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Upload not found")
        owner = row[0]
        if owner and owner != email:
            raise HTTPException(status_code=403, detail="Forbidden")

    path = _report_path(upload_id, ext)
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail=f"Report not found: {ext}")
    media = {"html":"text/html","tsv":"text/tab-separated-values","pdf":"application/pdf"}[ext]
    return FileResponse(path, media_type=media, filename=f"upload_{upload_id}_top5.{ext}")
