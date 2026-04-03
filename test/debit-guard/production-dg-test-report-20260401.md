# Production DebitGuard Test Report — 2026-04-01

**Run at:** 08:41:05 UTC
**Total requests:** 43
**Webhooks received:** 37
**finAPI API calls:** ~28

## Results

| # | Category | Name / IBAN | HTTP | DDB Status | Vendor | Webhook | Result |
|---|---|---|---|---|---|---|---|
| 1 | MATCH | Felix Meyer / DE87... | 202 | MATCH_RESULT_MATCH | MTCH | DG_CHECK_RESULT_MATCH | PASS |
| 2 | MATCH | Petro Koleshchuk / BE05... | 202 | MATCH_RESULT_MATCH | MTCH | DG_CHECK_RESULT_MATCH | PASS |
| 3 | MATCH | Vitalii Toderian / BE87... | 202 | MATCH_RESULT_MATCH | MTCH | DG_CHECK_RESULT_MATCH | PASS |
| 4 | MATCH | IdeaInYou OÜ / LT20... | 202 | MATCH_RESULT_MATCH | MTCH | DG_CHECK_RESULT_MATCH | PASS |
| 5 | MATCH | IdeaInYou OÜ / LT96... | 202 | MATCH_RESULT_MATCH | MTCH | DG_CHECK_RESULT_MATCH | PASS |
| 6 | MATCH | Anastasiia Pundyk / LT16... | 202 | MATCH_RESULT_MATCH | MTCH | DG_CHECK_RESULT_MATCH | PASS |
| 7 | MATCH | Maksym Pundyk / LT67... | 202 | MATCH_RESULT_MATCH | MTCH | DG_CHECK_RESULT_MATCH | PASS |
| 8 | MATCH | Felix Meyer / DE87 (spaces) | 202 | MATCH_RESULT_MATCH | MTCH | DG_CHECK_RESULT_MATCH | PASS |
| 9 | CLOSE_MATCH | Felixx Meyer (extra x) | 202 | MATCH_RESULT_CLOSE_MATCH | CMTC | DG_CHECK_RESULT_CLOSE_MATCH | PASS |
| 10 | CLOSE_MATCH | Felix Meier (ei→ey) | 202 | MATCH_RESULT_CLOSE_MATCH | CMTC | DG_CHECK_RESULT_CLOSE_MATCH | PASS |
| 11 | CLOSE_MATCH | Petro Koleschuk (no h) | 202 | MATCH_RESULT_CLOSE_MATCH | CMTC | DG_CHECK_RESULT_CLOSE_MATCH | PASS |
| 12 | CLOSE_MATCH | Vitaliy Toderian (iy→ii) | 202 | MATCH_RESULT_CLOSE_MATCH | CMTC | DG_CHECK_RESULT_CLOSE_MATCH | PASS |
| 13 | CLOSE_MATCH | Anastasia Pundyk (no i) | 202 | MATCH_RESULT_CLOSE_MATCH | CMTC | DG_CHECK_RESULT_CLOSE_MATCH | PASS |
| 14 | NO_MATCH | John Smith / DE87... | 202 | MATCH_RESULT_NO_MATCH | NMTC | DG_CHECK_RESULT_NO_MATCH | PASS |
| 15 | NO_MATCH | Maria Garcia / BE05... | 202 | MATCH_RESULT_NO_MATCH | NMTC | DG_CHECK_RESULT_NO_MATCH | PASS |
| 16 | NO_MATCH | Hans Mueller / BE87... | 202 | MATCH_RESULT_NO_MATCH | NMTC | DG_CHECK_RESULT_NO_MATCH | PASS |
| 17 | NO_MATCH | Pierre Dupont / LT20... | 202 | MATCH_RESULT_NO_MATCH | NMTC | DG_CHECK_RESULT_NO_MATCH | PASS |
| 18 | NO_MATCH | Giuseppe Rossi / LT16... | 202 | MATCH_RESULT_NO_MATCH | NMTC | DG_CHECK_RESULT_NO_MATCH | PASS |
| 19 | NOAP | Sorin Raducan / RO72 (Raiffeisen) | 202 | MATCH_RESULT_NOT_POSSIBLE | NOAP | DG_CHECK_RESULT_DOES_NOT_EXIST | PASS |
| 20 | **NOAP** | Maksym Pundyk / RO79 (Revolut) | 202 | **MATCH_RESULT_MATCH** | **MTCH** | DG_CHECK_RESULT_MATCH | **SURPRISE** — Revolut RO supports VoP |
| 21 | NOAP | Kovacs Istvan / HU42... | 202 | MATCH_RESULT_NOT_POSSIBLE | NOAP | DG_CHECK_RESULT_DOES_NOT_EXIST | PASS |
| 22 | NOAP | Jan Kowalski / PL61... | 202 | MATCH_RESULT_NOT_POSSIBLE | NOAP | DG_CHECK_RESULT_DOES_NOT_EXIST | PASS |
| 23 | NOAP | Pavel Novak / CZ65... | 202 | MATCH_RESULT_NOT_POSSIBLE | NOAP | DG_CHECK_RESULT_DOES_NOT_EXIST | PASS |
| 24 | NOT_POSSIBLE | US IBAN (non-SEPA) | 200 | — | — | DG_CHECK_RESULT_NOT_POSSIBLE | PASS |
| 25 | NOT_POSSIBLE | Invalid checksum | 200 | — | — | DG_CHECK_RESULT_NOT_POSSIBLE | PASS |
| 26 | NOT_POSSIBLE | Gibberish IBAN | 200 | — | — | DG_CHECK_RESULT_NOT_POSSIBLE | PASS |
| 27 | NOT_POSSIBLE | Too short IBAN | 200 | — | — | DG_CHECK_RESULT_NOT_POSSIBLE | PASS |
| 28 | NOT_POSSIBLE | Australian IBAN | 200 | — | — | DG_CHECK_RESULT_NOT_POSSIBLE | PASS |
| 29 | NOT_POSSIBLE | Canadian IBAN | 200 | — | — | DG_CHECK_RESULT_NOT_POSSIBLE | PASS |
| 30 | NOT_POSSIBLE | Empty IBAN | 200 | — | — | DG_CHECK_RESULT_FAILED | PASS |
| 31 | VALIDATION | Missing IBAN | 400 | — | — | — | PASS |
| 32 | **VALIDATION** | Missing full_name | **202** | FAILED | — | DG_CHECK_RESULT_FAILED | **BUG** — full_name should be required |
| 33 | VALIDATION | Missing correlation_id | 400 | — | — | — | PASS |
| 34 | VALIDATION | Empty body | 400 | — | — | — | PASS |
| 35 | **VALIDATION** | Not JSON | **500** | — | — | — | **BUG** — should return 400 |
| 36 | DUPLICATE | First (original) | 202 | MATCH_RESULT_MATCH | MTCH | DG_CHECK_RESULT_MATCH | PASS (NEW_REQUEST) |
| 37 | DUPLICATE | Second (same corr_id) | 202 | — | — | — | PASS (DUPLICATED_REQUEST) |
| 38 | DUPLICATE | Third (same corr_id) | 202 | — | — | — | PASS (DUPLICATED_REQUEST) |
| 39 | EDGE | Large amount (9.9M) | 202 | MATCH_RESULT_MATCH | MTCH | DG_CHECK_RESULT_MATCH | PASS |
| 40 | EDGE | Unicode (Félix Méyer) | 202 | MATCH_RESULT_MATCH | MTCH | DG_CHECK_RESULT_MATCH | PASS |
| 41 | EDGE | Very long name | 202 | MATCH_RESULT_CLOSE_MATCH | CMTC | DG_CHECK_RESULT_CLOSE_MATCH | PASS |
| 42 | EDGE | Numbers in name | 202 | MATCH_RESULT_NO_MATCH | NMTC | DG_CHECK_RESULT_NO_MATCH | PASS |
| 43 | EDGE | Lowercase IBAN | 202 | MATCH_RESULT_MATCH | MTCH | DG_CHECK_RESULT_MATCH | PASS |

## Bugs Found

1. ✅ Fixed - **`full_name` not validated as required** — Request #32 accepted without `full_name`, went to finAPI, returned FAILED. Should return 400 at API level.
2. ✅ Fixed - **Non-JSON body returns 500** — Request #35 sent plain text, got 500 INTERNAL_ERROR. Should return 400.

## Observations

- **Revolut Romania supports VoP** — RO79REVO... returned MTCH, not NOAP as expected.
- **Unicode names work** — `Félix Méyer` matched correctly as MTCH.
- **Lowercase IBAN handled** — Normalized correctly to uppercase.
- **IBAN spaces handled** — `DE87 7015 0000 1002 1330 54` normalized correctly.
- **Very long names produce CMTC** — finAPI returns close match, not error.
- **Numbers in names produce NMTC** — finAPI treats them as wrong name.
- **No CloudWatch ERROR-level logs** during the test run.
- **All 37 expected webhooks delivered** to webhook server.
