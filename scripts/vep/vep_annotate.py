#!/usr/bin/env python3
import argparse
import gzip
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DEFAULT_CHUNK_SIZE = 100000
MAX_RETRIES = 4
BACKOFF_BASE_SEC = 5
VEP_CACHE_DIR = "/mnt/nas_storage/vep/cache"
VEP_REF_DIR = "/mnt/nas_storage/vep/reference"
DB_HEADER_FILE = Path(__file__).with_name("columns_vep_annotated.tsv")
REQUIRED_COLUMNS = [c.strip() for c in DB_HEADER_FILE.read_text().splitlines() if c.strip()]


def run(cmd: list[str]) -> tuple[int, str, str]:
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    out, err = p.communicate()
    return p.returncode, out, err


def safe_unlink(p: Path):
    try:
        p.unlink(missing_ok=True)
    except Exception:
        pass


def parse_args():
    ap = argparse.ArgumentParser(
        description="Resilient VEP annotator with schema-aligned TSV output."
    )
    ap.add_argument("--vcf", required=True)
    ap.add_argument("--out-tsv", required=True)
    ap.add_argument("--assembly", default="GRCh38", choices=["GRCh37", "GRCh38"])
    ap.add_argument("--forks", type=int, default=4)
    ap.add_argument("--chunk-size", type=int, default=DEFAULT_CHUNK_SIZE)
    ap.add_argument("--max-retries", type=int, default=MAX_RETRIES)
    ap.add_argument("--cache-dir", default=VEP_CACHE_DIR)
    ap.add_argument("--ref-dir", default=VEP_REF_DIR)
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--vep-path", default="vep")
    return ap.parse_args()


def extract_columns_from_vep_record(rec: dict[str, str]) -> list[str]:
    def g(k):
        return rec.get(k) or ""

    def gnum(k):
        v = rec.get(k)
        if v in (None, ""):
            return ""
        try:
            return str(float(v))
        except (ValueError, TypeError):
            return ""

    strand_map = {"+": "1", "-": "-1", "1": "1", "-1": "-1"}
    strand = strand_map.get(rec.get("STRAND") or "", "")
    extra = rec.get("Extra", {}) or {}
    af = extra.get("gnomAD_AF") or extra.get("AF") or ""
    af_afr = extra.get("gnomAD_AFR_AF") or ""
    af_amr = extra.get("gnomAD_AMR_AF") or ""
    af_eas = extra.get("gnomAD_EAS_AF") or ""
    af_eur = extra.get("gnomAD_NFE_AF") or ""
    af_sas = extra.get("gnomAD_SAS_AF") or ""
    cadd_raw = extra.get("CADD_RAW", "")
    cadd_phred = extra.get("CADD_PHRED", "")
    clin_sig = extra.get("CLIN_SIG", "")
    sift = g("SIFT")
    polyphen = g("PolyPhen")
    canonical = "true" if (g("CANONICAL") == "YES" or extra.get("CANONICAL") == "YES") else "false"
    ordered = [
        g("Location").split(":")[0],
        g("Start") or g("POS") or g("Location").split(":")[1].split("-")[0],
        g("REF") or extra.get("REF_ALLELE", ""),
        g("Allele"),
        g("Existing_variation") or extra.get("RSID", ""),
        g("SYMBOL"),
        g("Gene"),
        g("Feature"),
        g("BIOTYPE") or extra.get("BIOTYPE", ""),
        g("Consequence"),
        g("IMPACT"),
        g("HGVSc"),
        g("HGVSp"),
        canonical,
        g("EXON"),
        g("INTRON"),
        g("Protein_position"),
        g("Amino_acids"),
        g("Codons"),
        strand,
        g("Existing_variation"),
        af,
        af_afr,
        af_amr,
        af_eas,
        af_eur,
        af_sas,
        clin_sig,
        sift,
        polyphen,
        cadd_raw,
        cadd_phred,
        json.dumps(extra, separators=(",", ":")),
    ]
    if len(ordered) != len(REQUIRED_COLUMNS):
        raise RuntimeError(
            f"Column count mismatch: got {len(ordered)} expected {len(REQUIRED_COLUMNS)}"
        )
    return ordered


def write_header(fp):
    fp.write("\t".join(REQUIRED_COLUMNS) + "\n")


def vcf_iter(path: Path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt") as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            yield line


def run_vep_on_chunk(lines: list[str], args) -> list[list[str]]:
    with tempfile.TemporaryDirectory() as td:
        chunk_vcf = Path(td) / "chunk.vcf"
        with open(chunk_vcf, "w") as w:
            w.write("##fileformat=VCFv4.2\n")
            w.write("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n")
            for ln in lines:
                w.write(ln)
        cmd = [
            args.vep_path,
            "--offline",
            "--assembly",
            args.assembly,
            "--dir_cache",
            args.cache_dir,
            "--fasta",
            str(Path(args.ref_dir) / f"{args.assembly}.fa"),
            "--everything",
            "--fork",
            str(args.forks),
            "--input_file",
            str(chunk_vcf),
            "--format",
            "vcf",
            "--vcf",
            "--tab",
            "--fields",
            "Location,Allele,Gene,SYMBOL,Feature,BIOTYPE,Consequence,IMPACT,EXON,INTRON,HGVSc,HGVSp,Protein_position,Amino_acids,Codons,STRAND,Existing_variation,SIFT,PolyPhen,CANONICAL",
            "--no_stats",
            "--cache",
        ]
        code, out, err = run(cmd)
        if code != 0:
            raise RuntimeError(f"VEP failed (exit {code}): {err[:1000]}")
        rows, vep_header = [], None
        for ln in out.splitlines():
            if ln.startswith("#"):
                continue
            if ln.startswith("Location\t"):
                vep_header = ln.strip().split("\t")
                continue
            parts = ln.strip().split("\t")
            rec = dict(zip(vep_header, parts, strict=False))
            extra = {}
            if "Extra" in rec:
                kvs = (rec["Extra"] or "").split(";")
                for kv in kvs:
                    if "=" in kv:
                        k, v = kv.split("=", 1)
                        extra[k] = v
                    elif kv:
                        extra[kv] = True
            rec["Extra"] = extra
            rows.append(extract_columns_from_vep_record(rec))
        return rows


def process_chunk(chunk_lines, out_fp, args):
    tries = 0
    while True:
        try:
            rows = run_vep_on_chunk(chunk_lines, args)
            for r in rows:
                out_fp.write("\t".join(r) + "\n")
            return len(rows)
        except Exception:
            tries += 1
            if tries > args.max_retries:
                raise
            time.sleep(BACKOFF_BASE_SEC * (2 ** (tries - 1)))


def main():
    args = parse_args()
    vcf = Path(args.vcf)
    out_tsv = Path(args.out_tsv)
    out_tmp = out_tsv.with_suffix(out_tsv.suffix + ".part")
    produced = 0
    if out_tmp.exists() and not args.resume:
        safe_unlink(out_tmp)
    with open(out_tmp, "a") as out:
        if out.tell() == 0:
            write_header(out)
        chunk = []
        for line in vcf_iter(vcf):
            chunk.append(line)
            if len(chunk) >= args.chunk_size:
                produced += process_chunk(chunk, out, args)
                chunk = []
        if chunk:
            produced += process_chunk(chunk, out, args)
    shutil.move(out_tmp, out_tsv)
    print(f"Wrote {produced} records to {out_tsv}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        sys.stderr.write(f"[FATAL] {e}\n")
        sys.exit(1)
