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
Run `./scripts/deploy-all.sh` to deploy all stacks (only network as of now).