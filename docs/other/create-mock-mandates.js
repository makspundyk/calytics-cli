#!/usr/bin/env node
/**
 * Create mock mandate records in calytics-cc-development-mandates.
 * - 5-10 mandates per day of month (1-31), randomly
 * - Income pattern: 50% stable, 30% irregular, 20% undetected
 * - Status: 85% active, 15% inactive
 * - All UI fields filled: reference, iban, account_holder_name, status, signing_method,
 *   amount, debit_day, suggested_debit_day, income_pattern
 *
 * Usage: TABLE_NAME=calytics-cc-development-mandates REGION=eu-central-1 node create-mock-mandates.js
 *        Or from calytics-be-admin: node scripts/create-mock-mandates.js (uses default table/region)
 */

const crypto = require('crypto');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const TABLE_NAME = process.env.TABLE_NAME || 'calytics-cc-development-mandates';
const REGION = process.env.AWS_REGION || process.env.REGION || 'eu-central-1';
const CLIENT_ID = process.env.CLIENT_ID || '117d49aa-fbc4-4a2e-9929-771ae29fef4f';

const FIRST_NAMES = ['Anna', 'Bruno', 'Clara', 'David', 'Emma', 'Felix', 'Gina', 'Hans', 'Iris', 'Julia', 'Klaus', 'Lena', 'Max', 'Nora', 'Paul', 'Rita', 'Stefan', 'Tina', 'Uwe', 'Vera'];
const LAST_NAMES = ['Mueller', 'Schmidt', 'Schneider', 'Fischer', 'Weber', 'Meyer', 'Wagner', 'Becker', 'Schulz', 'Hoffmann', 'Koch', 'Richter', 'Klein', 'Wolf', 'Schroeder', 'Neumann', 'Schwarz', 'Zimmermann', 'Braun'];

function randomInt(min, max) {
  return min + Math.floor(Math.random() * (max - min + 1));
}

function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function uuid() {
  return crypto.randomUUID();
}

function mandateReference(mandateId) {
  const hex = mandateId.replace(/-/g, '').toUpperCase().slice(0, 24);
  return `CALYTICS-${hex}`;
}

function randomIban() {
  let s = 'DE';
  for (let i = 0; i < 20; i++) s += Math.floor(Math.random() * 10);
  return s;
}

function ibanHash(iban) {
  return crypto.createHash('sha256').update(iban.toUpperCase()).digest('hex');
}

function shuffle(arr) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// Build list of (debit_day, income_pattern) for each mandate to create
function buildSpecs() {
  const specs = [];
  for (let day = 1; day <= 31; day++) {
    const count = randomInt(5, 10);
    for (let i = 0; i < count; i++) {
      specs.push({ debit_day: day });
    }
  }
  // Assign income_pattern: 50% stable, 30% irregular, 20% undetected
  const n = specs.length;
  const stableCount = Math.round(n * 0.5);
  const irregularCount = Math.round(n * 0.3);
  const indices = shuffle(specs.map((_, i) => i));
  indices.slice(0, stableCount).forEach((i) => { specs[i].income_pattern = 'stable'; });
  indices.slice(stableCount, stableCount + irregularCount).forEach((i) => { specs[i].income_pattern = 'irregular'; });
  indices.slice(stableCount + irregularCount).forEach((i) => { specs[i].income_pattern = 'undetected'; });
  return specs;
}

function toDynamoItem(spec, now) {
  const mandateId = uuid();
  const correlationId = uuid();
  const sessionId = uuid();
  const iban = randomIban();
  const accountHolder = `${pick(FIRST_NAMES)} ${pick(LAST_NAMES)}`;
  const status = Math.random() < 0.85 ? 'active' : 'inactive';
  const amount = randomInt(50, 300);
  const suggestedDebitDay = (spec.income_pattern === 'stable' || spec.income_pattern === 'irregular')
    ? randomInt(1, 31)
    : null;

  const item = {
    mandate_id: { S: mandateId },
    mandate_reference: { S: mandateReference(mandateId) },
    client_id: { S: CLIENT_ID },
    correlation_id: { S: correlationId },
    session_id: { S: sessionId },
    iban: { S: iban },
    iban_hash: { S: ibanHash(iban) },
    account_holder_name: { S: accountHolder },
    account_type: { S: 'CHECKING' },
    status: { S: status },
    signing_method: { S: 'BANK_VERIFIED_AIS' },
    verification_method: { S: 'AIS_BANK_LOGIN' },
    amount: { N: String(amount) },
    currency: { S: 'EUR' },
    debit_day: { N: String(spec.debit_day) },
    income_pattern: { S: spec.income_pattern },
    created_at: { N: String(now) },
    updated_at: { N: String(now) },
    version: { N: '1' },
    callback_sent: { BOOL: true },
    callback_sent_at: { N: String(now) },
  };
  if (suggestedDebitDay !== null) {
    item.suggested_debit_day = { N: String(suggestedDebitDay) };
  }
  return item;
}

function main() {
  const now = Date.now();
  const specs = buildSpecs();
  const items = specs.map((spec) => toDynamoItem(spec, now));

  const BATCH_SIZE = 25;
  const tmpDir = path.join(__dirname, '.batch-tmp');
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });

  let written = 0;
  for (let i = 0; i < items.length; i += BATCH_SIZE) {
    const chunk = items.slice(i, i + BATCH_SIZE);
    const requestItems = {
      [TABLE_NAME]: chunk.map((Item) => ({ PutRequest: { Item } })),
    };
    const file = path.join(tmpDir, `batch-${i}.json`);
    // --request-items is the RequestItems param: map of table name -> array of PutRequest
    fs.writeFileSync(file, JSON.stringify(requestItems), 'utf8');
    execSync(`aws dynamodb batch-write-item --request-items file://${path.resolve(file)} --region ${REGION}`, {
      stdio: ['inherit', 'pipe', 'inherit'],
      cwd: __dirname,
    });
    written += chunk.length;
    console.error(`Wrote batch ${Math.floor(i / BATCH_SIZE) + 1}: ${chunk.length} mandates (total ${written})`);
  }

  // Cleanup
  try {
    fs.readdirSync(tmpDir).forEach((f) => fs.unlinkSync(path.join(tmpDir, f)));
    fs.rmdirSync(tmpDir);
  } catch (_) {}

  console.log(JSON.stringify({ created: written, table: TABLE_NAME, region: REGION }));
}

main();
