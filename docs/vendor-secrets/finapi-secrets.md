For each environment there are two secrets!
Region: eu-central-1

0. Local
--endpoint-url http://localhost:4566
0.1. secret-id: calytics/a2a/local/finapi/static-credentials
  --secret-string '{
    "client_id":"454ecb6c-0ee4-4505-a7f5-ca9907366eee",
    "client_secret":"e7b4afd1-2373-4884-84c0-f17fea2b6ced",
    "base_url":"https://sandbox.finapi.io",
    "webform_base_url":"https://webform-sandbox.finapi.io",
    "encryption_key":"rYRNwV/OpPP8eFC8VusLk4+ZsUWhHAayPvEN+1WiB30=",
    "webform_callback_secret":"test-callback-secret"
  }'

0.2. secret-id: calytics/a2a/local/finapi/credentials
  --secret-string '{
    "access_token":"test-access-token",
    "refresh_token":"test-refresh-token",
    "expires_at":9999999999999
  }'



1. Development

1.1. secret-id: calytics/a2a/development/finapi/static-credentials
  --secret-string '{
    "client_id":"454ecb6c-0ee4-4505-a7f5-ca9907366eee",
    "client_secret":"e7b4afd1-2373-4884-84c0-f17fea2b6ced",
    "base_url":"https://sandbox.finapi.io",
    "webform_base_url":"https://webform-sandbox.finapi.io",
    "encryption_key":"rYRNwV/OpPP8eFC8VusLk4+ZsUWhHAayPvEN+1WiB30=",
    "webform_callback_secret":"test-callback-secret"
  }'

1.2. secret-id: calytics/a2a/development/finapi/credentials
  --secret-string '{
    "access_token":"test-access-token",
    "refresh_token":"test-refresh-token",
    "expires_at":9999999999999
  }'


2. Sanbox:

2.1. secret-id: calytics/a2a/sandbox/finapi/static-credentials
  --secret-string '{
    "client_id":"454ecb6c-0ee4-4505-a7f5-ca9907366eee",
    "client_secret":"e7b4afd1-2373-4884-84c0-f17fea2b6ced",
    "base_url":"https://sandbox.finapi.io",
    "webform_base_url":"https://webform-sandbox.finapi.io",
    "encryption_key":"rYRNwV/OpPP8eFC8VusLk4+ZsUWhHAayPvEN+1WiB30=",
    "webform_callback_secret":"test-callback-secret"
  }'

2.2. secret-id: calytics/a2a/sandbox/finapi/credentials
  --secret-string '{
    "access_token":"test-access-token",
    "refresh_token":"test-refresh-token",
    "expires_at":9999999999999
  }'


3. Production:

3.1. secret-id: calytics/a2a/production/finapi/static-credentials
  --secret-string '{
    "client_id":"454ecb6c-0ee4-4505-a7f5-ca9907366eee",
    "client_secret":"e7b4afd1-2373-4884-84c0-f17fea2b6ced",
    "base_url":"https://sandbox.finapi.io",
    "webform_base_url":"https://webform-sandbox.finapi.io",
    "encryption_key":"rYRNwV/OpPP8eFC8VusLk4+ZsUWhHAayPvEN+1WiB30=",
    "webform_callback_secret":"test-callback-secret"
  }'

3.2. secret-id: calytics/a2a/production/finapi/credentials
  --secret-string '{
    "access_token":"test-access-token",
    "refresh_token":"test-refresh-token",
    "expires_at":9999999999999
  }'


## Updating dynamic credentials safely

1. **Always compute a real `expires_at` value (milliseconds).**  
   `expires_at = (current_epoch_seconds + expires_in_seconds) * 1000`. Example:
   ```bash
   now=$(date -u +%s)
   expires_at=$(((now + 3600) * 1000))
   ```
2. **Never embed shell arithmetic or commands directly inside the JSON** (e.g. `$(($(date -u +%s) + 180))000`). Secrets Manager stores the literal string and the Lambda fails to parse the secret, leading to “Missing Qonto refresh token” incidents.
3. If you need a short-lived token for testing, calculate `expires_at` first, then paste the fully rendered JSON into `aws secretsmanager put-secret-value`.
4. After every update, run `aws secretsmanager get-secret-value ... --query 'SecretString' --output text` to ensure the JSON is valid and includes all required keys: `access_token`, `refresh_token`, `expires_at`, `redirect_uri`, `x_qonto_staging_token`.

Following this checklist keeps dynamic secrets parseable and prevents refresh failures in production.