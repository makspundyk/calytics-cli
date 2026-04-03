For each environment there are two secrets!
Region: eu-central-1

0. Local
--endpoint-url http://localhost:4566
0.1. secret-id: calytics/qonto/credentials
** redirect_uri: https://webhook.site/fd280d25-8aa6-48ce-8d4f-90e4d2bdb7ad
** x_qonto_staging_token: RtFadt3OLNmvzQeX3tqnXre5Y5+d1iEOv4K+af7m4hA=
** access_token, refresh_token, expires_at (in milliseconds !!)(calculated from expires_in) take from prompt

0.2. secret-id: calytics/qonto/static-credentials
** client-id: 5ba79b8a-8720-458c-8572-01e59a779f15
** client-secret: H8vmSqPUCn8DmCNbkxQMMoST6o



1. Development

1.1. secret-id: calytics/calytics-be/development/qonto/credentials
** redirect_uri: https://webhook.site/fd280d25-8aa6-48ce-8d4f-90e4d2bdb7ad
** x_qonto_staging_token: RtFadt3OLNmvzQeX3tqnXre5Y5+d1iEOv4K+af7m4hA=
** access_token, refresh_token, expires_at (in milliseconds !!)(calculated from expires_in) take from prompt

1.2. secret-id: calytics/calytics-be/development/qonto/static-credentials
** client-id: 5ba79b8a-8720-458c-8572-01e59a779f15
** client-secret: H8vmSqPUCn8DmCNbkxQMMoST6o


2. Sanbox:

2.1. secret-id: calytics/calytics-be/sandbox/qonto/credentials
** redirect_uri: https://webhook.site/fd280d25-8aa6-48ce-8d4f-90e4d2bdb7ad
** x_qonto_staging_token: +TuAry2TDiimDwiENe5VYzlpiGdSmmq0cWr/MGj6Jns=
** access_token, refresh_token, expires_at (in milliseconds !!)(calculated from expires_in) take from prompt

2.2. secret-id: calytics/calytics-be/sandbox/qonto/static-credentials
** client-id: 94286cbf-db8e-421a-b11f-5603ddb45174
** client-secret: ZIG75NoxlRi4z79SThGOorD9jN


3. Production:

3.1. secret-id: calytics/calytics-be/production/qonto/credentials
** redirect_uri: https://webhook.site/fd280d25-8aa6-48ce-8d4f-90e4d2bdb7ad
** x_qonto_staging_token: JGSzVPSAqmSOWfnW3ccZ+dEZF+P+BpHxFfVr6yC79bE=
** access_token, refresh_token, expires_at (in milliseconds !!)(calculated from expires_in) take from prompt

3.2. secret-id: calytics/calytics-be/production/qonto/static-credentials
** client-id: d69b8a1e-9ea3-4357-9a5f-68e80770bb0f
** client-secret: PkMSiuD4kgcz9k02IwqmasSx4n


4. Local - Production
--endpoint-url http://localhost:4566
4.1. secret-id: calytics/qonto/credentials
** redirect_uri: https://webhook-test.com/52cff5b907e24e1ce40e14c40ba75551
** x_qonto_staging_token: RtFadt3OLNmvzQeX3tqnXre5Y5+d1iEOv4K+af7m4hA=
** access_token, refresh_token, expires_at (in milliseconds !!)(calculated from expires_in) take from prompt

4.2. secret-id: calytics/qonto/static-credentials
** client-id: a8d842da-5f7e-492c-9124-e269ba40912b
** client-secret: Swlex2L1YT7qTTKuWrA2O4E2H0
---

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