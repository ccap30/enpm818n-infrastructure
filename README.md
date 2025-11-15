# ENPM 818N - Infrastructure Project

## Set up

Your environment should be able to use the AWS CLI
```bash
aws configure
```

Verify your environment is set up with
```bash
aws sts get-caller-identity
```

### Python Package: CloudFormation Linter
The [CloudFormation Linter](https://aws.amazon.com/blogs/devops/aws-cloudformation-linter-v1/) is an open source tool to validate cloudformation templates. It can be installed using pip.
```bash
pip3 install cfn-lint
```

## Structure
### params/
This directory contains parameter overrides that can be passed into cloudformation deploy commands. These files are currently unused.

### scripts/
This directory contains scripts to manage the CloudFormation deployments.
- `deploy-all.sh`: Deploys all stacks (Network, Database, Application) to AWS.
- `delete-all.sh`: Deletes all stacks (Application, Database, Network) from AWS.

### templates
This directory contains the various CloudFormation templates to deploy.

## Getting Started
Run `./scripts/deploy-all.sh` to deploy all stacks including the image builder (if necessary), network, database, and the application.

### Deploy Workflow (Last Updated: November 15th, 2025)
Currently, only the image builder and network templates exist.
- This script will first attempt to get the Custom AMI Image ID.
    - If it doesn't exist, it will run the image builder.
    - If it does, we'll will use that image when creating the EC2 instances.
- Deploy the network template

#### TODO
- Database stack
- Application stack

#### Notes about the EC2 Image Builder:
This is a free tool, but you pay for the resources to create (EC2 instance) and store (EBS snapshot) the image.
- Process: The image builder spins up an EC2 instance (m5.large, I haven't tried adjusting this), build the image based on an ImageBuilderComponent, test it (we don't have a test component), and store it in an EBS snapshot.
- Pricing: From what I've read, storing images costs about 50 cents per month. I've monitored this for a few days and it does appear to be low cost. Will keep an eye out just in case.
- Why we're using it: Allows us to automate the creation of a static base image for our EC2 instances. Everyone should have the same base image.
- What does this base image contain: See the ImageBuildComponent in the `image-builder.yaml` for the commands.
- What does this base image NOT do: It does not modify the `includes/connect.php` file with the RDS database endpoint. We need to set up the database first,  pass that in as an environment parameter when we create the EC2 instance, and then modify this file (likely just overwrite it with a custom script).

### Delete Workflow (Last Updated: November 15th, 2025)
- Deletes the network and image builder stacks

## Common Issues
### SSH'ing to a Ubuntu OS EC2 instance
- "ec2-user@X.X.X.X: Permission denied (publickey)"
- Make sure you ssh with the user "ubuntu" and not "ec2-user"w
```bash
ssh -i <key>.pem ubuntu@<EC2 public IP>
```