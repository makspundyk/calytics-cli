# VTL Script Installation Guide

## 📋 Overview

This guide helps you add Velocity Template Language (VTL) scripts to your API Gateway endpoints. VTL allows you to transform requests and responses before they reach your Lambda functions.

## 🚀 Quick Start (3 Steps)

### Step 1: List Your APIs

```bash
cd /home/unknown/projects/calytics/scripts/vtl
./vtl-helper.sh list-apis
```

This will show you all your API Gateways. Note the API ID you want to modify.

### Step 2: Update Integration with VTL

```bash
# Basic usage (if integration is already AWS/HTTP type)
./vtl-helper.sh update-vtl <API_ID> <RESOURCE_ID> <HTTP_METHOD> <VTL_FILE>

# If converting from AWS_PROXY to AWS (need Lambda ARN)
./vtl-helper.sh update-vtl <API_ID> <RESOURCE_ID> <HTTP_METHOD> <VTL_FILE> <LAMBDA_ARN>
```

### Step 3: Deploy and Monitor

```bash
# Deploy changes
./vtl-helper.sh deploy <API_ID> <STAGE_NAME>

# Monitor logs
LOG_GROUP=$(./vtl-helper.sh find-logs <API_ID> <STAGE_NAME>)
./vtl-helper.sh monitor-logs "$LOG_GROUP"
```

## 📝 Detailed Workflow

### 1. Discover Your API Structure

```bash
# List all APIs
aws apigateway get-rest-apis --query 'items[*].[id,name]' --output table

# List resources in your API (replace <API_ID>)
aws apigateway get-resources --rest-api-id <API_ID> --query 'items[*].[id,path,pathPart]' --output table

# Get integration details
aws apigateway get-integration \
  --rest-api-id <API_ID> \
  --resource-id <RESOURCE_ID> \
  --http-method <HTTP_METHOD>
```

### 2. Create Your VTL Template

Edit `sample-request-template.vtl` or create your own `.vtl` file.

**Key VTL Variables:**
- `$input.json('$')` - Request body
- `$input.params().header.get('X-Header')` - Header values
- `$context.requestId` - Request ID
- `$context.stage` - Stage name (prod, dev, etc.)

### 3. Update the Integration

**Option A: Using Helper Script (Recommended)**
```bash
./vtl-helper.sh update-vtl <API_ID> <RESOURCE_ID> <HTTP_METHOD> your-template.vtl
```

**Option B: Using AWS CLI Directly**
```bash
# Read VTL content
VTL_CONTENT=$(cat your-template.vtl | jq -Rs .)

# Update integration
aws apigateway update-integration \
  --rest-api-id <API_ID> \
  --resource-id <RESOURCE_ID> \
  --http-method <HTTP_METHOD> \
  --patch-ops \
    op=replace,path=/requestTemplates/application~1json,value="$VTL_CONTENT"
```

### 4. Deploy Changes

**⚠️ IMPORTANT: Changes are NOT live until you deploy!**

```bash
aws apigateway create-deployment \
  --rest-api-id <API_ID> \
  --stage-name <STAGE_NAME> \
  --description "VTL script update"
```

Or use the helper:
```bash
./vtl-helper.sh deploy <API_ID> <STAGE_NAME>
```

### 5. Monitor Requests

**Real-time Log Monitoring:**
```bash
# Find log group
LOG_GROUP=$(./vtl-helper.sh find-logs <API_ID> <STAGE_NAME>)

# Tail logs
aws logs tail "$LOG_GROUP" --follow --format short
```

**Or use CloudWatch Insights:**
```bash
aws logs start-query \
  --log-group-name "$LOG_GROUP" \
  --start-time $(($(date +%s) - 3600)) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | sort @timestamp desc | limit 100'
```

## 🔧 Converting AWS_PROXY to AWS Integration

If your current integration uses `AWS_PROXY` (Lambda proxy), you need to convert it to `AWS` type to use VTL:

```bash
# Get Lambda ARN from current integration
LAMBDA_ARN=$(aws apigateway get-integration \
  --rest-api-id <API_ID> \
  --resource-id <RESOURCE_ID> \
  --http-method <HTTP_METHOD> \
  --query 'uri' --output text | sed 's/.*functions\/\(.*\)\/invocations/\1/')

# Update with VTL (helper script handles this automatically)
./vtl-helper.sh update-vtl <API_ID> <RESOURCE_ID> <HTTP_METHOD> template.vtl "$LAMBDA_ARN"
```

## 🧪 Testing Your VTL

1. **Make a test request:**
```bash
curl -X POST https://<API_ID>.execute-api.<REGION>.amazonaws.com/<STAGE>/<PATH> \
  -H "Content-Type: application/json" \
  -H "x-api-key: <YOUR_API_KEY>" \
  -d '{"test": "data"}'
```

2. **Check logs immediately:**
```bash
aws logs tail "$LOG_GROUP" --since 1m --format short
```

3. **Verify transformation:**
   - Check CloudWatch Logs for the transformed request
   - Verify Lambda receives the expected format
   - Check response format if using response VTL

## 🐛 Troubleshooting

### VTL Not Working?

1. **Check integration type:**
```bash
aws apigateway get-integration \
  --rest-api-id <API_ID> \
  --resource-id <RESOURCE_ID> \
  --http-method <HTTP_METHOD> \
  --query 'type' --output text
```
   - Must be `AWS` or `HTTP`, not `AWS_PROXY`

2. **Check if deployed:**
```bash
aws apigateway get-deployments --rest-api-id <API_ID> --query 'items[0]' --output json
```

3. **Check CloudWatch Logs for errors:**
```bash
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --filter-pattern "error" \
  --start-time $(($(date +%s) - 3600))
```

### Common VTL Errors

- **Syntax Error**: Missing quotes, incorrect variable syntax
- **Variable Not Found**: Check variable names (case-sensitive)
- **JSON Parsing Error**: Ensure proper JSON formatting in template

## 📚 Files in This Directory

- `vtl-helper.sh` - Helper script for common operations
- `vtl-setup-guide.md` - Comprehensive guide
- `QUICK_START.md` - Quick reference
- `sample-request-template.vtl` - Example request template
- `sample-response-template.vtl` - Example response template

## 🔗 AWS Console Alternative

If you prefer using AWS Console:

1. Go to **API Gateway** → Your API → **Resources**
2. Select the resource and method
3. Click **Integration Request** or **Integration Response**
4. Expand **Mapping Templates**
5. Add template for `application/json`
6. Paste your VTL template
7. Click **Save**
8. Go to **Actions** → **Deploy API**

## ⚠️ Important Notes

1. **Always deploy after changes** - Updates are not live until deployment
2. **Test in dev/staging first** - VTL errors can break your API
3. **Monitor logs** - Check CloudWatch Logs for VTL execution errors
4. **Backup current config** - Save current integration before changes
5. **AWS_PROXY limitation** - VTL doesn't work with AWS_PROXY, must convert to AWS type

## 🎯 Next Steps

1. Identify which API endpoint you want to modify
2. Create your VTL template
3. Use the helper script to update
4. Deploy and test
5. Monitor logs to verify it works

Need help? Check `vtl-setup-guide.md` for detailed examples and troubleshooting.

