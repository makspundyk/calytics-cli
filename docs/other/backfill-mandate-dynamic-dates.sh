#!/usr/bin/env bash
# Backfill mandate fields on Development Analytics Collects Mandate table with randomized mock data.
#
# Sets: debit_day, income_pattern, suggested_debit_day, amount, currency, signing_method,
#       iban, iban_hash, account_holder_name
# - iban_hash = SHA-256 hex of iban (uppercase), must stay in sync with iban (GSI3).
set -euo pipefail

TABLE_NAME="${1:-calytics-cc-development-mandates}"
REGION="${AWS_REGION:-eu-central-1}"

PATTERNS=(stable irregular undetected)
SIGNING_METHOD="BANK_VERIFIED_AIS"
CURRENCY="EUR"

# Random account holder names (first + last)
FIRST_NAMES=(Anna Bruno Clara David Emma Felix Gina Hans Iris Julia Klaus Lena Max Nora Paul Rita Stefan Tina Uwe Vera)
LAST_NAMES=(Mueller Schmidt Schneider Fischer Weber Meyer Wagner Becker Schulz Hoffmann Koch Richter Klein Wolf Schroeder Neumann Schwarz Zimmermann Braun)

# Generate random German-style IBAN (DE + 20 digits; mock only, check digits not validated)
random_iban() {
  echo -n "DE"
  for _ in {1..20}; do echo -n $((RANDOM % 10)); done
}

# SHA-256 hex of string (iban uppercase, same as code)
iban_hash() {
  printf '%s' "$1" | openssl dgst -sha256 -binary | xxd -p -c 256
}

echo "Scanning ${TABLE_NAME} for mandates..."
IDS=$(aws dynamodb scan --table-name "$TABLE_NAME" --region "$REGION" \
  --projection-expression "mandate_id" \
  --output json | jq -r '.Items[].mandate_id.S')

count=0
for mid in $IDS; do
  dd=$((RANDOM % 31 + 1))
  amount=$((50 + RANDOM % 251))
  idx=$((RANDOM % 3))
  ip="${PATTERNS[$idx]}"

  iban=$(random_iban)
  iban_hash_val=$(iban_hash "${iban^^}")
  first="${FIRST_NAMES[$((RANDOM % ${#FIRST_NAMES[@]}))]}"
  last="${LAST_NAMES[$((RANDOM % ${#LAST_NAMES[@]}))]}"
  account_holder="${first} ${last}"

  # Escape double quotes in account_holder for JSON
  account_holder_escaped="${account_holder//\"/\\\"}"

  if [[ "$ip" == "stable" || "$ip" == "irregular" ]]; then
    sd=$((RANDOM % 31 + 1))
    UPD="aws dynamodb update-item --table-name $TABLE_NAME --region $REGION --key '{\"mandate_id\":{\"S\":\"$mid\"}}' --update-expression 'SET debit_day = :dd, income_pattern = :ip, suggested_debit_day = :sd, #am = :am, currency = :cur, signing_method = :sm, iban = :iban, iban_hash = :ih, account_holder_name = :ahn' --expression-attribute-names '{\"#am\":\"amount\"}' --expression-attribute-values '{\":dd\":{\"N\":\"$dd\"},\":ip\":{\"S\":\"$ip\"},\":sd\":{\"N\":\"$sd\"},\":am\":{\"N\":\"$amount\"},\":cur\":{\"S\":\"$CURRENCY\"},\":sm\":{\"S\":\"$SIGNING_METHOD\"},\":iban\":{\"S\":\"$iban\"},\":ih\":{\"S\":\"$iban_hash_val\"},\":ahn\":{\"S\":\"$account_holder_escaped\"}}'"
    eval $UPD
    echo "  $mid -> iban=$iban, account_holder=$account_holder, debit_day=$dd, amount=${amount} EUR, income_pattern=$ip, suggested_debit_day=$sd"
  else
    UPD="aws dynamodb update-item --table-name $TABLE_NAME --region $REGION --key '{\"mandate_id\":{\"S\":\"$mid\"}}' --update-expression 'SET debit_day = :dd, income_pattern = :ip, #am = :am, currency = :cur, signing_method = :sm, iban = :iban, iban_hash = :ih, account_holder_name = :ahn REMOVE suggested_debit_day' --expression-attribute-names '{\"#am\":\"amount\"}' --expression-attribute-values '{\":dd\":{\"N\":\"$dd\"},\":ip\":{\"S\":\"$ip\"},\":am\":{\"N\":\"$amount\"},\":cur\":{\"S\":\"$CURRENCY\"},\":sm\":{\"S\":\"$SIGNING_METHOD\"},\":iban\":{\"S\":\"$iban\"},\":ih\":{\"S\":\"$iban_hash_val\"},\":ahn\":{\"S\":\"$account_holder_escaped\"}}'"
    eval $UPD
    echo "  $mid -> iban=$iban, account_holder=$account_holder, debit_day=$dd, amount=${amount} EUR, income_pattern=$ip, suggested_debit_day=(null)"
  fi
  ((count++)) || true
done

echo "Updated $count mandate(s)."
