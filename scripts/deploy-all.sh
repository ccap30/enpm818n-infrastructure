#!/bin/bash

set -e

# Variables
REPO_ROOT=$(git rev-parse --show-toplevel)
REGION="us-east-1"
CAPABILITIES="CAPABILITY_NAMED_IAM"
SCRIPTS_DIR="$REPO_ROOT/scripts"

# SQL_KEY="ecommerce_1.sql"
# SQL_S3_PATH="s3://${S3_BUCKET}/${SQL_KEY}"
# REPO_URL="https://github.com/edaviage/818N-E_Commerce_Application"
# 818N_REPO_CLONE="$REPO_ROOT/../818N-E_Commerce_Application"

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
    PARAMETER_OVERRIDES="$3"

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
        --region $REGION \
        --parameter-overrides $PARAMETER_OVERRIDES
    echo "Successfully deployed $STACK_NAME"

    # Useful for debugging
    # print_outputs $STACK_NAME $REGION
}


echo "========================"
echo "  Deploying all stacks  "
echo "========================"

# Stacks should be in upward dependency order (network, then db, then app)


#################
# Image Builder #
#################
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
    # Deploy the image builder
    IMAGE_BUILDER_STACK="enpm818n-image-builder"
    echo "Warning: Unable to find Custom AMI Image. Deploying image builder stack..."
    deploy_stack $IMAGE_BUILDER_STACK "image-builder.yaml"

    # Run the image builder pipeline
    IMAGE_BUILDER_PIPELINE_ARN=$(aws cloudformation describe-stack-resources \
        --stack-name $IMAGE_BUILDER_STACK \
        --query "StackResources[?LogicalResourceId=='ImageBuilderPipeline'].PhysicalResourceId" \
        --output text)
    echo "Image builder pipeline ARN: $IMAGE_BUILDER_PIPELINE_ARN"
    aws imagebuilder start-image-pipeline-execution --image-pipeline-arn $IMAGE_BUILDER_PIPELINE_ARN

    # Get the new AMI ID
    CUSTOM_UBUNTU_AMI_ID=$(aws ec2 describe-images \
                            --owners self \
                            --filters "Name=name,Values=enpm818n-custom-ubuntu-ami-*" \
                            --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
                            --output text)
    if [[ "$CUSTOM_UBUNTU_AMI_ID" == "None" ]]; then
        # TODO: This doesn't work. We can't fetch the AMI ID so quickly. Will have to wait until it's created.
        echo "Fatal: Failed to create Custom AMI Image!"
        exit 1
    fi
    echo "Successfully created Custom AMI Image, ID: $CUSTOM_UBUNTU_AMI_ID"

else
    echo "Found Custom AMI Image ID: $CUSTOM_UBUNTU_AMI_ID"
fi



########################
# Network and Database #
########################
deploy_stack "enpm818n-network" "network.yaml"
deploy_stack "enpm818n-database" "database.yaml"



##########################
# E-commerce Application #
##########################
KEY_NAME="enpm818n-key-pair"
KEY_FILE="$KEY_NAME.pem"
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
    echo "Warning: Key pair '$KEY_NAME' does not exist. Creating it and saving it now..."
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --key-type rsa \
        --query 'KeyMaterial' \
        --output text > "$KEY_FILE"
    chmod 400 "$KEY_FILE"
    echo "Info: Key pair '$KEY_NAME' created."
else
    echo "Key pair '$KEY_NAME' found!"
    find . -iname "$KEY_FILE"
fi

DB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name enpm818n-database \
    --query "Stacks[0].Outputs[?OutputKey=='DBEndpoint'].OutputValue" \
    --output text)

echo "Using DB Endpoint: $DB_ENDPOINT"

deploy_stack "enpm818n-application" "application.yaml" "CustomAmiId=$CUSTOM_UBUNTU_AMI_ID DBEndpoint=$DB_ENDPOINT"




echo ""
echo "===================================="
echo "  Successfully deployed all stacks  "
echo "===================================="
echo ""