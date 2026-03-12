#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# put_richer_test_pdfs.sh
#
# Purpose:
#   Seed a realistic dev dataset in your processed bucket:
#     - multiple BANs
#     - several months per BAN
#     - intentional missing months
#
# Requirements:
#   - PROCESSED_BUCKET_URI must be set (e.g., gs://afp-pdfs-dev-highttyler)
#   - gsutil available (Cloud Shell has it)
# -----------------------------------------------------------------------------

if [[ -z "${PROCESSED_BUCKET_URI:-}" ]]; then
  echo "ERROR: PROCESSED_BUCKET_URI is not set" >&2
  echo "Example: export PROCESSED_BUCKET_URI=gs://afp-pdfs-dev-highttyler" >&2
  exit 1
fi

BUCKET="${PROCESSED_BUCKET_URI%/}"

make_pdf () {
  # args: <path> <label>
  local path="$1"; local label="$2"
  mkdir -p "$(dirname "$path")"
  {
    echo "%PDF-1.4"
    echo "% Mock statement: $label"
  } > "$path"
}

TMPDIR="$(mktemp -d)"
echo "Seeding test data under: $BUCKET"

# --- BAN 10003827: mostly monthly, with gaps (missing 2024-11 and 2025-02) ---
BAN=10003827
for ymd in 20241024 20241224 20250124 20250324; do
  make_pdf "$TMPDIR/$BAN/${BAN}_${ymd}.pdf" "${BAN}_${ymd}"
done
gsutil -m cp "$TMPDIR/$BAN/"*.pdf "$BUCKET/$BAN/"

# --- BAN 10004912: sparse coverage (Oct/Dec only) ---
BAN=10004912
for ymd in 20241020 20241220; do
  make_pdf "$TMPDIR/$BAN/${BAN}_${ymd}.pdf" "${BAN}_${ymd}"
done
gsutil -m cp "$TMPDIR/$BAN/"*.pdf "$BUCKET/$BAN/"

# --- BAN 10005788: full quarter (Oct, Nov, Dec) ---
BAN=10005788
for ymd in 20241015 20241115 20241215; do
  make_pdf "$TMPDIR/$BAN/${BAN}_${ymd}.pdf" "${BAN}_${ymd}"
done
gsutil -m cp "$TMPDIR/$BAN/"*.pdf "$BUCKET/$BAN/"

# --- BAN 10006001: crosses year boundary; missing Jan ---
BAN=10006001
for ymd in 20241110 20241210 20240210 20240310; do
  make_pdf "$TMPDIR/$BAN/${BAN}_${ymd}.pdf" "${BAN}_${ymd}"
done
gsutil -m cp "$TMPDIR/$BAN/"*.pdf "$BUCKET/$BAN/"

echo "Upload complete. Verifying a few prefixes..."
gsutil ls "$BUCKET/10003827/" || true
gsutil ls "$BUCKET/10004912/" || true