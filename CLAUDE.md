# CLAUDE.md

Interview assignment (Dentsu, DevOps Lead, round 2). Current status, decisions and next
steps are in [docs/PROGRESS.md](docs/PROGRESS.md). Read it first.

## Goal

1. Use Terraform to deploy a **private** EKS **1.36** cluster: private API endpoint only,
   one managed node group (On-Demand t3.medium, AL2023, min/desired/max = 1/1/1), and the
   AWS Load Balancer Controller installed by Helm through Terraform with IRSA.
2. Build a Node.js Express app (`/health`, `/users`) and package it with a Dockerfile.
   A Jenkins pipeline builds it, pushes it to ECR and deploys it to EKS with kubectl,
   behind a public ALB.
3. Deliverables: modular Terraform, the app, the Dockerfile, the Jenkinsfile, the k8s
   manifests, and a README with prerequisites, deploy steps and validation steps.

## Repository layout

```
terraform/modules/   vpc, ecr, jenkins-host, eks, nodegroup, alb-controller
terraform/stacks/    01-base, 02-eks, 03-addons   (root configs)
app/                 Node.js source, tests, Dockerfile
k8s/                 deployment.yaml, service.yaml, ingress.yaml
Jenkinsfile
README.md            user-facing deploy/validate/teardown guide
docs/PROGRESS.md     status log for working sessions
```

## Three-stack design

The EKS API is private, so anything that calls the Kubernetes API has to run inside the
VPC. That includes the Terraform Helm provider, Jenkins kubectl and any manual kubectl.

| Stack | Runs from | Creates | State key |
|---|---|---|---|
| 01-base | laptop | VPC, 2 public + 2 private subnets, 1 NAT, ECR, Jenkins host | `01-base/terraform.tfstate` |
| 02-eks | Jenkins host (over SSM) | EKS cluster, node group, OIDC provider, core add-ons, access entry | `02-eks/terraform.tfstate` |
| 03-addons | Jenkins host (over SSM) | LBC IAM policy, IRSA role, `helm_release` | `03-addons/terraform.tfstate` |

Later stacks read earlier ones with `terraform_remote_state` from the same S3 bucket.

## Conventions

- Region `ap-south-1`. AZs `ap-south-1a` and `ap-south-1b`.
- Name prefix `dentsu-demo`, giving resource names like `dentsu-demo-<thing>`.
  **IAM roles and policies must be named `dentsu-demo-*`.** The Jenkins host role is only
  allowed to manage IAM resources under that prefix. Use managed policies, not inline
  `PutRolePolicy`.
- **No community modules.** Write plain `aws_*` resources in local modules.
- Modules contain no `provider` or `backend` blocks. Each module's `versions.tf` declares
  only `required_providers` with a `>=` constraint.
- Stacks pin exact versions: Terraform `~> 1.16.0`, AWS provider `6.67.0`.
  Tools on the host: kubectl `1.36.5`, Helm `3.22.0`, Terraform `1.16.4`.
- Stack backend: S3 bucket `dentsu-demo-mumbai` in ap-south-1, key `<stack>/terraform.tfstate`, `use_lockfile = true` (no DynamoDB table). The bucket name is
  set in each stack's `backend.hcl` (partial config).
- Each module has the files `main.tf`, `variables.tf`, `outputs.tf` and `versions.tf`.
  Each stack also has `providers.tf`, `backend.hcl` and `terraform.tfvars`.
- Tags: provider `default_tags` in each stack sets `Name` (fallback `dentsu-demo`), `Env = dentsu-demo`,
  `Project`, `ManagedBy` and `Stack`. Every taggable resource also sets its own `Name`,
  which overrides the fallback.
- Working rules: one phase per session, and plan before code. Claude may run
  `terraform fmt` and `validate`. **The user runs every `plan` and `apply`.** After
  each module, explain every resource and why it is needed.

## Commands

```bash
# 01-base (laptop)
cd terraform/stacks/01-base
terraform init -backend-config=backend.hcl
terraform plan -out tfplan && terraform apply tfplan
$(terraform output -raw ssm_shell_command)                 # shell on the host
$(terraform output -raw ssm_jenkins_port_forward_command)  # Jenkins on localhost:8080

# 02-eks and 03-addons (on the Jenkins host as ec2-user, after cloning). 03 is not written yet.
cd terraform/stacks/02-eks      # then 03-addons
terraform init -backend-config=backend.hcl
terraform plan -out tfplan && terraform apply tfplan
aws eks update-kubeconfig --region ap-south-1 --name dentsu-demo   # after 02
kubectl get nodes                                                  # expect 1 Ready
kubectl -n kube-system get deploy aws-load-balancer-controller     # after 03, expect 1/1

# Static checks (any stack)
terraform fmt -recursive terraform/ && terraform validate
```

**Teardown order:** delete the Ingress first with `kubectl delete -f k8s/ingress.yaml`
and wait for the ALB to be gone. Then run `terraform destroy` in 03-addons and 02-eks
(on the host), and finally in 01-base (on the laptop). An orphaned ALB or its security
groups block VPC deletion.
