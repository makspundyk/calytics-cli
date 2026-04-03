#!/bin/bash

# VTL Helper Script for API Gateway
# This script helps you manage VTL templates for API Gateway

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to list all REST APIs
list_apis() {
    echo -e "${GREEN}Listing all REST APIs...${NC}"
    aws apigateway get-rest-apis --query 'items[*].[id,name,createdDate]' --output table
}

# Function to list resources in an API
list_resources() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: API ID is required${NC}"
        echo "Usage: $0 list-resources <API_ID>"
        exit 1
    fi
    
    echo -e "${GREEN}Listing resources for API: $1${NC}"
    aws apigateway get-resources --rest-api-id "$1" --query 'items[*].[id,path,pathPart]' --output table
}

# Function to get integration details
get_integration() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        echo -e "${RED}Error: API ID, Resource ID, and HTTP Method are required${NC}"
        echo "Usage: $0 get-integration <API_ID> <RESOURCE_ID> <HTTP_METHOD>"
        exit 1
    fi
    
    echo -e "${GREEN}Getting integration details...${NC}"
    aws apigateway get-integration \
        --rest-api-id "$1" \
        --resource-id "$2" \
        --http-method "$3" \
        --output json | jq .
}

# Function to update integration with VTL template
update_integration_vtl() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
        echo -e "${RED}Error: API ID, Resource ID, HTTP Method, and VTL file path are required${NC}"
        echo "Usage: $0 update-vtl <API_ID> <RESOURCE_ID> <HTTP_METHOD> <VTL_FILE> [LAMBDA_ARN]"
        exit 1
    fi
    
    API_ID=$1
    RESOURCE_ID=$2
    HTTP_METHOD=$3
    VTL_FILE=$4
    LAMBDA_ARN=$5
    
    if [ ! -f "$VTL_FILE" ]; then
        echo -e "${RED}Error: VTL file not found: $VTL_FILE${NC}"
        exit 1
    fi
    
    # Read VTL template and escape it for JSON
    VTL_CONTENT=$(cat "$VTL_FILE" | jq -Rs .)
    
    echo -e "${YELLOW}Current integration type:${NC}"
    CURRENT_TYPE=$(aws apigateway get-integration \
        --rest-api-id "$API_ID" \
        --resource-id "$RESOURCE_ID" \
        --http-method "$HTTP_METHOD" \
        --query 'type' --output text)
    echo "  Type: $CURRENT_TYPE"
    
    if [ "$CURRENT_TYPE" = "AWS_PROXY" ]; then
        echo -e "${YELLOW}Warning: Current integration is AWS_PROXY. VTL requires AWS or HTTP type.${NC}"
        echo -e "${YELLOW}You need to provide LAMBDA_ARN to convert to AWS type.${NC}"
        
        if [ -z "$LAMBDA_ARN" ]; then
            echo -e "${RED}Error: LAMBDA_ARN is required when converting from AWS_PROXY${NC}"
            exit 1
        fi
        
        REGION=$(aws configure get region)
        URI="arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"
        
        echo -e "${GREEN}Updating integration to AWS type with VTL template...${NC}"
        aws apigateway update-integration \
            --rest-api-id "$API_ID" \
            --resource-id "$RESOURCE_ID" \
            --http-method "$HTTP_METHOD" \
            --patch-ops \
                op=replace,path=/type,value=AWS \
                op=replace,path=/integrationHttpMethod,value=POST \
                op=replace,path=/uri,value="$URI" \
                op=replace,path=/requestTemplates/application~1json,value="$VTL_CONTENT" \
            --output json
        
        echo -e "${GREEN}Integration updated successfully!${NC}"
    else
        echo -e "${GREEN}Updating VTL template...${NC}"
        aws apigateway update-integration \
            --rest-api-id "$API_ID" \
            --resource-id "$RESOURCE_ID" \
            --http-method "$HTTP_METHOD" \
            --patch-ops \
                op=replace,path=/requestTemplates/application~1json,value="$VTL_CONTENT" \
            --output json
        
        echo -e "${GREEN}VTL template updated successfully!${NC}"
    fi
    
    echo -e "${YELLOW}Remember to deploy the API after updating!${NC}"
}

# Function to deploy API
deploy_api() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo -e "${RED}Error: API ID and Stage Name are required${NC}"
        echo "Usage: $0 deploy <API_ID> <STAGE_NAME> [DESCRIPTION]"
        exit 1
    fi
    
    API_ID=$1
    STAGE_NAME=$2
    DESCRIPTION=${3:-"VTL script update"}
    
    echo -e "${GREEN}Deploying API to stage: $STAGE_NAME${NC}"
    DEPLOYMENT_ID=$(aws apigateway create-deployment \
        --rest-api-id "$API_ID" \
        --stage-name "$STAGE_NAME" \
        --description "$DESCRIPTION" \
        --query 'id' --output text)
    
    echo -e "${GREEN}Deployment created: $DEPLOYMENT_ID${NC}"
    echo -e "${GREEN}API deployed successfully!${NC}"
}

# Function to monitor logs
monitor_logs() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Log Group Name is required${NC}"
        echo "Usage: $0 monitor-logs <LOG_GROUP_NAME>"
        exit 1
    fi
    
    LOG_GROUP=$1
    
    echo -e "${GREEN}Monitoring logs for: $LOG_GROUP${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    
    aws logs tail "$LOG_GROUP" --follow --format short
}

# Function to find log group for an API
find_log_group() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo -e "${RED}Error: API ID and Stage Name are required${NC}"
        echo "Usage: $0 find-logs <API_ID> <STAGE_NAME>"
        exit 1
    fi
    
    API_ID=$1
    STAGE_NAME=$2
    
    LOG_GROUP="API-Gateway-Execution-Logs_${API_ID}/${STAGE_NAME}"
    
    echo -e "${GREEN}Looking for log group: $LOG_GROUP${NC}"
    
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q .; then
        FOUND=$(aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --query 'logGroups[0].logGroupName' --output text)
        echo -e "${GREEN}Found log group: $FOUND${NC}"
        echo "$FOUND"
    else
        echo -e "${YELLOW}Log group not found. Make sure CloudWatch logging is enabled for the stage.${NC}"
        exit 1
    fi
}

# Main script
case "$1" in
    list-apis)
        list_apis
        ;;
    list-resources)
        list_resources "$2"
        ;;
    get-integration)
        get_integration "$2" "$3" "$4"
        ;;
    update-vtl)
        update_integration_vtl "$2" "$3" "$4" "$5" "$6"
        ;;
    deploy)
        deploy_api "$2" "$3" "$4"
        ;;
    monitor-logs)
        monitor_logs "$2"
        ;;
    find-logs)
        find_log_group "$2" "$3"
        ;;
    *)
        echo "VTL Helper Script for API Gateway"
        echo ""
        echo "Usage: $0 <command> [arguments]"
        echo ""
        echo "Commands:"
        echo "  list-apis                                    List all REST APIs"
        echo "  list-resources <API_ID>                     List resources in an API"
        echo "  get-integration <API_ID> <RESOURCE_ID> <HTTP_METHOD>  Get integration details"
        echo "  update-vtl <API_ID> <RESOURCE_ID> <HTTP_METHOD> <VTL_FILE> [LAMBDA_ARN]  Update integration with VTL"
        echo "  deploy <API_ID> <STAGE_NAME> [DESCRIPTION]  Deploy API changes"
        echo "  find-logs <API_ID> <STAGE_NAME>            Find CloudWatch log group"
        echo "  monitor-logs <LOG_GROUP_NAME>               Monitor API Gateway logs in real-time"
        echo ""
        echo "Examples:"
        echo "  $0 list-apis"
        echo "  $0 list-resources abc123xyz"
        echo "  $0 get-integration abc123xyz def456uvw POST"
        echo "  $0 update-vtl abc123xyz def456uvw POST request-template.vtl"
        echo "  $0 deploy abc123xyz prod"
        echo "  $0 find-logs abc123xyz prod"
        echo "  $0 monitor-logs API-Gateway-Execution-Logs_abc123xyz/prod"
        exit 1
        ;;
esac

