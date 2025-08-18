from fastapi import FastAPI

from ingest_patch_upload import router as ingest_patch_router

app = FastAPI()
app.include_router(ingest_patch_router)


@app.get("/healthz")
def healthz():
    return {"ok": True}
