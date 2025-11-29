#!/bin/bash

set -e

# TODO:
# ./delete-all.sh           : Delete app, database, network
# ./delete-all.sh builder   : Delete the image builder
# ./delete-all.sh s3        : Delete the S3 bucket
# ./delete-all.sh all       : Delete everything
ALL_FLAG="$1"

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


echo "======================="
echo "  Deleting all stacks  "
echo "======================="

# This list should be in downward dependency order (app, then db, then network)
delete_stack "enpm818n-application"
delete_stack "enpm818n-database"
delete_stack "enpm818n-network"

delete_stack "enpm818n-image-builder"

echo ""
echo "=========================================="
echo "     Successfully deleted all stacks      "
echo "  Recommend double checking just in case! "
echo "=========================================="
echo ""