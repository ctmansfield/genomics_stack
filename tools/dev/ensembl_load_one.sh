#!/usr/bin/env bash
set -Eeuo pipefail

# Usage: tools/dev/ensembl_load_one.sh <DB> <TABLE>
CONT="${CONT:-ensembldb}"
DUMPROOT="${DUMPROOT:-/mnt/llmstore/ensembl/dumps/release-114/mysql}"

DB="${1:-}"; TBL="${2:-}"
[[ -n "$DB" && -n "$TBL" ]] || { echo "Usage: $0 <DB> <TABLE>"; exit 64; }

ROOT="${DUMPROOT}/${DB}"
SCHEMA_GZ="${ROOT}/${DB}.sql.gz"
DATA_GZ="${ROOT}/${TBL}.txt.gz"

[[ -d "$ROOT" ]]      || { echo "[ERR] missing $ROOT"; exit 1; }
[[ -f "$SCHEMA_GZ" ]] || { echo "[ERR] missing schema: $SCHEMA_GZ"; exit 1; }
[[ -f "$DATA_GZ"   ]] || { echo "[ERR] missing data:   $DATA_GZ"; exit 1; }

mysqlc(){ docker exec -i "$CONT" mysql --local-infile=1 -N -B -u root -pensembl "$@"; }
mysqle(){ mysqlc -e "$1"; }

echo "[info] DB=$DB TBL=$TBL"
echo "[info] ensure DB exists + schema applied (idempotent)"
mysqle "CREATE DATABASE IF NOT EXISTS \`$DB\` DEFAULT CHARACTER SET utf8mb4;"
gzip -dc "$SCHEMA_GZ" | docker exec -i "$CONT" mysql -u root -pensembl "$DB"

ENGINE=$(mysqlc -e "SELECT ENGINE FROM information_schema.tables WHERE table_schema='$DB' AND table_name='$TBL';")
AI_COL=$(mysqlc -e "SELECT COLUMN_NAME FROM information_schema.columns WHERE table_schema='$DB' AND table_name='$TBL' AND EXTRA LIKE '%auto_increment%';")
CHARSET=$(gzip -dc "$SCHEMA_GZ" | sed -n 's/.*DEFAULT CHARSET=\([a-z0-9_]\+\).*/\1/p' | head -1)
[[ -n "$CHARSET" ]] || CHARSET=latin1

# counts
NC_ALL=$(mysqlc -e "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='$DB' AND table_name='$TBL';")
NC_NOAI=$(mysqlc -e "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='$DB' AND table_name='$TBL' AND EXTRA NOT LIKE '%auto_increment%';")
NF_FILE=$(gzip -dc "$DATA_GZ" | head -1 | awk -F'\t' '{print NF}')
ALL_COLS=$(mysqlc -e "SELECT GROUP_CONCAT(CONCAT('\`',COLUMN_NAME,'\`') ORDER BY ORDINAL_POSITION SEPARATOR ',') FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$DB' AND TABLE_NAME='$TBL';")
NOAI_COLS=$(mysqlc -e "SELECT GROUP_CONCAT(CONCAT('\`',COLUMN_NAME,'\`') ORDER BY ORDINAL_POSITION SEPARATOR ',') FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$DB' AND TABLE_NAME='$TBL' AND EXTRA NOT LIKE '%auto_increment%';")

FILE_HAS_AI=0
LD_COLS="$ALL_COLS"
LD_SET=""
if [[ -n "$AI_COL" && "$NF_FILE" -eq "$NC_ALL" ]]; then
  # dump includes the AI column -> read it into a user var and don't insert it
  LD_COLS="@dump_id,$NOAI_COLS"
  LD_SET="SET \`$AI_COL\`=NULL"
  FILE_HAS_AI=1
elif [[ "$NF_FILE" -eq "$NC_NOAI" ]]; then
  LD_COLS="$NOAI_COLS"
else
  echo "[ERR] field count $NF_FILE doesn't match table columns ($NC_ALL) or no-AI ($NC_NOAI)"; exit 2
fi

echo "[info] ENGINE=$ENGINE CHARSET=$CHARSET AI_COL=${AI_COL:-none} NF_FILE=$NF_FILE has_ai=$FILE_HAS_AI"

# MyISAM bulk index speedup is harmless on other engines
[ "$ENGINE" = "MyISAM" ] && mysqle "ALTER TABLE \`$DB\`.\`$TBL\` DISABLE KEYS;"

STAGED="/tmp/${DB}.${TBL}.txt"
echo "[stage] $DATA_GZ -> $CONT:$STAGED"
gzip -dc "$DATA_GZ" | docker exec -i "$CONT" bash -lc "cat > '$STAGED'"

echo "[load] $DB.$TBL"
mysqle "
  SET NAMES $CHARSET;
  SET SESSION unique_checks=0, foreign_key_checks=0;
  LOAD DATA LOCAL INFILE '$STAGED'
    INTO TABLE \`$DB\`.\`$TBL\`
    CHARACTER SET $CHARSET
    FIELDS TERMINATED BY '\t'
    LINES  TERMINATED BY '\n'
    ($LD_COLS)
    $LD_SET;
  SET SESSION unique_checks=1, foreign_key_checks=1;
"
[ "$ENGINE" = "MyISAM" ] && mysqle "ALTER TABLE \`$DB\`.\`$TBL\` ENABLE KEYS;"

docker exec "$CONT" rm -f "$STAGED" || true
ROWS=$(mysqlc -e "SELECT COUNT(*) FROM \`$DB\`.\`$TBL\`;")
echo "[ok] $DB.$TBL rows=$ROWS"
