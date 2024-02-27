
aws sqs create-queue --queue-name test-queue

aws sqs send-message --queue-url "https://sqs.ap-south-1.amazonaws.com/123123/test-queue" --message-body "Hello"

aws sqs receive-message --queue-url "https://sqs.ap-south-1.amazonaws.com/123123/test-queue"

# KEDA Operator Role
aws iam create-role --role-name keda-operator --assume-role-policy-document file://keda-operator-trust-policy.json
{
    "Role": {
        "Path": "/",
        "RoleName": "keda-operator",
        "RoleId": "AROAW47CR6OQRW3XQCAWP",
        "Arn": "arn:aws:iam::123123:role/keda-operator",
        "CreateDate": "2024-02-26T06:56:58+00:00",
        "AssumeRolePolicyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "",
                    "Effect": "Allow",
                    "Principal": {
                        "Federated": "arn:aws:iam::123123:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/123123123"
                    },
                    "Action": "sts:AssumeRoleWithWebIdentity",
                    "Condition": {
                        "StringEquals": {
                            "oidc.eks.ap-south-1.amazonaws.com/id/123123123:sub": "system:serviceaccount:keda:keda-operator"
                        }
                    }
                }
            ]
        }
    }
}

# AWS
aws iam create-policy --policy-name sqs-full-access --policy-document file://sqs-full-access-policy.json
{
    "Policy": {
        "PolicyName": "sqs-full-access",
        "PolicyId": "ANPAQSSX464CFMD22IACE",
        "Arn": "arn:aws:iam::123123:policy/sqs-full-access",
        "Path": "/",
        "DefaultVersionId": "v1",
        "AttachmentCount": 0,
        "PermissionsBoundaryUsageCount": 0,
        "IsAttachable": true,
        "CreateDate": "2024-02-25T17:45:49+00:00",
        "UpdateDate": "2024-02-25T17:45:49+00:00"
    }
}

aws iam create-role --role-name sqs-full-access --assume-role-policy-document file://trust-policy.json
{
    "Role": {
        "Path": "/",
        "RoleName": "sqs-full-access",
        "RoleId": "AROAQSSX464CIQONRV4ZN",
        "Arn": "arn:aws:iam::123123:role/sqs-full-access",
        "CreateDate": "2024-02-25T17:49:45+00:00",
        "AssumeRolePolicyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "",
                    "Effect": "Allow",
                    "Principal": {
                        "Federated": "arn:aws:iam::123123:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/123123"
                    },
                    "Action": "sts:AssumeRoleWithWebIdentity",
                    "Condition": {
                        "StringEquals": {
                            "oidc.eks.ap-south-1.amazonaws.com/id/123123:sub": "system:serviceaccount:default:aws-sqs"
                        }
                    }
                }
            ]
        }
    }
}

aws iam attach-role-policy --role-name sqs-full-access --policy-arn arn:aws:iam::123123:policy/sqs-full-access
