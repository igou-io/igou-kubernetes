# AWS Security Group Sync

This guide describes how to synchronize an AWS security group with a list of IP addresses from a Kubernetes ConfigMap using a periodic Kubernetes CronJob.

## Prerequisites

- `kubectl` command-line tool installed
- `kustomize` command-line tool installed
- An existing Kubernetes cluster
- AWS CLI version 2.x installed
- AWS access key and secret key with permissions to modify security groups

## Usage

1. Clone or download this repository to your local machine.

2. Create a file named `ip-addresses.txt` in the `config` directory. List the IP addresses or CIDRs you want to allow in your security group, one per line.

3. Create a Kubernetes secret with your AWS access key and secret key:

   ```sh
   kubectl create secret generic aws-credentials \
       --from-literal=aws_access_key_id=<YOUR_AWS_ACCESS_KEY> \
       --from-literal=aws_secret_access_key=<YOUR_AWS_SECRET_KEY>
4. Create a Kustomization file in the root directory of the repository:

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - cronjob.yaml

configMapGenerator:
  - name: allowed-ips
    files:
      - config/ip-addresses.txt
  - name: security-group-settings
    literals:
      - port=<YOUR_PORT>
      - protocol=<YOUR_PROTOCOL>
      - group-id=<YOUR_SECURITY_GROUP_ID>
      - aws-region=<YOUR_AWS_REGION>

secretGenerator:
  - name: aws-credentials
    literals:
      - aws_access_key_id=<YOUR_AWS_ACCESS_KEY>
      - aws_secret_access_key=<YOUR_AWS_SECRET_KEY>
```

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
