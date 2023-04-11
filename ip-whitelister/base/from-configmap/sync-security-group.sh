#!/bin/sh

set -euo pipefail

# Load IP addresses from the ConfigMap
echo "Loading IP addresses from ConfigMap..."
IP_ADDRESSES="$(cat /config/ip-addresses.txt)"

# Load security group settings from ConfigMap
echo "Loading security group settings from ConfigMap..."
PORT="$(cat /settings/port)"
PROTOCOL="$(cat /settings/protocol)"
SECURITY_GROUP_ID="$(cat /settings/group-id)"
AWS_REGION="$(cat /settings/aws-region)"

# Set AWS region
export AWS_DEFAULT_REGION="${AWS_REGION}"

# Get the list of existing IP addresses in the security group
echo "Getting existing IP addresses in the security group..."
EXISTING_IPS=$(aws ec2 describe-security-groups \
    --group-ids "${SECURITY_GROUP_ID}" \
    --query "SecurityGroups[0].IpPermissions[?ToPort==\`${PORT}\` && IpProtocol==\`${PROTOCOL}\`].IpRanges[].CidrIp" \
    --output text)

# Revoke IP addresses not present in the ConfigMap
echo "Revoking IP addresses not present in the ConfigMap..."
for EXISTING_IP in ${EXISTING_IPS}; do
    if ! echo "${IP_ADDRESSES}" | grep -qE "^${EXISTING_IP}\$"; then
        echo "Revoking IP address: ${EXISTING_IP}"
        aws ec2 revoke-security-group-ingress \
            --group-id "${SECURITY_GROUP_ID}" \
            --protocol "${PROTOCOL}" \
            --port "${PORT}" \
            --cidr "${EXISTING_IP}" || true
    fi
done

# Authorize IP addresses from the ConfigMap that are not already in the security group
echo "Authorizing new IP addresses from the ConfigMap..."
IFS=$'\n' # Set internal field separator to newline
for IP in ${IP_ADDRESSES}; do
    if ! echo "${EXISTING_IPS}" | grep -qE "^${IP}\$"; then
        echo "Authorizing IP address: ${IP}"
        aws ec2 authorize-security-group-ingress \
            --group-id "${SECURITY_GROUP_ID}" \
            --protocol "${PROTOCOL}" \
            --port "${PORT}" \
            --cidr "${IP}" || true
    fi
done
unset IFS

echo "Security group synchronization complete."
