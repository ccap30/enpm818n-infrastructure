#!/bin/bash

set -e

# Variables
REPO_ROOT=$(git rev-parse --show-toplevel)
REGION="us-east-1"
CAPABILITIES="CAPABILITY_NAMED_IAM"
SCRIPTS_DIR="$REPO_ROOT/scripts"

# Parameters:
#   $1. Path to template file
function validate_stack {
    TEMPLATE_FILE=$1
    echo "Validating CloudFormation template: $TEMPLATE_FILE"
    cfn-lint --template $TEMPLATE_FILE

    # Alternatively, you can use the following, but it prints the formatted template
    # aws cloudformation validate-template --template-body file://$TEMPLATE_FILE
}

# Parameters:
#   1. Stack name
#   2. Region
function print_outputs {
    STACK_NAME=$1
    echo "Stack outputs for $STACK_NAME"
    aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query "Stacks[0].Outputs"
}

# Parameters:
#   1. Stack name
#   2. CloudFormation yaml file name
function deploy_stack {
    STACK_NAME=$1
    TEMPLATE_FILE="$REPO_ROOT/templates/$2"

    echo ""
    echo "----------------------------------"
    echo " Stack: $STACK_NAME"
    echo " Template File: $TEMPLATE_FILE"
    echo " Region: $REGION"
    echo "----------------------------------"
    echo ""

    validate_stack $TEMPLATE_FILE

    # Deploy stack
    echo "Deploying stack: $STACK_NAME"
    aws cloudformation deploy \
        --stack-name $STACK_NAME \
        --template-file $TEMPLATE_FILE \
        --capabilities $CAPABILITIES \
        --region $REGION
    echo "Successfully deployed $STACK_NAME"

    # Useful for debugging
    # print_outputs $STACK_NAME $REGION
}


echo "========================"
echo "  Deploying all stacks  "
echo "========================"

# Make sure the Custom AMI Image ID exists.
# If it doesn't, we need to deploy the image builder and generate that image.
# TODO: "enpm818n-custom-ubuntu-ami" is the "${PREFIX}-${IMAGE_NAME}" that's used in the image builder template.
#        We should create a local variable in this script and pass it as a parameter to the template.
CUSTOM_UBUNTU_AMI_ID=$(aws ec2 describe-images \
                        --owners self \
                        --filters "Name=name,Values=enpm818n-custom-ubuntu-ami-*" \
                        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
                        --output text)

# This could probably be replaced with an AWS lambda function, but since this 
# image is supposed to be static, let's just grab what should be the only image ID.
if [[ "$CUSTOM_UBUNTU_AMI_ID" == "None" ]]; then
    # Create and run the image builder
    echo "Warning: Unable to find Custom AMI Image. Deploying image builder stack..."
    deploy_stack "enpm818n-image-builder" "image-builder.yaml"
    # TODO: aws command to wait for the image builder to complete
    # TODO: aws command to run the image builder

    # Get the new AMI ID
    CUSTOM_UBUNTU_AMI_ID=$(aws ec2 describe-images \
                            --owners self \
                            --filters "Name=name,Values=enpm818n-custom-ubuntu-ami-*" \
                            --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
                            --output text)
    if [[ "$CUSTOM_UBUNTU_AMI_ID" == "None" ]]; then
        echo "Fatal: Failed to create Custom AMI Image!"
        exit 1
    fi
    echo "Successfully created Custom AMI Image, ID: $CUSTOM_UBUNTU_AMI_ID"

else
    echo "Found Custom AMI Image ID: $CUSTOM_UBUNTU_AMI_ID"
fi

# This list should be in upward dependency order (network, then db, then app)

deploy_stack "enpm818n-network" "network.yaml"
# deploy_stack "enpm818n-database" "database.yaml"
# deploy_stack "enpm818n-application" "application.yaml"

echo ""
echo "===================================="
echo "  Successfully deployed all stacks  "
echo "===================================="
echo ""