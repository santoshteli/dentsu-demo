# dentsu-demo

Private EKS 1.36 cluster with the AWS Load Balancer Controller, built with Terraform,
plus a Node.js app deployed through a Jenkins CI/CD pipeline behind a public ALB.

Region: `ap-south-1`. The EKS API endpoint is private only, so stacks 02 and 03 and
all `kubectl` commands run from the Jenkins host inside the VPC.

| Stack | Runs from | Creates |
|---|---|---|
| `terraform/stacks/01-base` | laptop | VPC, subnets, NAT, ECR, Jenkins host |
| `terraform/stacks/02-eks` | Jenkins host | EKS cluster, node group, OIDC provider |
| `terraform/stacks/03-addons` | Jenkins host | IRSA role, AWS Load Balancer Controller |

## Stack 01-base

### Prerequisites

- Terraform 1.16.x, AWS CLI v2, Session Manager plugin
- An S3 bucket for Terraform state in `ap-south-1`, created by hand
- Put the bucket name in `terraform/stacks/01-base/backend.hcl` and `terraform.tfvars`

### Deploy

```bash
cd terraform/stacks/01-base
terraform init -backend-config=backend.hcl
terraform plan -out tfplan
terraform apply tfplan
```

### Validate

The user data takes about 5 minutes after the instance starts.

```bash
# Shell on the host
$(terraform output -raw ssm_shell_command)
sudo cat /var/log/user-data.done            # timestamp means bootstrap finished
sudo tail -20 /var/log/user-data.log        # installed tool versions
sudo cat /var/lib/jenkins/secrets/initialAdminPassword

# On the laptop, in a second terminal
$(terraform output -raw ssm_jenkins_port_forward_command)
# Open http://localhost:8080 and log in with the initial admin password
```
