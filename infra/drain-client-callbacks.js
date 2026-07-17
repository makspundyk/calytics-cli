const { SQSClient, ReceiveMessageCommand, DeleteMessageCommand } = require('@aws-sdk/client-sqs');
const { handler } = require('/app/dist/infrastructure/schedulers/run-client-callback-ingress.lambda.js');
const endpoint = process.env.AWS_ENDPOINT || 'http://localstack:4566';
const region = process.env.AWS_REGION || 'eu-central-1';
const queueUrl = (process.env.CLIENT_CALLBACKS_QUEUE_URL || '').replace(/^https?:\/\/[^/]+/, 'http://localstack:4566');
const sqs = new SQSClient({ endpoint, region, credentials: { accessKeyId: 'test', secretAccessKey: 'test' } });
(async () => {
  let received = 0, settled = 0;
  for (let i = 0; i < 15; i++) {
    const r = await sqs.send(new ReceiveMessageCommand({ QueueUrl: queueUrl, MaxNumberOfMessages: 10, WaitTimeSeconds: 1, AttributeNames: ['All'] }));
    const msgs = r.Messages || [];
    if (!msgs.length) break;
    const event = { Records: msgs.map(m => ({ messageId: m.MessageId, receiptHandle: m.ReceiptHandle, body: m.Body, attributes: m.Attributes || {} })) };
    const res = await handler(event, {});
    const failed = new Set((res.batchItemFailures || []).map(f => f.itemIdentifier));
    for (const m of msgs) { received++; if (!failed.has(m.MessageId)) { await sqs.send(new DeleteMessageCommand({ QueueUrl: queueUrl, ReceiptHandle: m.ReceiptHandle })); settled++; } }
  }
  console.log(JSON.stringify({ received, settled }));
})().catch(e => { console.error('DRAIN_ERROR', (e && e.message) || e); process.exit(1); });
