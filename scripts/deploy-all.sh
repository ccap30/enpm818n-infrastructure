#!/bin/bash

set -e

# Variables
REPO_ROOT=$(git rev-parse --show-toplevel)
REGION="us-east-1"
CAPABILITIES="CAPABILITY_NAMED_IAM"
WEB_APP_REPO="$REPO_ROOT/../818N-E_Commerce_Application"

function validate_stack {
    TEMPLATE_FILE=$1
    echo "Validating CloudFormation template: $TEMPLATE_FILE"
    cfn-lint --template $TEMPLATE_FILE

    # Alternatively, you can use the following, but it prints the formatted template
    # aws cloudformation validate-template --template-body file://$TEMPLATE_FILE
}

function deploy_stack {
    STACK_NAME=$1
    TEMPLATE_FILE="$REPO_ROOT/templates/$2"  # CloudFormation yaml file name
    PARAMETER_OVERRIDES="$3"  # Any parameter overrides key,value pairs

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
    if [[ "$PARAMETER_OVERRIDES" != "" ]]; then
            aws cloudformation deploy \
        --stack-name $STACK_NAME \
        --template-file $TEMPLATE_FILE \
        --capabilities $CAPABILITIES \
        --region $REGION \
        --parameter-overrides $PARAMETER_OVERRIDES
    else
        aws cloudformation deploy \
            --stack-name $STACK_NAME \
            --template-file $TEMPLATE_FILE \
            --capabilities $CAPABILITIES \
            --region $REGION
    fi
}




echo "There are prerequiste steps required before deploying the stacks."
echo "This should be done on AWS. We have not automated these steps."
echo " - Set up a Route 53 domain"
echo " - Create a certificate with the Certificate Manager"
echo " - Add certificate record to the domain"
echo ""
echo "Sleeping for 10 seconds so you can read this. Press 'CTRL + C' now to stop deployment."
sleep 10

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



######################################
# Deploy S3 Bucket and Static Assets #
######################################
S3_BUCKET_STACK_NAME="enpm818n-s3-bucket"
deploy_stack "$S3_BUCKET_STACK_NAME" "s3.yaml"

S3_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name $S3_BUCKET_STACK_NAME \
    --query "Stacks[0].Outputs[?OutputKey=='S3BucketName'].OutputValue" \
    --output text)

echo "Syncing asset files (.png, .jpg, .js, .css) with the S3 bucket..."
aws s3 sync "$WEB_APP_REPO/assets" "s3://$S3_BUCKET/assets" \
--exclude "*" \
--include "*.png" \
--include "*.jpg" \
--include "*.js" \
--include "*.css" \
--only-show-errors



############
# ACM_CERT #
############
ACM_CERT=$(aws acm list-certificates \
    --query "CertificateSummaryList[?DomainName=='carl-aws.com'].CertificateArn" \
    --output text)



##################
# Deploy Web App #
##################
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
    echo "Using key pair: '$KEY_NAME'"
fi

DB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name enpm818n-database \
    --query "Stacks[0].Outputs[?OutputKey=='DBEndpoint'].OutputValue" \
    --output text)

deploy_stack "enpm818n-application" \
    "application.yaml" \
    "CustomAmiId=$CUSTOM_UBUNTU_AMI_ID DBEndpoint=$DB_ENDPOINT AcmCertificateArn=$ACM_CERT"



#####################
# Deploy CloudFront #
#####################
deploy_stack "enpm818n-cloudfront" "cloudfront.yaml" "AcmCertificateArn=$ACM_CERT"


echo ""
echo "===================================="
echo "  Successfully deployed all stacks  "
echo "===================================="
echo ""