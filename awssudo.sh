#!/bin/bash

# 1. connect as ops using OKTA
OKTA_DOMAIN=godaddy.okta.com; KEY=$(openssl rand -hex 18); eval $(aws-okta-processor authenticate -e -o $OKTA_DOMAIN -u $LOGNAME -k $KEY)
ACCOUNT_ID=$(aws sts get-caller-identity | jq -r .Account)

# 2. look in secrets manager and record access key id and secret access key for deploy user
printf "\nGetting credentials for deploy user...\n"
SECERT_LIST=$(aws secretsmanager list-secrets --filters Key=name,Values=/Secrets/IAMUser/GD-AWS-DeployUser)
echo "\nSECERT_LIST ${SECERT_LIST} \n"
SECRET_ID=$(aws secretsmanager list-secrets --filters Key=description,Values=GD-AWS-DeployUser | jq -r .SecretList[0].Name)
echo "SECRET_ID ${SECRET_ID} \n"

# echo "${SECRET_ID}" | jq -c
if [ -z $SECRET_ID ]; then
    printf "\nUnable to retrieve DeployUser secret"
    return 1
fi


SECRET_STRING=$( \
    aws secretsmanager get-secret-value \
        --secret-id "${SECRET_ID}" | \
    jq -r .SecretString \
    )
echo "SECRET_STRING ${SECRET_STRING} \n"

NEW_AWS_ACCESS_KEY_ID=$(echo "${SECRET_STRING}" | jq -r .AccessKeyId)
NEW_AWS_SECRET_ACCESS_KEY=$(echo "${SECRET_STRING}" | jq -r .SecretAccessKey)

# 3. look in parameter store to get the ARN of the deploy role
PARAMETER_NAME='/AdminParams/IAM/DeployRoleArn'
ROLE_ARN=$(aws ssm get-parameter --name "${PARAMETER_NAME}" | jq -r .Parameter.Value)
echo "Assuming role ${ROLE_ARN}"

# 4. export access key id and secret access key from secrets manager and unset session token
export AWS_ACCESS_KEY_ID=$NEW_AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$NEW_AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

# 5: assume the role that we pulled from parameter store
printf "Getting credentials for assuming deploy role...\n"
ASSUMED_CREDS=$( \
    aws sts assume-role \
        --role-arn "${ROLE_ARN}" \
        --role-session-name "${RANDOM}" | \
    jq .Credentials \
    )
echo "\nASSUMED_CREDS ${ASSUMED_CREDS} \n"

# 6. export access key id, secret access key, and session token from role assumption in step 4
export AWS_ACCESS_KEY_ID=$(echo $ASSUMED_CREDS | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $ASSUMED_CREDS | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $ASSUMED_CREDS | jq -r .SessionToken)

printf "\nSet up account done...\n"

printf "\nChecking aws profile...\n"
AWS_PROFILE=$(aws configure list)
echo "AWS_PROFILE ${AWS_PROFILE}"