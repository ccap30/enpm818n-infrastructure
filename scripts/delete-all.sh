#!/bin/bash

set -e

# ./delete-all.sh           : Delete app, cdn, database, network, cloudwatch dashboard, and cloudtrail
# ./delete-all.sh builder   : Delete the image builder
# ./delete-all.sh s3        : Delete the s3 bucket
# ./delete-all.sh all       : Delete everything (image builder, s3 bucket, and everything else)
OPTIONAL_FLAG="$1"

# Variables
REPO_ROOT=$(git rev-parse --show-toplevel)
REGION="us-east-1"
SCRIPTS_DIR="$REPO_ROOT/scripts"

# Parameters:
#    1. Stack name
function delete_stack {
    STACK_NAME=$1

    echo ""
    echo "----------------------------------"
    echo " Attempting to delete stack: $STACK_NAME"
    echo " Region: $REGION"
    echo "----------------------------------"
    echo ""

    # Delete stack
    aws cloudformation delete-stack --stack-name $STACK_NAME

    # Wait for deletion
    echo "Waiting for stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"

    echo "Stack $STACK_NAME has been successfully deleted."
}

echo "============================="
echo "  Deleting requested stacks  "
echo "============================="

if [[ "$OPTIONAL_FLAG" == "builder" ]]; then
    delete_stack "enpm818n-image-builder"
    echo ""
    echo "=========================================="
    echo "    Successfully deleted image builder    "
    echo "  Recommend double checking just in case! "
    echo "=========================================="
    echo ""
    exit 0
fi

if [[ "$OPTIONAL_FLAG" == "s3" ]]; then
    delete_stack "enpm818n-s3"
    echo ""
    echo "=========================================="
    echo "      Successfully deleted S3 bucket      "
    echo "  Recommend double checking just in case! "
    echo "=========================================="
    echo ""
    exit 0
fi

if [[ "$OPTIONAL_FLAG" == "all" ]]; then
    delete_stack "enpm818n-cloudtrail" &
    delete_stack "enpm818n-cloudwatch" &
    delete_stack "enpm818n-image-builder" &
    deploy_stack "enpm818n-cloudfront" &
    wait
    delete_stack "enpm818n-application"
    delete_stack "enpm818n-database"

    # TODO: Empty the bucket first
    delete_stack "enpm818n-s3-bucket" &
    delete_stack "enpm818n-network" &
    wait
    echo ""
    echo "=========================================="
    echo "     Successfully deleted all stacks      "
    echo "  Recommend double checking just in case! "
    echo "=========================================="
    echo ""
    exit 0
fi

delete_stack "enpm818n-cloudtrail" &
delete_stack "enpm818n-cloudwatch" &
delete_stack "enpm818n-cloudfront" &
wait
delete_stack "enpm818n-application"
delete_stack "enpm818n-database"
delete_stack "enpm818n-network"

echo ""
echo "=========================================="
echo "       Successfully deleted stacks        "
echo "  Recommend double checking just in case! "
echo "=========================================="
echo ""