#!/bin/bash

# Replace with your VPC ID
VPC_ID=$(cat stack_resources_output | grep CassandraVPCId | awk '{print $2}')
#VPC_ID=vpc-example

# Delete VPC Endpoints
echo "Deleting VPC Endpoints..."
ENDPOINT_IDS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[*].VpcEndpointId" --output text)
if [ "$ENDPOINT_IDS" != "" ]; then
  aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $ENDPOINT_IDS
fi

# Delete Security Groups (except default)
echo "Deleting Security Groups..."
SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
for sg in $SG_IDS; do
  # Detach network interfaces
  NETWORK_INTERFACE_IDS=$(aws ec2 describe-network-interfaces --filters "Name=group-id,Values=$sg" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
  for ni in $NETWORK_INTERFACE_IDS; do
    aws ec2 detach-network-interface --attachment-id $(aws ec2 describe-network-interfaces --network-interface-ids $ni --query "NetworkInterfaces[*].Attachment.AttachmentId" --output text)
    aws ec2 delete-network-interface --network-interface-id $ni
  done

  aws ec2 delete-security-group --group-id $sg
done

# Delete Subnets
echo "Deleting Subnets..."
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text)
for subnet in $SUBNET_IDS; do
  # Delete instances in the subnet
  INSTANCE_IDS=$(aws ec2 describe-instances --filters "Name=subnet-id,Values=$subnet" --query "Reservations[*].Instances[*].InstanceId" --output text)
  for instance_id in $INSTANCE_IDS; do
    aws ec2 terminate-instances --instance-ids $instance_id
    aws ec2 wait instance-terminated --instance-ids $instance_id
  done

  # Delete NAT gateways in the subnet
  NAT_GATEWAY_IDS=$(aws ec2 describe-nat-gateways --filter "Name=subnet-id,Values=$subnet" --query "NatGateways[*].NatGatewayId" --output text)
  for nat_gateway_id in $NAT_GATEWAY_IDS; do
    aws ec2 delete-nat-gateway --nat-gateway-id $nat_gateway_id
    aws ec2 wait nat-gateway-deleted --nat-gateway-id $nat_gateway_id
  done

  # Delete network interfaces in the subnet
  NETWORK_INTERFACE_IDS=$(aws ec2 describe-network-interfaces --filters "Name=subnet-id,Values=$subnet" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
  for ni in $NETWORK_INTERFACE_IDS; do
    aws ec2 delete-network-interface --network-interface-id $ni
  done

  aws ec2 delete-subnet --subnet-id $subnet
done

# Delete Route Tables (except main)
echo "Deleting Route Tables..."
RTB_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query "RouteTables[].RouteTableId[]" --output text)
for rtb in $RTB_IDS; do
  # Disassociate any route table associations
  ASSOCIATION_IDS=$(aws ec2 describe-route-tables --route-table-ids $rtb --query "RouteTables[*].Associations[*].RouteTableAssociationId" --output text)
  for association_id in $ASSOCIATION_IDS; do
    aws ec2 disassociate-route-table --association-id $association_id
  done

  aws ec2 delete-route-table --route-table-id $rtb
done

# Detach and delete Internet Gateways
echo "Deleting Internet Gateways..."
IGW_IDS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[*].InternetGatewayId" --output text)
for igw in $IGW_IDS; do
  aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID
  aws ec2 delete-internet-gateway --internet-gateway-id $igw
done

# Delete NAT Gateways (if any are left)
echo "Deleting NAT Gateways..."
NATGATEWAY_IDS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[*].NatGatewayId" --output text)
for natgw in $NATGATEWAY_IDS; do
  aws ec2 delete-nat-gateway --nat-gateway-id $natgw
done

# Wait for NAT Gateways to be deleted
while true; do
  PENDING_NATGATEWAYS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=pending,deleting" --query "NatGateways[*].NatGatewayId" --output text)
  if [ -z "$PENDING_NATGATEWAYS" ]; then
    break
  fi
  echo "Waiting for NAT Gateways to delete..."
  sleep 10
done

# Finally, delete the VPC
echo "Deleting VPC..."
aws ec2 delete-vpc --vpc-id $VPC_ID

echo "VPC and all associated resources have been deleted."

