 ===== A2A Payment 1 =====
     amount: 0.01
     callback_nonce: 6ee0f56ec908b1284533256c91c02575
     callback_url:
     client_id: cf66a360-e630-482f-aecf-0c050266dfaf
     correlation_id: shop-a:ORDER-2024-11-20-001
     created_at: 1775045448567
     currency: EUR
     expires_at: 1775047248567
     finalized: False
     payment_id: 019d48f4-10fa-70f1-a4dc-e3473c0ce169
     purpose: Order #12345 - Premium Widgets
     recipient:
       bic: NTSBDEB1XXX
       iban: DE72100110012625000781
       name: CSABA KRUEMMER
     recipient_iban: DE72100110012625000781
     sender:
       bic: HYVEDEMMXXX
       iban: DE50700202700015224749
       name: Csaba Krümmer
     sender_iban: DE50700202700015224749
     session_status: NOT_YET_OPENED
     status: OPEN
     tenant_composite_key: cf66a360-e630-482f-aecf-0c050266dfaf#shop-a
     tenant_group: premium
     tenant_id: shop-a
     updated_at: 1775045448567
     vendor_credentials_encrypted:
       algorithm: AES-256-GCM
       encryptedPassword: oHbgxx9LH85jF3WwDiZP/12SYcpiOZnDBwLimFRJeDR6Ipi6
       encryptedUsername: /HLkkxhEG85jFHK0ByZP/A/PYZAyaprDBF3kklJKIjIjJpng
       iv: 60yHUKsq7avkJb2z
       passwordTag: flDhmBXk9fYj+161Wi6gcA==
       usernameTag: P6qkgKWI99ssQdjHLjtA6g==
     vendor_name: finapi
     vendor_payment_id: 8
     vendor_session_id: 8cc4d5de-01da-43fd-a8be-b9da3cdf6b11
     vendor_session_url: https://webform-live.finapi.io/wf/8cc4d5de-01da-43fd-a8be-b9da3cdf6b11
     version: 1
     webhook_received: False
     webhook_sent: False

     ===== A2A Payment 2 =====
     amount: 0.01
     callback_nonce: 49ca1963c89aecf4f24c078f1aed0519
     callback_url:
     client_id: cf66a360-e630-482f-aecf-0c050266dfaf
     correlation_id: shop-a:ORDER-2024-11-20-001
     created_at: 1775044919225
     currency: EUR
     expires_at: 1775046719225
     finalized: True
     finalized_at: 1775045238452
     payment_id: 019d48eb-fda6-7638-a26a-367bebcb8a32
     purpose: Order #12345 - Premium Widgets
     recipient:
       bic: NTSBDEB1XXX
       iban: DE72100110012625000781
       name: CSABA KRUEMMER
     recipient_iban: DE72100110012625000781
     sender:
       bic: HYVEDEMMXXX
       iban: DE50700202700015224749
       name: Csaba Krümmer
     sender_iban: DE50700202700015224749
     session_status: COMPLETED
     status: SUCCESSFUL
     tenant_composite_key: cf66a360-e630-482f-aecf-0c050266dfaf#shop-a
     tenant_group: premium
     tenant_id: shop-a
     updated_at: 1775045238720
     vendor_credentials_encrypted:
       algorithm: AES-256-GCM
       encryptedPassword: Aw8cDJBzH0RKXEjGt0MFoEuA0qq6LH4S7qVzSGYADvfsKstr
       encryptedUsername: Vw5AWMJ+HhNKDh2SuEMF9RyO0qu7fS8S7qt/SzJQDaC+L8tn
       iv: l6H7NiYINw5HxMLQ
       passwordTag: xdzdC/S29Eso6gZ5kkv79Q==
       usernameTag: KiS7/PsZTGEDyHMiJzzRYQ==
     vendor_name: finapi
     vendor_payment_id: 10285823
     vendor_session_id: da5e03ac-1395-4bea-86d4-74a056117ba4
     vendor_session_url: https://webform-live.finapi.io/wf/da5e03ac-1395-4bea-86d4-74a056117ba4
     version: 4
     webhook_received: True
     webhook_sent: True
     webhook_sent_at: 1775045237996

     ----


can we fetch this payment_id from finapi api ?
client_id: cf66a360-e630-482f-aecf-0c050266dfaf
correlation_id: shop-a:ORDER-2024-11-20-001
payment_id: 019d48eb-fda6-7638-a26a-367bebcb8a32
username: 74ebd432-a1f7-4d19-9bcc-78966ae3e3b5
password: c596692e-3d28-41f7-8c22-7655b1fd76b9

I need you to use aws cli and this finapi files:
* \\wsl.localhost\Ubuntu-24.04\home\unknown\projects\calytics\calytics-a2a\src\domains\calyti
cs-collect\specs\api-docs.yaml
* \\wsl.localhost\Ubuntu-24.04\home\unknown\projects\calytics\calytics-a2a\src\domains\calyti
cs-collect\specs\openapi-access-v2.yaml    