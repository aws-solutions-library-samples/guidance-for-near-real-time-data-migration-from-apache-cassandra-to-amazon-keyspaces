#!/bin/bash

# Get the parameters from stack_resource_output file
ec2_id=$(cat stack_resources_output | grep Cassandraclientinstance | awk '{print $2}')
cassandraec2one=$(cat stack_resources_cassandra_output | grep CassandraInstanceOne | awk '{print $2}')
cassandraec2two=$(cat stack_resources_cassandra_output | grep CassandraInstanceTwo | awk '{print $2}')
cassandraec2three=$(cat stack_resources_cassandra_output | grep CassandraInstanceThree | awk '{print $2}')
vpc_id=$(cat stack_resources_output | grep keyspacesVPCId | awk '{print $2}')
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Function to disable API termination
disable_api_termination() {
  instance_id=$1
  echo "Disabling API termination for instance $instance_id"
  aws ec2 modify-instance-attribute --instance-id "$instance_id" --no-disable-api-termination
}

# Disable API termination for all instances
disable_api_termination "$ec2_id"
disable_api_termination "$cassandraec2one"
disable_api_termination "$cassandraec2two"
disable_api_termination "$cassandraec2three"

# Delete Cassandra kafka client instance
echo "Terminating Cassandra Kafka client instance $ec2_id"
delete_ec2=$(aws ec2 terminate-instances --instance-ids "$ec2_id")

# Delete Cassandra cluster EC2 instances
echo "Terminating Cassandra cluster EC2 instances"
delete_nodeone=$(aws ec2 terminate-instances --instance-ids "$cassandraec2one")
delete_nodetwo=$(aws ec2 terminate-instances --instance-ids "$cassandraec2two")
delete_nodethree=$(aws ec2 terminate-instances --instance-ids "$cassandraec2three")


echo "Deleting S3 bucket contents for cql-replicator-$AWS_ACCOUNT_ID-$AWS_REGION"
aws s3 rm s3://cql-replicator-$AWS_ACCOUNT_ID-$AWS_REGION --recursive

sleep 60

echo "Deleting S3 bucket cql-replicator-$AWS_ACCOUNT_ID-$AWS_REGION"
aws s3 rb s3://cql-replicator-$AWS_ACCOUNT_ID-$AWS_REGION


sleep 10


# Delete Cassandra cluster stack
echo "Deleting Cassandra cluster stack cass-cluster-stack"
aws cloudformation delete-stack --stack-name cass-cluster-stack

# Sleep for 120 seconds to allow all Cassandra instances to terminate
echo "Waiting 120 seconds for Cassandra instances to terminate"
sleep 120

# Now delete all VPC and IAM stack
echo "Deleting stack cfn-vpc-ks-stack"
aws cloudformation delete-stack --stack-name cfn-vpc-ks-stack

# Message to check CloudFormation console
echo "Stack deletion initiated for cfn-vpc-ks-stack. Please check the AWS CloudFormation console for the deletion status."

# Delete EC2 key pair
echo "Deleting EC2 key pair my-cass-kp"
aws ec2 delete-key-pair --key-name "my-cass-kp"
