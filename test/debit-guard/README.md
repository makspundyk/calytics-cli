# DebitGuard Production Test Suite

## Prerequisites

1. **Webhook server** (optional, for verifying webhook delivery):
   ```bash
   node docs/other/testing/webhook-server.js 3334
   ```

2. **ngrok** (optional, to expose webhook server to the internet):
   ```bash
   ngrok http 3334
   ```
   Then set the ngrok URL + `/webhook` as a webhook in Calytics Admin UI for the `DebitGuardVerificationStatusChanged` event.

3. **API key** — Set in the test script (`API_KEY` variable). Get from Calytics Admin UI.

## Running Tests

```bash
# From calytics-be root
bash scripts/test/debit-guard/production-dg-test-cases.sh
```

The script:
- Sends 43 requests covering all DebitGuard scenarios
- Prints results to console in real time
- Saves full responses to `production-dg-test-results-<timestamp>.json`
- Takes ~35 seconds to complete

## Test Scenarios

| Category | Count | finAPI calls | What it tests |
|---|---|---|---|
| MATCH | 8 | 8 | Real names + real IBANs from `real_iban_data.txt` |
| CLOSE_MATCH | 5 | 5 | Slight name typos (extra letter, swapped vowels) |
| NO_MATCH | 5 | 5 | Completely wrong names on valid IBANs |
| DOES_NOT_EXIST | 5 | 5 | Non-SEPA / unsupported bank IBANs (RO, HU, PL, CZ) |
| NOT_POSSIBLE | 7 | 0 | Invalid IBANs, non-SEPA countries — sync 200 response |
| VALIDATION | 5 | 0 | Missing fields, bad JSON — should return 400 |
| DUPLICATE | 3 | 1 | Same correlation_id sent 3 times — idempotency check |
| EDGE CASES | 5 | 5 | Unicode names, long names, lowercase IBAN, large amounts |

**Total: 43 requests, ~29 finAPI API calls**

## Verifying Results

### 1. Check webhook delivery
If webhook server is running:
```bash
curl http://localhost:3334/webhooks
```
Webhook files saved to `docs/other/testing/webhooks-<timestamp>.json`.

### 2. Check DynamoDB records
```bash
# Single transaction
aws dynamodb scan \
  --table-name calytics-be-production-verifications \
  --filter-expression "contains(PK, :tid)" \
  --expression-attribute-values '{":tid": {"S": "<transaction_id>"}}' \
  --region eu-central-1 \
  --query "Items[0].{status:status.S,vsvc:verification_service_status.S,vendor_status:vendor_status.S}"
```

### 3. Check CloudWatch logs
```bash
# Errors only
aws logs filter-log-events \
  --log-group-name "/aws/lambda/calytics-be-production-data-enrichment" \
  --filter-pattern '"level":50' \
  --start-time $(date -d '10 minutes ago' +%s000) \
  --region eu-central-1

# Specific transaction
aws logs filter-log-events \
  --log-group-name "/aws/lambda/calytics-be-production-data-enrichment" \
  --filter-pattern "<transaction_id>" \
  --start-time $(date -d '10 minutes ago' +%s000) \
  --region eu-central-1
```

## Files

| File | Purpose |
|---|---|
| `production-dg-test-cases.sh` | Test script with all 43 requests |
| `production-dg-test-results-*.json` | Raw API responses per run |
| `production-dg-test-report-*.md` | Human-readable test reports |
| `real_iban_data.txt` | Real IBAN + name pairs for MATCH tests |

## Modifying Tests

- **Add new IBANs**: Add to `real_iban_data.txt` and create a new `send_request` call in the MATCH section
- **Change API key**: Edit the `API_KEY` variable at the top of `production-dg-test-cases.sh`
- **Target sandbox**: Change `API_URL` to `https://api-sandbox.calytics.io/debit-guard/v1` and use sandbox API key
