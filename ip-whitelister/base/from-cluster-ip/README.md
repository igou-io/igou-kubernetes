# AWS Security Group Updater CronJob

This Kubernetes CronJob updates an AWS security group's ingress rules to allow traffic from the current public IP address of the Kubernetes cluster. It runs every 15 minutes and checks if the cluster's IP is already allowed. If it is not present, it adds it. Additionally, the CronJob removes any old IPs that aren’t the public IP from the security group.

## Prerequisites

- A running Kubernetes cluster
- `kubectl` command-line tool installed and configured
- AWS account with the necessary permissions to manage security groups
- AWS CLI installed on your local machine (for encoding access keys)

## Configuration

1. Update the `configmap.yaml` file with the correct values for `PORT`, `PROTOCOL`, `GROUP_ID`, and `AWS_REGION`. These values represent the port and protocol to open in the security group, the security group ID, and the AWS region where the security group is located.
