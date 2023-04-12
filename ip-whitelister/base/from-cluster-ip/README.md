# AWS Security Group Updater CronJob

This Kubernetes CronJob updates an AWS security group's ingress rules to allow traffic from the current public IP address of the Kubernetes cluster. It runs every 15 minutes and checks if the cluster's IP is already allowed. If it is not present, it adds it. Additionally, the CronJob removes any old IPs that aren’t the public IP from the security group.

## Prerequisites

- A running Kubernetes cluster
- `kubectl` command-line tool installed and configured
- AWS account with the necessary permissions to manage security groups
- AWS CLI installed on your local machine (for encoding access keys)

## Configuration

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - aws-security-group-cronjob.yaml
  - secret.yaml

configMapGenerator:
  - name: aws-security-group-config
    literals:
      - PORT=<your_port>
      - PROTOCOL=<your_protocol>
      - GROUP_ID=<your_security_group_id>
      - AWS_REGION=<your_aws_region>
```
