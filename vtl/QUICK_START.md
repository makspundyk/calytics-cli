# Quick Start: Add VTL Script to API Gateway

## 🎯 Step-by-Step Process

### Step 1: Identify Your API and Endpoint

```bash
cd /home/unknown/projects/calytics/scripts/vtl
# List all your APIs
./vtl-helper.sh list-apis

# Example output will show:
# |  abc123xyz  |  calytics-prod-banking-api  |  2024-01-01T00:00:00Z  |
```

### Step 2: Find the Resource and Method

```bash
# Replace <API_ID> with the ID from Step 1
./vtl-helper.sh list-resources <API_ID>

# Example output:
# |  def456uvw  |  /v1/debit-guard  |  debit-guard  |
```

### Step 3: Check Current Integration

```bash
# Check current integration type
./vtl-helper.sh get-integration <API_ID> <RESOURCE_ID> <HTTP_METHOD>

# Example:
./vtl-helper.sh get-integration abc123xyz def456uvw POST
```

**Important Notes:**
- If integration type is `AWS_PROXY`, you'll need to convert it to `AWS` type
- If integration type is already `AWS` or `HTTP`, you can directly update VTL

### Step 4: Create Your VTL Template

Create a `.vtl` file with your template. See `sample-request-template.vtl` for examples.

**Common VTL Variables:**
- `$input.json('$')` - Full request body as JSON
- `$input.params().header.get('Header-Name')` - Get header value
- `$context.requestId` - Request ID
- `$context.stage` - Stage name
- `$util.escapeJavaScript()` - Escape JavaScript in strings

### Step 5: Update Integration with VTL

```bash
# If current type is AWS_PROXY, you need Lambda ARN:
./vtl-helper.sh update-vtl <API_ID> <RESOURCE_ID> <HTTP_METHOD> <VTL_FILE> <LAMBDA_ARN>

# If current type is already AWS or HTTP:
./vtl-helper.sh update-vtl <API_ID> <RESOURCE_ID> <HTTP_METHOD> <VTL_FILE>

# Example:
./vtl-helper.sh update-vtl abc123xyz def456uvw POST request-template.vtl
```

### Step 6: Deploy the Changes

**⚠️ CRITICAL: Changes won't take effect until you deploy!**

```bash
./vtl-helper.sh deploy <API_ID> <STAGE_NAME> "Description of changes"

# Example:
./vtl-helper.sh deploy abc123xyz prod "Added request transformation VTL"
```

### Step 7: Monitor and Test

```bash
# Find the log group
LOG_GROUP=$(./vtl-helper.sh find-logs <API_ID> <STAGE_NAME>)

# Monitor logs in real-time
./vtl-helper.sh monitor-logs "$LOG_GROUP"

# In another terminal, make a test request:
curl -X POST https://<API_ID>.execute-api.<REGION>.amazonaws.com/<STAGE>/<PATH> \
  -H "Content-Type: application/json" \
  -H "x-api-key: <YOUR_API_KEY>" \
  -d '{"test": "data"}'
```

## 🔍 Troubleshooting

### Check if VTL is Applied

```bash
aws apigateway get-integration \
  --rest-api-id <API_ID> \
  --resource-id <RESOURCE_ID> \
  --http-method <HTTP_METHOD> \
  --query 'requestTemplates' \
  --output json
```

### View Recent Errors

```bash
# Get log group
LOG_GROUP=$(./vtl-helper.sh find-logs <API_ID> <STAGE_NAME>)

# Query for errors
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --filter-pattern "error" \
  --start-time $(($(date +%s) - 3600)) \
  --query 'events[*].message' \
  --output text
```

### Common Issues

1. **VTL Syntax Error**: Check CloudWatch Logs for detailed error messages
2. **Integration Not Working**: Verify integration type is `AWS` or `HTTP`, not `AWS_PROXY`
3. **Changes Not Applied**: Make sure you deployed after updating VTL
4. **Lambda Not Receiving Data**: Check if VTL template is correctly formatting the request

## 📚 Additional Resources

- Full guide: `vtl-setup-guide.md`
- Sample templates: `sample-request-template.vtl`, `sample-response-template.vtl`
- AWS VTL Reference: https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-mapping-template-reference.html

