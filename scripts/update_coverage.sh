#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# list_coverage.sh
#
# Purpose:
#   Scan a processed bucket laid out as:
#     gs://<bucket>/<BAN>/<BAN>_YYYYMMDD.pdf
#   and emit:
#     - coverage_months.csv (BAN,YEAR,MONTH that exist)
#     - missing_months.csv  (BAN,YEAR,MONTH missing in a given range)
#
# Inputs (env):
#   PROCESSED_BUCKET_URI  e.g., gs://afp-pdfs-dev-highttyler
#   START                 e.g., 2024-10
#   END                   e.g., 2025-03
#
# Behavior:
#   - If START/END are not set, prints only existing months and exits (no missing calc).
# -----------------------------------------------------------------------------

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: $name is not set" >&2
    exit 1
  fi
}

# --- Bucket required
require_env PROCESSED_BUCKET_URI
BUCKET="${PROCESSED_BUCKET_URI%/}"

OUT_HAVE="./coverage_months.csv"
OUT_MISS="./missing_months.csv"

# --- Gather all PDFs under any BAN folder
mapfile -t PDF_URIS < <(gsutil ls -r "${BUCKET}/*/*.pdf" 2>/dev/null || true)

# If nothing found, write header(s) and exit 0
if [[ ${#PDF_URIS[@]} -eq 0 ]]; then
  echo "ban,year,month" > "$OUT_HAVE"
  echo "ban,year,month" > "$OUT_MISS"
  echo "No PDFs found under ${BUCKET}/*/" >&2
  exit 0
fi

# --- Parse URIs → BAN,YEAR,MONTH present
TMP_HAVE="$(mktemp)"
for uri in "${PDF_URIS[@]}"; do
  fn="$(basename "$uri")"
  if [[ "$fn" =~ ^([0-9]+)_([0-9]{8})\.pdf$ ]]; then
    ban="${BASH_REMATCH[1]}"
    date="${BASH_REMATCH[2]}"
    year="${date:0:4}"
    month="${date:4:2}"
    printf "%s,%s,%s\n" "$ban" "$year" "$month"
  fi
done | sort -u > "$TMP_HAVE"

# Write HAVE CSV
echo "ban,year,month" > "$OUT_HAVE"
cat "$TMP_HAVE" >> "$OUT_HAVE"

# --- If START/END not provided, just show existing and exit
if [[ -z "${START:-}" || -z "${END:-}" ]]; then
  echo
  echo "Present months (BAN, YEAR, MONTH):"
  column -t -s, "$OUT_HAVE"
  echo
  echo "Tip: set START=YYYY-MM and END=YYYY-MM to compute missing months."
  echo "Example:"
  echo "  export START=2024-10; export END=2025-03; ./scripts/list_coverage.sh"
  rm -f "$TMP_HAVE"
  exit 0
fi

# --- Build the expected month list (inclusive range)
# Helpers to move month cursor
to_ym() { printf "%04d-%02d" "$1" "$2"; }     # args: year month
next_ym() {                                   # echo next YYYY-MM
  local y m; IFS=- read -r y m <<<"$1"
  if (( m == 12 )); then
    printf "%04d-%02d" $((y+1)) 1
  else
    printf "%04d-%02d" "$y" $((m+1))
  fi
}

# Normalize inputs
if [[ ! "$START" =~ ^[0-9]{4}-[0-9]{2}$ ]] || [[ ! "$END" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
  echo "ERROR: START/END must be YYYY-MM (e.g., 2024-10)" >&2
  rm -f "$TMP_HAVE"
  exit 2
fi

# Expand expected YYYY-MM set
TMP_EXPECT="$(mktemp)"
cur="$START"
while :; do
  echo "$cur"
  [[ "$cur" == "$END" ]] && break
  cur="$(next_ym "$cur")"
done > "$TMP_EXPECT"

# Build maps:
#  present per BAN as YYYY-MM
#  expected for every BAN = the same $TMP_EXPECT list
declare -A present_map  # key="BAN|YYYY-MM" -> 1
declare -A bans         # set of BANs seen

while IFS=, read -r ban y m; do
  ym="$(to_ym "$y" "$m")"
  present_map["$ban|$ym"]=1
  bans["$ban"]=1
done < <(tail -n +2 "$OUT_HAVE")

# Compute missing per BAN
echo "ban,year,month" > "$OUT_MISS"
while IFS= read -r ym; do
  for ban in "${!bans[@]}"; do
    key="$ban|$ym"
    if [[ -z "${present_map[$key]:-}" ]]; then
      year="${ym:0:4}"; month="${ym:5:2}"
      printf "%s,%s,%s\n" "$ban" "$year" "$month" >> "$OUT_MISS"
    fi
  done
done < "$TMP_EXPECT"

# Pretty print a small summary
echo
echo "Present months:"
column -t -s, "$OUT_HAVE"

echo
echo "Missing months in range $START → $END:"
if [[ $(wc -l < "$OUT_MISS") -le 1 ]]; then
  echo "(none)"
else
  column -t -s, "$OUT_MISS"
fi

echo
echo "Wrote:"
echo "  $(readlink -f "$OUT_HAVE")"
echo "  $(readlink -f "$OUT_MISS")"

# Cleanup
rm -f "$TMP_HAVE" "$TMP_EXPECT"