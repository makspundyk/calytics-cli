#!/usr/bin/env node
/**
 * Delete mock mandates (those with UUID-style mandate_id; keep ULID 019... originals).
 * Usage: TABLE_NAME=calytics-cc-development-mandates REGION=eu-central-1 node delete-mock-mandates.js
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const TABLE_NAME = process.env.TABLE_NAME || 'calytics-cc-development-mandates';
const REGION = process.env.AWS_REGION || process.env.REGION || 'eu-central-1';

// Get all mandate_ids via scan (paginate)
function getAllMandateIds() {
  const ids = [];
  let lastKey = null;
  do {
    let cmd = `aws dynamodb scan --table-name ${TABLE_NAME} --region ${REGION} --projection-expression "mandate_id" --output json`;
    if (lastKey) cmd += ` --starting-token "${JSON.stringify(lastKey).replace(/"/g, '\\"')}"`;
    const out = JSON.parse(execSync(cmd, { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 }));
    out.Items.forEach((item) => ids.push(item.mandate_id.S));
    lastKey = out.NextToken || null;
  } while (lastKey);
  return ids;
}

// Keep only those that do NOT start with "019" (originals are ULIDs)
function mockIds(ids) {
  return ids.filter((id) => !id.startsWith('019'));
}

function main() {
  console.error('Scanning table for mandate_ids...');
  const allIds = getAllMandateIds();
  const toDelete = mockIds(allIds);
  console.error(`Total: ${allIds.length}, keeping ${allIds.length - toDelete.length}, deleting ${toDelete.length} mock mandates`);

  if (toDelete.length === 0) {
    console.log(JSON.stringify({ deleted: 0 }));
    return;
  }

  const BATCH_SIZE = 25;
  const tmpDir = path.join(__dirname, '.batch-tmp');
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });

  let deleted = 0;
  for (let i = 0; i < toDelete.length; i += BATCH_SIZE) {
    const chunk = toDelete.slice(i, i + BATCH_SIZE);
    const requestItems = {
      [TABLE_NAME]: chunk.map((id) => ({
        DeleteRequest: { Key: { mandate_id: { S: id } } },
      })),
    };
    const file = path.join(tmpDir, `del-${i}.json`);
    fs.writeFileSync(file, JSON.stringify(requestItems), 'utf8');
    execSync(`aws dynamodb batch-write-item --request-items file://${path.resolve(file)} --region ${REGION}`, {
      stdio: ['inherit', 'pipe', 'inherit'],
    });
    deleted += chunk.length;
    console.error(`Deleted batch ${Math.floor(i / BATCH_SIZE) + 1}: ${chunk.length} (total ${deleted})`);
  }

  try {
    fs.readdirSync(tmpDir).forEach((f) => fs.unlinkSync(path.join(tmpDir, f)));
    fs.rmdirSync(tmpDir);
  } catch (_) {}

  console.log(JSON.stringify({ deleted, table: TABLE_NAME }));
}

main();
