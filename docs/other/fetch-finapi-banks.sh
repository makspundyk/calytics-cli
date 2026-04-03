#!/bin/bash

# Fetch all banks from finAPI production API
# Usage: ./scripts/fetch-finapi-banks.sh

set -e

# ── Prompt for credentials ──────────────────────────────────────────────────

read -rp "Client ID: " CLIENT_ID
read -rsp "Client Secret: " CLIENT_SECRET
echo

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
    echo "Error: Client ID and Client Secret are required."
    exit 1
fi

BASE_URL="https://live.finapi.io"
OUTPUT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JSON_FILE="$OUTPUT_DIR/finapi_banks.json"
CSV_FILE="$OUTPUT_DIR/finapi_banks.csv"

# ── Get OAuth token ─────────────────────────────────────────────────────────

echo "Authenticating with finAPI..."

TOKEN_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v2/oauth/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&grant_type=client_credentials")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)

if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "Error: Failed to get access token."
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

echo "Authenticated successfully."

# ── Fetch all banks (paginated) ─────────────────────────────────────────────

echo "Fetching banks..."

python3 - "$BASE_URL" "$ACCESS_TOKEN" "$JSON_FILE" "$CSV_FILE" << 'PYEOF'
import json, urllib.request, csv, sys

base_url = sys.argv[1]
token = sys.argv[2]
json_file = sys.argv[3]
csv_file = sys.argv[4]

all_banks = []
page = 1

while True:
    url = f"{base_url}/api/v2/banks?perPage=500&page={page}&isTestBank=false"
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/json"
    })
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())

    banks = data.get("banks", [])
    paging = data.get("paging", {})
    total_pages = paging.get("pageCount", 0)

    all_banks.extend(banks)
    print(f"  Page {page}/{total_pages} — {len(all_banks)} banks so far")

    if page >= total_pages:
        break
    page += 1

# Save JSON
with open(json_file, "w") as f:
    json.dump({"totalCount": len(all_banks), "banks": all_banks}, f, indent=2)

# Save CSV
with open(csv_file, "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["id", "name", "bic", "blz", "city", "country", "banking_interfaces"])
    for b in all_banks:
        interfaces = ", ".join(
            iface.get("bankingInterface", "") for iface in b.get("interfaces", [])
        )
        writer.writerow([
            b.get("id", ""),
            b.get("name", ""),
            b.get("bic", ""),
            b.get("blz", ""),
            b.get("city", ""),
            b.get("location", ""),
            interfaces,
        ])

print(f"\nDone! {len(all_banks)} banks saved to:")
print(f"  JSON: {json_file}")
print(f"  CSV:  {csv_file}")
PYEOF
