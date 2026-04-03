#!/bin/bash

# =============================================================================
# Production DebitGuard Test Suite
# =============================================================================
# 50 total requests, ≤30 finAPI ibanNameCheck API calls
#
# Breakdown:
#   MATCH scenarios:        8 requests  (real names + real IBANs)
#   CLOSE_MATCH scenarios:  5 requests  (slight name typos)
#   NO_MATCH scenarios:     5 requests  (wrong names on valid IBANs)
#   DOES_NOT_EXIST (NOAP):  5 requests  (non-SEPA / unsupported bank IBANs)
#   NOT_POSSIBLE (sync):    7 requests  (invalid IBANs, non-SEPA countries — no finAPI call)
#   VALIDATION_ERROR:       5 requests  (missing fields, bad format — no finAPI call)
#   DUPLICATE:              3 requests  (same correlation_id — no finAPI call)
#   ERROR_SIMULATION:       2 requests  (error IBAN if configured)
#
# Total finAPI calls: ~25 (MATCH+CLOSE+NO_MATCH+NOAP+ERROR = 25)
# =============================================================================

API_URL="https://api.calytics.io/debit-guard/v1"
API_KEY="ak_prod_e22f0e065bbd6befb7a4196c9e9afcc0ad332b09856ffeeab59270cd32b53bb8"
RESULTS_FILE="$(dirname "$0")/production-dg-test-results-$(date -u +%Y%m%dT%H%M%S).json"

echo "[]" > "$RESULTS_FILE"
REQUEST_NUM=0

send_request() {
    local description="$1"
    local payload="$2"
    REQUEST_NUM=$((REQUEST_NUM + 1))

    echo "[$REQUEST_NUM] $description"

    response=$(curl -s -w "\n%{http_code}" --location "$API_URL" \
        --header "Content-Type: application/json" \
        --header "x-api-key: $API_KEY" \
        --data-raw "$payload")

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    echo "    HTTP $http_code | $(echo "$body" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(f"tx={d.get(\"transaction_id\",\"N/A\")[:12]}... status={d.get(\"status\",\"N/A\")}")' 2>/dev/null || echo "$body" | head -c 120)"

    # Append to results file
    python3 -c "
import json, sys
results = json.load(open('$RESULTS_FILE'))
results.append({
    'request_num': $REQUEST_NUM,
    'description': '''$description''',
    'http_code': $http_code,
    'response': json.loads('''$body''') if '''$body'''.strip().startswith('{') else '''$body'''
})
json.dump(results, open('$RESULTS_FILE', 'w'), indent=2)
" 2>/dev/null

    # Small delay to avoid overwhelming the API
    sleep 0.3
}

echo "=========================================="
echo "Production DebitGuard Test Suite"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Results: $RESULTS_FILE"
echo "=========================================="

# =============================================================================
# MATCH scenarios (8) — Real names + real IBANs → MTCH from finAPI
# =============================================================================

send_request "MATCH: Felix Meyer - DE IBAN" '{
    "iban": "DE87701500001002133054",
    "full_name": "Felix Meyer",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-001", "tenant_group": "match-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "185.220.101.42", "total_amount": 250.00, "currency": "EUR",
    "customer_information": {"age": 35, "email": "felix.m@example.de", "country": "Germany", "address": "Marienplatz 1, Munich"}
}'

send_request "MATCH: Petro Koleshchuk - BE IBAN" '{
    "iban": "BE05967500210875",
    "full_name": "Petro Koleshchuk",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-002", "tenant_group": "match-tests",
    "payment_provider": "adyen", "banking_country": "BE",
    "ip_address": "91.183.45.12", "total_amount": 89.99, "currency": "EUR",
    "customer_information": {"age": 28, "email": "petro.k@example.be", "country": "Belgium", "address": "Rue de la Loi 16, Brussels"}
}'

send_request "MATCH: Vitalii Toderian - BE IBAN" '{
    "iban": "BE87967346807294",
    "full_name": "Vitalii Toderian",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-003", "tenant_group": "match-tests",
    "payment_provider": "mollie", "banking_country": "BE",
    "ip_address": "77.109.141.66", "total_amount": 450.50, "currency": "EUR",
    "customer_information": {"age": 31, "email": "vitalii.t@example.be", "country": "Belgium", "address": "Grand Place 5, Antwerp"}
}'

send_request "MATCH: IdeaInYou OÜ - LT IBAN (1)" '{
    "iban": "LT203500010016677174",
    "full_name": "IdeaInYou OÜ",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-004", "tenant_group": "match-tests",
    "payment_provider": "revolut", "banking_country": "LT",
    "ip_address": "88.119.50.33", "total_amount": 12500.00, "currency": "EUR",
    "customer_information": {"age": 0, "email": "billing@ideainyou.com", "country": "Estonia", "address": "Tallinn, Harju"}
}'

send_request "MATCH: IdeaInYou OÜ - LT IBAN (2)" '{
    "iban": "LT963500010016692102",
    "full_name": "IdeaInYou OÜ",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-005", "tenant_group": "match-tests",
    "payment_provider": "revolut", "banking_country": "LT",
    "ip_address": "88.119.50.34", "total_amount": 7800.00, "currency": "EUR",
    "customer_information": {"age": 0, "email": "finance@ideainyou.com", "country": "Estonia", "address": "Tallinn, Harju"}
}'

send_request "MATCH: Anastasiia Pundyk - LT IBAN" '{
    "iban": "LT163500010018665261",
    "full_name": "Anastasiia Pundyk",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-006", "tenant_group": "match-tests",
    "payment_provider": "wise", "banking_country": "LT",
    "ip_address": "178.54.210.88", "total_amount": 320.00, "currency": "EUR",
    "customer_information": {"age": 27, "email": "anastasiia.p@example.com", "country": "Ukraine", "address": "Kyiv, Shevchenko Blvd 12"}
}'

send_request "MATCH: Maksym Pundyk - LT IBAN" '{
    "iban": "LT673500010016584760",
    "full_name": "Maksym Pundyk",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-007", "tenant_group": "match-tests",
    "payment_provider": "revolut", "banking_country": "LT",
    "ip_address": "178.54.210.90", "total_amount": 1500.00, "currency": "EUR",
    "customer_information": {"age": 30, "email": "maksym.p@example.com", "country": "Ukraine", "address": "Kyiv, Lesya Ukrainka 25"}
}'

send_request "MATCH: Felix Meyer - DE IBAN (spaces)" '{
    "iban": "DE87 7015 0000 1002 1330 54",
    "full_name": "Felix Meyer",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-008", "tenant_group": "match-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "185.220.101.43", "total_amount": 99.95, "currency": "EUR",
    "customer_information": {"age": 35, "email": "felix@example.de", "country": "Germany", "address": "Alexanderplatz 7, Berlin"}
}'

# =============================================================================
# CLOSE_MATCH scenarios (5) — Slight name typos → CMTC from finAPI
# =============================================================================

send_request "CLOSE_MATCH: Felixx Meyer (extra x)" '{
    "iban": "DE87701500001002133054",
    "full_name": "Felixx Meyer",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-009", "tenant_group": "close-match-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "203.0.113.10", "total_amount": 175.00, "currency": "EUR",
    "customer_information": {"age": 35, "email": "felixx@example.de", "country": "Germany", "address": "Hamburg, Reeperbahn 1"}
}'

send_request "CLOSE_MATCH: Felix Meier (ei instead of ey)" '{
    "iban": "DE87701500001002133054",
    "full_name": "Felix Meier",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-010", "tenant_group": "close-match-tests",
    "payment_provider": "adyen", "banking_country": "DE",
    "ip_address": "203.0.113.11", "total_amount": 340.00, "currency": "EUR",
    "customer_information": {"age": 36, "email": "felix.meier@example.de", "country": "Germany", "address": "Frankfurt, Zeil 50"}
}'

send_request "CLOSE_MATCH: Petro Koleschuk (missing h)" '{
    "iban": "BE05967500210875",
    "full_name": "Petro Koleschuk",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-011", "tenant_group": "close-match-tests",
    "payment_provider": "mollie", "banking_country": "BE",
    "ip_address": "203.0.113.12", "total_amount": 55.00, "currency": "EUR",
    "customer_information": {"age": 28, "email": "petro.k2@example.be", "country": "Belgium", "address": "Ghent, Veldstraat 10"}
}'

send_request "CLOSE_MATCH: Vitaliy Toderian (iy instead of ii)" '{
    "iban": "BE87967346807294",
    "full_name": "Vitaliy Toderian",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-012", "tenant_group": "close-match-tests",
    "payment_provider": "adyen", "banking_country": "BE",
    "ip_address": "203.0.113.13", "total_amount": 220.00, "currency": "EUR",
    "customer_information": {"age": 31, "email": "vitaliy.t@example.be", "country": "Belgium", "address": "Liege, Place du Marche 3"}
}'

send_request "CLOSE_MATCH: Anastasia Pundyk (missing i)" '{
    "iban": "LT163500010018665261",
    "full_name": "Anastasia Pundyk",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-013", "tenant_group": "close-match-tests",
    "payment_provider": "wise", "banking_country": "LT",
    "ip_address": "203.0.113.14", "total_amount": 180.00, "currency": "EUR",
    "customer_information": {"age": 27, "email": "anastasia.p@example.com", "country": "Ukraine", "address": "Lviv, Rynok Square 1"}
}'

# =============================================================================
# NO_MATCH scenarios (5) — Wrong names on valid IBANs → NMTC from finAPI
# =============================================================================

send_request "NO_MATCH: John Smith on Felix's IBAN" '{
    "iban": "DE87701500001002133054",
    "full_name": "John Smith",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-014", "tenant_group": "no-match-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "198.51.100.10", "total_amount": 500.00, "currency": "EUR",
    "customer_information": {"age": 45, "email": "john.smith@example.com", "country": "UK", "address": "London, Baker Street 221B"}
}'

send_request "NO_MATCH: Maria Garcia on Petro's IBAN" '{
    "iban": "BE05967500210875",
    "full_name": "Maria Garcia",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-015", "tenant_group": "no-match-tests",
    "payment_provider": "mollie", "banking_country": "BE",
    "ip_address": "198.51.100.11", "total_amount": 75.00, "currency": "EUR",
    "customer_information": {"age": 38, "email": "maria.g@example.es", "country": "Spain", "address": "Madrid, Gran Via 28"}
}'

send_request "NO_MATCH: Hans Mueller on Vitalii's IBAN" '{
    "iban": "BE87967346807294",
    "full_name": "Hans Mueller",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-016", "tenant_group": "no-match-tests",
    "payment_provider": "adyen", "banking_country": "BE",
    "ip_address": "198.51.100.12", "total_amount": 1200.00, "currency": "EUR",
    "customer_information": {"age": 52, "email": "hans.m@example.de", "country": "Germany", "address": "Stuttgart, Konigstrasse 15"}
}'

send_request "NO_MATCH: Pierre Dupont on IdeaInYou IBAN" '{
    "iban": "LT203500010016677174",
    "full_name": "Pierre Dupont",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-017", "tenant_group": "no-match-tests",
    "payment_provider": "revolut", "banking_country": "LT",
    "ip_address": "198.51.100.13", "total_amount": 3200.00, "currency": "EUR",
    "customer_information": {"age": 41, "email": "pierre.d@example.fr", "country": "France", "address": "Paris, Rue de Rivoli 100"}
}'

send_request "NO_MATCH: Totally Wrong Name on Anastasiia's IBAN" '{
    "iban": "LT163500010018665261",
    "full_name": "Giuseppe Rossi",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-018", "tenant_group": "no-match-tests",
    "payment_provider": "wise", "banking_country": "LT",
    "ip_address": "198.51.100.14", "total_amount": 95.00, "currency": "EUR",
    "customer_information": {"age": 33, "email": "giuseppe.r@example.it", "country": "Italy", "address": "Rome, Via del Corso 50"}
}'

# =============================================================================
# DOES_NOT_EXIST / NOAP scenarios (5) — Banks that don't support VoP
# =============================================================================

send_request "NOAP: Romanian IBAN (Raiffeisen)" '{
    "iban": "RO72RZBR0000060018920305",
    "full_name": "Sorin Raducan",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-019", "tenant_group": "noap-tests",
    "payment_provider": "revolut", "banking_country": "RO",
    "ip_address": "86.121.12.19", "total_amount": 600.00, "currency": "EUR",
    "customer_information": {"age": 40, "email": "sorin.r@example.ro", "country": "Romania", "address": "Bucharest, Calea Victoriei 100"}
}'

send_request "NOAP: Romanian IBAN (Revolut)" '{
    "iban": "RO79REVO0000138762239233",
    "full_name": "Maksym Pundyk",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-020", "tenant_group": "noap-tests",
    "payment_provider": "revolut", "banking_country": "RO",
    "ip_address": "178.54.210.91", "total_amount": 2000.00, "currency": "EUR",
    "customer_information": {"age": 30, "email": "maksym.p2@example.com", "country": "Romania", "address": "Cluj-Napoca, Str. Napoca 10"}
}'

send_request "NOAP: Hungarian IBAN" '{
    "iban": "HU42117730161111101800000000",
    "full_name": "Kovacs Istvan",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-021", "tenant_group": "noap-tests",
    "payment_provider": "adyen", "banking_country": "HU",
    "ip_address": "188.142.160.5", "total_amount": 150.00, "currency": "EUR",
    "customer_information": {"age": 47, "email": "kovacs.i@example.hu", "country": "Hungary", "address": "Budapest, Andrassy ut 60"}
}'

send_request "NOAP: Polish IBAN" '{
    "iban": "PL61109010140000071219812874",
    "full_name": "Jan Kowalski",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-022", "tenant_group": "noap-tests",
    "payment_provider": "przelewy24", "banking_country": "PL",
    "ip_address": "83.27.144.20", "total_amount": 430.00, "currency": "PLN",
    "customer_information": {"age": 36, "email": "jan.k@example.pl", "country": "Poland", "address": "Warsaw, Nowy Swiat 33"}
}'

send_request "NOAP: Czech IBAN" '{
    "iban": "CZ6508000000192000145399",
    "full_name": "Pavel Novak",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-023", "tenant_group": "noap-tests",
    "payment_provider": "adyen", "banking_country": "CZ",
    "ip_address": "77.75.79.100", "total_amount": 280.00, "currency": "CZK",
    "customer_information": {"age": 29, "email": "pavel.n@example.cz", "country": "Czech Republic", "address": "Prague, Vaclavske namesti 1"}
}'

# =============================================================================
# NOT_POSSIBLE scenarios (7) — Invalid IBANs / non-SEPA → sync 200, no finAPI call
# =============================================================================

send_request "NOT_POSSIBLE: US IBAN (non-SEPA)" '{
    "iban": "US64SVBKUS6S3300958879",
    "full_name": "James Wilson",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-024", "tenant_group": "not-possible-tests",
    "payment_provider": "stripe", "banking_country": "US",
    "ip_address": "8.8.8.8", "total_amount": 999.99, "currency": "USD",
    "customer_information": {"age": 50, "email": "james.w@example.com", "country": "USA", "address": "New York, 5th Avenue 100"}
}'

send_request "NOT_POSSIBLE: Invalid checksum IBAN" '{
    "iban": "DE00000000000000000000",
    "full_name": "Test Invalid",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-025", "tenant_group": "not-possible-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "192.168.1.1", "total_amount": 100.00, "currency": "EUR",
    "customer_information": {"age": 25, "email": "test@example.com", "country": "Germany", "address": "Berlin, Test St 1"}
}'

send_request "NOT_POSSIBLE: Gibberish IBAN" '{
    "iban": "XYZABC123456789",
    "full_name": "Nobody Real",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-026", "tenant_group": "not-possible-tests",
    "payment_provider": "adyen", "banking_country": "XX",
    "ip_address": "10.0.0.1", "total_amount": 50.00, "currency": "EUR",
    "customer_information": {"age": 20, "email": "nobody@example.com", "country": "Nowhere", "address": "Unknown"}
}'

send_request "NOT_POSSIBLE: Too short IBAN" '{
    "iban": "DE1234",
    "full_name": "Short Iban",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-027", "tenant_group": "not-possible-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "172.16.0.1", "total_amount": 10.00, "currency": "EUR",
    "customer_information": {"age": 22, "email": "short@example.com", "country": "Germany", "address": "Munich, Short St"}
}'

send_request "NOT_POSSIBLE: Australian IBAN (non-SEPA)" '{
    "iban": "AU45932000123456789",
    "full_name": "Bruce Wayne",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-028", "tenant_group": "not-possible-tests",
    "payment_provider": "stripe", "banking_country": "AU",
    "ip_address": "1.1.1.1", "total_amount": 750.00, "currency": "AUD",
    "customer_information": {"age": 40, "email": "bruce@example.au", "country": "Australia", "address": "Sydney, Harbour Bridge 1"}
}'

send_request "NOT_POSSIBLE: Canadian account (non-SEPA)" '{
    "iban": "CA12345678901234567890",
    "full_name": "Wayne Gretzky",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-029", "tenant_group": "not-possible-tests",
    "payment_provider": "stripe", "banking_country": "CA",
    "ip_address": "24.114.50.10", "total_amount": 1100.00, "currency": "CAD",
    "customer_information": {"age": 60, "email": "wayne.g@example.ca", "country": "Canada", "address": "Toronto, Bay Street 99"}
}'

send_request "NOT_POSSIBLE: Empty IBAN" '{
    "iban": "",
    "full_name": "Empty Iban Person",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-030", "tenant_group": "not-possible-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "127.0.0.1", "total_amount": 0.01, "currency": "EUR",
    "customer_information": {"age": 18, "email": "empty@example.com", "country": "Germany", "address": "Nowhere"}
}'

# =============================================================================
# VALIDATION_ERROR scenarios (5) — Missing required fields → 400, no finAPI call
# =============================================================================

send_request "VALIDATION: Missing IBAN field" '{
    "full_name": "Missing Iban",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-031", "tenant_group": "validation-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "127.0.0.1", "total_amount": 100.00, "currency": "EUR",
    "customer_information": {"age": 30, "email": "no.iban@example.com", "country": "Germany", "address": "Berlin"}
}'

send_request "VALIDATION: Missing full_name field" '{
    "iban": "DE87701500001002133054",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-032", "tenant_group": "validation-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "127.0.0.1", "total_amount": 100.00, "currency": "EUR",
    "customer_information": {"age": 30, "email": "no.name@example.com", "country": "Germany", "address": "Berlin"}
}'

send_request "VALIDATION: Missing correlation_id" '{
    "iban": "DE87701500001002133054",
    "full_name": "Felix Meyer",
    "tenant_id": "prod-test-033", "tenant_group": "validation-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "127.0.0.1", "total_amount": 100.00, "currency": "EUR",
    "customer_information": {"age": 35, "email": "no.corr@example.com", "country": "Germany", "address": "Berlin"}
}'

send_request "VALIDATION: Empty body" '{}'

send_request "VALIDATION: Not JSON at all" 'this is not json at all'

# =============================================================================
# DUPLICATE scenarios (3) — Same correlation_id → should be idempotent
# =============================================================================

DUPLICATE_CORR_ID=$(uuidgen)

send_request "DUPLICATE: First request (original)" '{
    "iban": "DE87701500001002133054",
    "full_name": "Felix Meyer",
    "correlation_id": "'$DUPLICATE_CORR_ID'",
    "tenant_id": "prod-test-036", "tenant_group": "duplicate-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "185.220.101.44", "total_amount": 500.00, "currency": "EUR",
    "customer_information": {"age": 35, "email": "felix.dup@example.de", "country": "Germany", "address": "Berlin, Unter den Linden 1"}
}'

sleep 2

send_request "DUPLICATE: Second request (same correlation_id)" '{
    "iban": "DE87701500001002133054",
    "full_name": "Felix Meyer",
    "correlation_id": "'$DUPLICATE_CORR_ID'",
    "tenant_id": "prod-test-036", "tenant_group": "duplicate-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "185.220.101.44", "total_amount": 500.00, "currency": "EUR",
    "customer_information": {"age": 35, "email": "felix.dup@example.de", "country": "Germany", "address": "Berlin, Unter den Linden 1"}
}'

send_request "DUPLICATE: Third request (same correlation_id)" '{
    "iban": "DE87701500001002133054",
    "full_name": "Felix Meyer",
    "correlation_id": "'$DUPLICATE_CORR_ID'",
    "tenant_id": "prod-test-036", "tenant_group": "duplicate-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "185.220.101.44", "total_amount": 500.00, "currency": "EUR",
    "customer_information": {"age": 35, "email": "felix.dup@example.de", "country": "Germany", "address": "Berlin, Unter den Linden 1"}
}'

# =============================================================================
# LARGE AMOUNT / EDGE CASES (5) — Various edge cases
# =============================================================================

send_request "EDGE: Very large amount" '{
    "iban": "DE87701500001002133054",
    "full_name": "Felix Meyer",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-039", "tenant_group": "edge-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "185.220.101.45", "total_amount": 9999999.99, "currency": "EUR",
    "customer_information": {"age": 35, "email": "felix.big@example.de", "country": "Germany", "address": "Munich, Maximilianstrasse 1"}
}'

send_request "EDGE: Unicode name with accents" '{
    "iban": "DE87701500001002133054",
    "full_name": "Félix Méyer",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-040", "tenant_group": "edge-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "185.220.101.46", "total_amount": 150.00, "currency": "EUR",
    "customer_information": {"age": 35, "email": "felix.accent@example.de", "country": "Germany", "address": "Cologne, Dom Platz 1"}
}'

send_request "EDGE: Very long name" '{
    "iban": "BE05967500210875",
    "full_name": "Petro Oleksandrovych Koleshchuk-Von Der Lansen Bergerstein III",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-041", "tenant_group": "edge-tests",
    "payment_provider": "mollie", "banking_country": "BE",
    "ip_address": "91.183.45.13", "total_amount": 42.00, "currency": "EUR",
    "customer_information": {"age": 28, "email": "petro.long@example.be", "country": "Belgium", "address": "Bruges, Markt 7"}
}'

send_request "EDGE: Name with numbers" '{
    "iban": "DE87701500001002133054",
    "full_name": "Felix123 Meyer456",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-042", "tenant_group": "edge-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "185.220.101.47", "total_amount": 77.77, "currency": "EUR",
    "customer_information": {"age": 35, "email": "felix.num@example.de", "country": "Germany", "address": "Dusseldorf, Konigsallee 1"}
}'

send_request "EDGE: Lowercase IBAN" '{
    "iban": "de87701500001002133054",
    "full_name": "Felix Meyer",
    "correlation_id": "'$(uuidgen)'",
    "tenant_id": "prod-test-043", "tenant_group": "edge-tests",
    "payment_provider": "stripe", "banking_country": "DE",
    "ip_address": "185.220.101.48", "total_amount": 200.00, "currency": "EUR",
    "customer_information": {"age": 35, "email": "felix.lower@example.de", "country": "Germany", "address": "Leipzig, Augustusplatz 1"}
}'

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "=========================================="
echo "Test Suite Complete"
echo "Total requests: $REQUEST_NUM"
echo "Results saved: $RESULTS_FILE"
echo "Finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=========================================="
