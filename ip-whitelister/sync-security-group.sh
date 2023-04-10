#!/bin/sh

set -euo pipefail

# Load IP addresses from the ConfigMap
IP_ADDRESSES="$(cat /config/ip-addresses.txt)"

# Load security group settings from ConfigMap
PORT="$(cat /settings/port)"
PROTOCOL="$(cat /settings/protocol)"
SECURITY_GROUP_ID="$(cat /settings/group-id)"
AWS_REGION="$(cat /settings/aws-region)"

# Configure AWS CLI
export AWS_ACCESS_KEY_ID=$(cat /secrets/aws_access_key_id)
export AWS_SECRET_ACCESS_KEY=$(cat /secrets/aws_secret_access_key)
export AWS_DEFAULT_REGION="$AWS_REGION"

# Get the current rules from the security group
EXISTING_IPS=$(aws ec2 describe-security-groups --group-ids "$SECURITY_GROUP_ID" --query 'SecurityGroups[0].IpPermissions[].IpRanges[].CidrIp' --output text | tr '\t' '\n')

# Add IPs from ConfigMap to the security group
for IP in $IP_ADDRESSES; do
  if ! echo "$EXISTING_IPS" | grep -q "$IP"; then
    aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol "$PROTOCOL" --port "$PORT" --cidr "$IP" || echo "Error: Failed to add IP $IP"
  fi
done

# Remove IPs from the security group that are not present in the ConfigMap
for IP in $EXISTING_IPS; do
  if ! echo "$IP_ADDRESSES" | grep -q "$IP"; then
    aws ec2 revoke-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol "$PROTOCOL" --port "$PORT" --cidr "$IP" || echo "Error: Failed to remove IP $IP"
  fi
done
