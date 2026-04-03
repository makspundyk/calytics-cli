For each environment there are two secrets!
Region: eu-central-1

0. Local
--endpoint-url http://localhost:4566
(Usually uses Sandbox or Development credentials for local testing)
0.1. secret-id: calytics/calytics-be/local/revolut/credentials
** access_token: take from prompt
** expires_at: (in milliseconds !!)(calculated from expires_in) take from prompt
** client_assertion: take from prompt

0.2. secret-id: calytics/calytics-be/local/revolut/static-credentials
** client_id: hM6yqyGA6drWxzpsXRpLOonnoeJtw0pTr70SyKm4T24
** refresh_token: oa_sand_r7ye9YW2renXYNHwijNLRoIX-fgWcOzQNsf_fl5KRJw
** private_key: (Multi-line PEM format): 
"-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDkAzNL7ahEHg6V
XCgtISzfTAtRc8fkqSbCUppRtOha9lV5HK919d/o1GQK9a0KaEpdzxPqmWy9ixR/
GR0Xtc3IWDONFOQNU1eQT0luZ5wua65fop0av8f7iyEl0ii/okr9bmqPDIlBFqHm
jjebWr5nzvmzDuy2dSXUywUBGH81wT/W7zF08CBIAj3ltVJe4tHkPiwJTtevwbj1
2ADch0N6ExtikVOSsnxTSyXRixeDeTtkLmT9Yc2DbKuq0y+KACS6eeua/oJRFXud
5BWUf2GVIW2IEI3L6EpRm7Jo67bKUlH+q0d190g4/4lF3+lrXmndgijzI6mw8ZOQ
Ww9loYONAgMBAAECgf9I9SBLfeD+oHNqewoz6quqzPzdI7tQ8JJdkF3WCSWaUxFT
cuKLRKrvyg4+WruH2EqeBrfPFFZRLCRrEFPFpYTooR6/WyQyJ5yCPeS3hP68Ak06
MRs3u3spHUsE2g4US624jaGWCJjlMn9AlkwAYXFnpO4PZZNbQhXFjVcf2VZyVVf/
boSmuvHx2xrxewBX1YQNjyagp9En4dUIgR2xHfdR/RfiFI4qXa0xIOskZRHBGiMZ
rTfcU+2kpb2chnsAMwHN0UOOQGZjXqDJA9SeRJWVsLdhSRlb1xu/E4/mAPjPoQ26
l1W7r8vSkIBlyGCQBAw52z1NczgXp2W/2EdIm1kCgYEA9Yju+9dHfnuczHmWQyIs
uybJMn05ifUYpSKmPaBFb2wLPUmWblrfr9YnGqn7An+PtUsTksAq1WTpSrt89P/+
gjnl/TPgWVX4lF/5HtUPe6P4lqPbj/p/bWqNzX20i6TdP2NH4ndgZNoKDS8y8jRP
yhWsQkaK/PKxVDvWUm+ZaFsCgYEA7bsT1cjwIIdsT2dVZzpNWOQaYM1GuXNIkat/
U4Z3lt8xYytbYbpayUzsHcyOjB1Rs5IxapHn2fc2EIzZvSENTgKa4IAnxngaVQxb
kGRUakRhS5UHVng+m2NrMOkClETY9xvK7sSfA0iGyVRtHXQQjDTP+hrh6mR8lSOs
Tfd/yDcCgYEA58JM8eIOVdEP++F4d/22AyFlIAcbXKDAln7SM7EoWTe+lCb1m0yj
fzHAz2ZKy9zkJNesrgQ9ahdKLYQzOn64GOvVrt5ckXaYoFTGrNenOalYZ7ha8tgb
l4fQOXrCBF2liMOJgrXzgr5cZn16tSuzdKhoZFZ5srDRuRSSBFXak6kCgYEAzg9I
JBhlu2xmv3TMHAv3G0OscZe84+Y/UrSaSuXVJtsTTeg47z6+jpm0WCgErwKC3Omt
F7ichNu46yOLYFoT1DiB0nKDB473FB0ACOpOGUZoJ0Fn+NWFPt8v/FccOzRp89cN
UWTwh8IHwt8BLXR7G2xzkVBX3fl32zXuli4ffoUCgYByeoN5kiyOzyv0pWpMmZdM
Ja6gl6zz6w9xYYEFleyOukwDpXBSt1nifMR670xST3vQR79j+7+nX2AeXJRZfYPw
DWxa0qR7mcvCVEpxndce4WiJ4fvro9pVXMuv5qRQeMKXRGEpbkpGsea7QIZ7CgFI
KZCvUTrUJlpcOKi1zvxsgg==
-----END PRIVATE KEY-----"
** redirect_domain: webhook.site

1. Development

1.1. secret-id: calytics/calytics-be/development/revolut/credentials
** access_token: take from prompt
** expires_at: (in milliseconds !!)(calculated from expires_in) take from prompt
** client_assertion: take from prompt

1.2. secret-id: calytics/calytics-be/development/revolut/static-credentials
** client_id: iT20x3LppeUpMfnI7FBEEJvCO5QgcfbqaLBy5xKHTMQ
** refresh_token: oa_sand_o8ab1Lny7SW5vBP5869ElqPu-__C4tjJVPCGLCWyRRA
** private_key: (Multi-line PEM format):
"-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDkAzNL7ahEHg6V
XCgtISzfTAtRc8fkqSbCUppRtOha9lV5HK919d/o1GQK9a0KaEpdzxPqmWy9ixR/
GR0Xtc3IWDONFOQNU1eQT0luZ5wua65fop0av8f7iyEl0ii/okr9bmqPDIlBFqHm
jjebWr5nzvmzDuy2dSXUywUBGH81wT/W7zF08CBIAj3ltVJe4tHkPiwJTtevwbj1
2ADch0N6ExtikVOSsnxTSyXRixeDeTtkLmT9Yc2DbKuq0y+KACS6eeua/oJRFXud
5BWUf2GVIW2IEI3L6EpRm7Jo67bKUlH+q0d190g4/4lF3+lrXmndgijzI6mw8ZOQ
Ww9loYONAgMBAAECgf9I9SBLfeD+oHNqewoz6quqzPzdI7tQ8JJdkF3WCSWaUxFT
cuKLRKrvyg4+WruH2EqeBrfPFFZRLCRrEFPFpYTooR6/WyQyJ5yCPeS3hP68Ak06
MRs3u3spHUsE2g4US624jaGWCJjlMn9AlkwAYXFnpO4PZZNbQhXFjVcf2VZyVVf/
boSmuvHx2xrxewBX1YQNjyagp9En4dUIgR2xHfdR/RfiFI4qXa0xIOskZRHBGiMZ
rTfcU+2kpb2chnsAMwHN0UOOQGZjXqDJA9SeRJWVsLdhSRlb1xu/E4/mAPjPoQ26
l1W7r8vSkIBlyGCQBAw52z1NczgXp2W/2EdIm1kCgYEA9Yju+9dHfnuczHmWQyIs
uybJMn05ifUYpSKmPaBFb2wLPUmWblrfr9YnGqn7An+PtUsTksAq1WTpSrt89P/+
gjnl/TPgWVX4lF/5HtUPe6P4lqPbj/p/bWqNzX20i6TdP2NH4ndgZNoKDS8y8jRP
yhWsQkaK/PKxVDvWUm+ZaFsCgYEA7bsT1cjwIIdsT2dVZzpNWOQaYM1GuXNIkat/
U4Z3lt8xYytbYbpayUzsHcyOjB1Rs5IxapHn2fc2EIzZvSENTgKa4IAnxngaVQxb
kGRUakRhS5UHVng+m2NrMOkClETY9xvK7sSfA0iGyVRtHXQQjDTP+hrh6mR8lSOs
Tfd/yDcCgYEA58JM8eIOVdEP++F4d/22AyFlIAcbXKDAln7SM7EoWTe+lCb1m0yj
fzHAz2ZKy9zkJNesrgQ9ahdKLYQzOn64GOvVrt5ckXaYoFTGrNenOalYZ7ha8tgb
l4fQOXrCBF2liMOJgrXzgr5cZn16tSuzdKhoZFZ5srDRuRSSBFXak6kCgYEAzg9I
JBhlu2xmv3TMHAv3G0OscZe84+Y/UrSaSuXVJtsTTeg47z6+jpm0WCgErwKC3Omt
F7ichNu46yOLYFoT1DiB0nKDB473FB0ACOpOGUZoJ0Fn+NWFPt8v/FccOzRp89cN
UWTwh8IHwt8BLXR7G2xzkVBX3fl32zXuli4ffoUCgYByeoN5kiyOzyv0pWpMmZdM
Ja6gl6zz6w9xYYEFleyOukwDpXBSt1nifMR670xST3vQR79j+7+nX2AeXJRZfYPw
DWxa0qR7mcvCVEpxndce4WiJ4fvro9pVXMuv5qRQeMKXRGEpbkpGsea7QIZ7CgFI
KZCvUTrUJlpcOKi1zvxsgg==
-----END PRIVATE KEY-----"
** redirect_domain: webhook.site


2. Sandbox

2.1. secret-id: calytics/calytics-be/sandbox/revolut/credentials
** access_token: take from prompt
** expires_at: (in milliseconds !!)(calculated from expires_in) take from prompt
** client_assertion: take from prompt

2.2. secret-id: calytics/calytics-be/sandbox/revolut/static-credentials
** client_id: mB18o9pb0ljXnEGWGGVDGYTepyulvlvzvo8OZ693RWk
** refresh_token: oa_sand_vF50YgBpsXDVPeB9NNJJYoPEEn9K9OQEYlcOhVxZSnc
** private_key: (Multi-line PEM format): 
"-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDcGlNagzawJxI+
yej0LeY8Jzm/IXUln6HCSTR7WryKDhddPKAsQLRp7GUTgWstraKBhs3vzTCXnDv/
LFRZ4k35fkirUq/z/safPzP9bM3kagjBBjZX7/UrZfJliGoBUskTCQEYSfiVIbG9
Q68JehFX23i04Hj+BKwKirvjcFdVIpP6S+7AAmXp5+SrpHzNmZe3wWg87zbQETuV
yG+yUjLGUt+6xchHtmuHVPYtwFEiTD2SyscVIxwfbV/O0BA2/4jcn/rDqvjniWZC
gi8zN+ZFLmKl/7mqKWzL6hE79ZCfS/tDnWYoeij1FKZEEligle37c226gB1yU7/v
6Ar0wrLvAgMBAAECggEAB2TprfMV2unFHCTjquhWgWjT8M7VRP6i4Yhct1QqB1Kd
Mv2pZ93YnG0GTEHJxvlmqdv3KSTcirYDR07xmn9sHS3tOmGHFbcBFzJ5Xacnwjz/
BEpgIv4ltLUyZSTQYtupc6FBedO/rSA6UgsRuKDIL7UTeLLIfcghu3eZA6AE3xBA
AhviiEGqO8cgaaLqINbZsnQJ9p7s253zbJn5SeXZHYi8SPxU1NuH0uSrizmEP6/7
p7HSaipk10MYyy14vB2J6q8WPwK42g0QGisKtgWXspLPQKXLqCvAIymPWHRW8uih
FRC2/C+45eEPFD+EKIna5gjlP7k60gwnM6L41VscmQKBgQD7VVha+DwvcB2lvI+F
p1ueHUbP6Tg+9uxfKD/A0Vzch+mu8GL7ZZ8FK70Fq3EBBDLy3AucwKgDBLbmaC/7
wL8HO/S0uVdJ94wOsnrLjf8vmaYE/H6en+7e3lOLPU4xPAq12lgPjNo1+DTb2HEQ
f02f+VR9lUfBzzmNarADeInZFQKBgQDgMIiHejv7UUjFLqWF9uG0xZH+2BaHnjbq
79UgsEzt+kpv9ernGci35SrmU+iqA3vGs3ltEtifIe3aiVxhBO3UqUXjstpE19Bx
HcpvpzOhS3gHrmvKsoxgZZ6aiPsVNrtSn+e7Cu89Qbbd12z87p+dl6LqpbAO+rMc
BrDcxiQU8wKBgQCWEB0TI8f7ovtwq6cd7BD91QkktmFI5vG21zdJjzfczKGwPAM9
iy1pTvYrXnO4YaNx8gRU8YrfUn9KDscnj6v/S8MN7OO7XDyZweMjioLlDt5bd866
M0/Sbfh/2HjJWMokTlvp3PWk56/X2+GWMgxNCfdyjCEuDOaWEy9Iwz27CQKBgQC1
Ya7kZVnoIECPAAl9VFwSJJLVK8E2oiPuenHly53CIHFfGgieRzckyW2nAhZIjx7y
iTxhqhDG1u2YlO+/svw0xWs9KPP9JNqI2kBxi0ZzZhrLpCujyEdYqn7iqpbx9+Eg
nS0gIF2lIuivnV6ZWPqcxxVRYRILXHvS3frz8/83TwKBgD4WP562xnk0dclprJWn
fKiYGMvMl8ARxJmLkXlJgzAwk/0blczMLl49eQm5N20AobyL8yOY26UsRcPuP8GD
Axzl2KjFW956iutiCIbazF5GuJP5/kcK5sK7iL717vm/KYJmcbGOzy9j7CIXOgxd
FArpBS1t7Q75WlEmoc4QbwHB
-----END PRIVATE KEY-----"
** redirect_domain: webhook.site


3. Production

3.1. secret-id: calytics/calytics-be/production/revolut/credentials
** access_token: take from prompt
** expires_at: (in milliseconds !!)(calculated from expires_in) take from prompt
** client_assertion: take from prompt

3.2. secret-id: calytics/calytics-be/production/revolut/static-credentials
** client_id: hOydrYxx7LSi5KgGJkJP0KrA0Wv-o-SXaEX5QoAySPw
** refresh_token: oa_prod_qG7r4sieXagqFyDQLSpMJLJRqlQXWjQxXFLW1KGDRd4
** private_key: (Multi-line PEM format) take from prompt
** redirect_domain: webhook.site

---

## Updating dynamic credentials safely

1. **Calculate `expires_at` (milliseconds).**
   Revolut API returns `expires_in` (seconds). You must convert this to a future timestamp in milliseconds.
   `expires_at = (current_epoch_seconds + expires_in_seconds) * 1000`.
   
   Example calculation:
   ```bash
   # If expires_in is 2399 seconds
   now=$(date -u +%s)
   expires_at=$(((now + 2399) * 1000))
   echo $expires_at
   ```

2. **Prepare the JSON object.**
   The dynamic secret **MUST** contain:
   - `access_token`: The new access token string.
   - `expires_at`: The calculated numeric timestamp (milliseconds).
   - `client_assertion`: The JWT used for the request (if available/needed).

   **Do NOT include:** `refresh_token` or `redirect_domain` here. Those belong in `static-credentials`.

3. **Update the secret.**
   Paste the fully formed JSON into the command.
   **Never embed shell arithmetic directly inside the JSON string** in the AWS command, as it won't be evaluated and will break the JSON parsing.

   ```bash
   aws secretsmanager put-secret-value --secret-id calytics/calytics-be/sandbox/revolut/credentials --secret-string '{"access_token":"...","expires_at":1761827279252,"client_assertion":"..."}'
   ```

4. **Verify.**
   Run `aws secretsmanager get-secret-value ... --query 'SecretString' --output text` to ensure the JSON is valid and numerical values are numbers, not strings.
