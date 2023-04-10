#!/bin/sh

set -euo pipefail

# Load IP addresses from the ConfigMap
echo "Loading IP addresses from ConfigMap..."
IP_ADDRESSES="$(cat /config/allowed-ips)"

# Load security group settings from ConfigMap
echo "Loading security group settings from ConfigMap..."
PORT="$(cat /settings/port)"
PROTOCOL="$(cat /settings/protocol)"
SECURITY_GROUP_ID="$(cat /settings/group-id)"
AWS_REGION="$(cat /settings/aws-region)"

# Set AWS region
export AWS_DEFAULT_REGION="${AWS_REGION}"

# Validate the IP addresses before getting the existing IPs in the security group
echo "Validating IP addresses..."
INVALID_IPS=false
while read -r IP; do
    if ! echo "${IP}" | grep -qE '^(\d{1,3}\.){3}\d{1,3}(\/([0-9]|[1-2][0-9]|3[0-2]))?$'; then
        echo "Invalid IP address or CIDR: ${IP}"
        INVALID_IPS=true
    fi
done <<< "${IP_ADDRESSES}"

if [ "${INVALID_IPS}" = true ]; then
    echo "Aborting due to invalid IP addresses."
    exit 1
fi

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
            --cidr "${EXISTING_IP}"
    fi
done

# Authorize IP addresses from the ConfigMap that are not already in the security group
echo "Authorizing new IP addresses from the ConfigMap..."
while read -r IP; do
    if ! echo "${EXISTING_IPS}" | grep -qE "^${IP}\$"; then
        echo "Authorizing IP address: ${IP}"
        aws ec2 authorize-security-group-ingress \
            --group-id "${SECURITY_GROUP_ID}" \
            --protocol "${PROTOCOL}" \
            --port "${PORT}" \
            --cidr "${IP}"
    fi
done <<< "${IP_ADDRESSES}"

echo "Security group synchronization complete."
