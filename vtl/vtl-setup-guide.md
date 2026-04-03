# VTL Script Setup Guide for API Gateway

## Step 1: Identify Your API Gateway

First, let's list all your API Gateways to identify which one you want to modify.

### AWS CLI Commands:

```bash
# List all REST APIs
aws apigateway get-rest-apis --query 'items[*].[id,name]' --output table

# Get details of a specific API (replace API_ID)
aws apigateway get-rest-api --rest-api-id <API_ID>

# List all resources in an API
aws apigateway get-resources --rest-api-id <API_ID> --query 'items[*].[id,path,pathPart]' --output table

# Get integration details for a specific method
aws apigateway get-integration \
  --rest-api-id <API_ID> \
  --resource-id <RESOURCE_ID> \
  --http-method <HTTP_METHOD>
```

## Step 2: Understanding VTL Integration Types

**Important**: VTL templates work with:
- `AWS` integration type (not `AWS_PROXY`)
- `HTTP` integration type
- `MOCK` integration type

If your current integration is `AWS_PROXY`, you'll need to change it to `AWS` or `HTTP` to use VTL.

## Step 3: Update Integration with VTL Script

### Option A: Update Request Template (Request VTL)

```bash
aws apigateway update-integration \
  --rest-api-id <API_ID> \
  --resource-id <RESOURCE_ID> \
  --http-method <HTTP_METHOD> \
  --patch-ops \
    op=replace,path=/requestTemplates/application~1json,value='<VTL_TEMPLATE>' \
    op=replace,path=/type,value=AWS \
    op=replace,path=/integrationHttpMethod,value=POST \
    op=replace,path=/uri,value='arn:aws:apigateway:<REGION>:lambda:path/2015-03-31/functions/<LAMBDA_ARN>/invocations'
```

### Option B: Update Response Template (Response VTL)

```bash
aws apigateway put-integration-response \
  --rest-api-id <API_ID> \
  --resource-id <RESOURCE_ID> \
  --http-method <HTTP_METHOD> \
  --status-code 200 \
  --response-templates '{"application/json":"<VTL_TEMPLATE>"}'
```

## Step 4: Deploy the Changes

**CRITICAL**: After updating VTL, you MUST deploy the API:

```bash
# Create a new deployment
aws apigateway create-deployment \
  --rest-api-id <API_ID> \
  --stage-name <STAGE_NAME> \
  --description "VTL script update"
```

## Step 5: Monitor API Gateway Requests

### Real-time Log Streaming (CloudWatch Logs)

```bash
# Get the log group name (usually: API-Gateway-Execution-Logs_<API_ID>/<STAGE_NAME>)
aws logs describe-log-groups --query 'logGroups[?contains(logGroupName, `API-Gateway`)].logGroupName' --output table

# Tail logs in real-time
aws logs tail <LOG_GROUP_NAME> --follow --format short

# Filter for specific requests
aws logs tail <LOG_GROUP_NAME> --follow --filter-pattern "requestId" --format short
```

### CloudWatch Insights Query

```bash
# Query recent requests
aws logs start-query \
  --log-group-name <LOG_GROUP_NAME> \
  --start-time $(($(date +%s) - 3600)) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | sort @timestamp desc | limit 100'
```

### Using AWS Console

1. Go to API Gateway → Your API → Stages → Your Stage
2. Click on "Logs / Tracing" tab
3. Enable "Enable CloudWatch Logs"
4. View logs in CloudWatch Logs console

## Step 6: Test the VTL Script

```bash
# Make a test request
curl -X POST https://<API_ID>.execute-api.<REGION>.amazonaws.com/<STAGE>/<PATH> \
  -H "Content-Type: application/json" \
  -H "x-api-key: <YOUR_API_KEY>" \
  -d '{"test": "data"}'

# Check the logs immediately after
aws logs tail <LOG_GROUP_NAME> --since 1m --format short
```

## Common VTL Template Examples

### Example 1: Transform Request Body
```vtl
{
  "body": $input.json('$'),
  "headers": {
    #foreach($header in $input.params().header.keySet())
    "$header": "$util.escapeJavaScript($input.params().header.get($header))"
    #if($foreach.hasNext),#end
    #end
  },
  "requestId": "$context.requestId"
}
```

### Example 2: Add Custom Headers
```vtl
#set($context.requestOverride.header.X-Custom-Header = "value")
#set($context.requestOverride.header.X-Request-Id = $context.requestId)
$input.json('$')
```

### Example 3: Conditional Logic
```vtl
#if($input.params().header.get('Content-Type') == 'application/json')
  $input.json('$')
#else
  {"error": "Invalid content type"}
#end
```

## Troubleshooting

### Check Integration Status
```bash
aws apigateway get-integration \
  --rest-api-id <API_ID> \
  --resource-id <RESOURCE_ID> \
  --http-method <HTTP_METHOD>
```

### Validate VTL Syntax
- Use AWS Console to test VTL templates before deploying
- Check CloudWatch Logs for VTL errors
- Common errors: syntax issues, missing quotes, incorrect variable references

### Rollback
```bash
# Get previous deployment ID
aws apigateway get-deployments --rest-api-id <API_ID> --query 'items[*].[id,createdDate]' --output table

# Redeploy previous version
aws apigateway create-deployment \
  --rest-api-id <API_ID> \
  --stage-name <STAGE_NAME> \
  --description "Rollback to previous version"
```

