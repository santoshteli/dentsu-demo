# dentsu-demo

A private Amazon EKS 1.36 cluster with the AWS Load Balancer Controller, built with Terraform, and a Node.js application deployed to it by a Jenkins CI/CD pipeline behind a public Application Load Balancer.

Region: `ap-south-1` (Mumbai).

## Repositories

| Repository | Contents |
|---|---|
| **[santoshteli/dentsu-demo](https://github.com/santoshteli/dentsu-demo)** (this repo) | Terraform for the VPC, ECR, Jenkins host, EKS cluster, node group and AWS Load Balancer Controller, and the infrastructure pipeline (`Jenkinsfile.infra`) |
| **[santoshteli/dentsu-demo-app](https://github.com/santoshteli/dentsu-demo-app)** | Node.js application and tests, Dockerfile, Kubernetes manifests, and the application CI/CD pipeline (`Jenkinsfile`) |

Platform and application are separate on purpose: they change at different rates and have different owners, an application commit only triggers the application pipeline, and application developers never need write access to the Terraform.

### Where each deliverable lives

| Deliverable | Location |
|---|---|
| EKS 1.36 cluster, private API endpoint only | `terraform/modules/eks`, `terraform/stacks/02-eks` |
| Managed node group: On-Demand, t3.medium, Amazon Linux 2023, min/desired/max 1/1/1 | `terraform/modules/nodegroup`, `terraform/stacks/02-eks` |
| AWS Load Balancer Controller via Helm, managed by Terraform, with IRSA | `terraform/modules/alb-controller`, `terraform/stacks/03-addons` |
| Reusable Terraform modules | `terraform/modules` (vpc, ecr, jenkins-host, eks, nodegroup, alb-controller) |
| Node.js REST API (`/health`, `/users`) | `src/`, `test/` in dentsu-demo-app |
| Dockerfile | `Dockerfile` in dentsu-demo-app |
| CI/CD pipeline: Git, npm, Docker, ECR, kubectl | `Jenkinsfile` in dentsu-demo-app |
| Kubernetes manifests: deployment, service, ingress (ALB) | `k8s/` in dentsu-demo-app |
| README: prerequisites, deployment, validation | This file |

## Architecture

```
                         Internet
             |                                  |
     Jenkins ALB (HTTP, your IP only)     App ALB (HTTP, public)
             |                                  |   created by the Load Balancer
+------------|----------------------------------|---Controller from the Ingress
|  VPC 10.0.0.0/16, 2 AZs                       |
|  Public subnets:  NAT gateway, both ALBs      |
|  Private subnets: |                           |
|     Jenkins host (no public IP) ----443----> EKS API (private endpoint only)
|        Terraform, kubectl, Docker            |
|        pipelines dentsu-infra, dentsu-app     v
|                                     EKS node (t3.medium, AL2023)
|                                       app pods  <- ALB targets pod IPs
|                                       Load Balancer Controller (IRSA)
+---------------------------------------------------------------+
   ECR: dentsu-demo-app images        S3: Terraform state (one key per stack)
```

Because the EKS API is private, everything that talks to Kubernetes runs inside the VPC, on the Jenkins host. The Terraform is split into three stacks accordingly:

| Stack | Runs from | Creates | Resources |
|---|---|---|---|
| `01-base` | Laptop | VPC, 2 public and 2 private subnets, 1 NAT gateway, ECR repository, Jenkins host and its ALB | 33 |
| `02-eks` | Jenkins host (pipeline `dentsu-infra`) | EKS cluster, managed node group, OIDC provider, add-ons (vpc-cni, kube-proxy, CoreDNS), admin access entry | 16 |
| `03-addons` | Jenkins host (pipeline `dentsu-infra`) | IAM policy and IRSA role, AWS Load Balancer Controller Helm release | 4 |

### Key design decisions

- **Private API endpoint only.** Reached from the Jenkins host inside the VPC, allowed by a security group rule on port 443 and an EKS access entry for the host's IAM role.
- **No stored credentials.** Terraform, the AWS CLI, Docker (ECR login) and kubectl on the Jenkins host all use the host's IAM role. Jenkins holds no AWS keys and no registry passwords.
- **No SSH.** Shell access is through AWS Systems Manager Session Manager. The Jenkins host has no public IP and no inbound rules except 8080 from its own ALB.
- **IRSA for the controller.** Its IAM role trusts only the service account `kube-system/aws-load-balancer-controller` in this cluster, through the cluster's OIDC provider. The official IAM policy for the pinned controller version is committed in the module.
- **Public ALB to private pods.** The Ingress uses `target-type: ip`: the ALB in the public subnets sends traffic straight to pod IPs, which are VPC addresses thanks to the VPC CNI.
- **Pinned versions.** Terraform 1.16, AWS provider 6.67.0, Helm provider 3.3.0, EKS add-ons, controller and chart 3.6.0, kubectl 1.36.5. No community modules.
- **Reviewed changes.** The infrastructure pipeline saves each plan as a build artifact and waits for manual approval before applying exactly that plan.

## Repository layout

```
terraform/
  modules/
    vpc/             VPC, subnets (with ALB subnet tags), IGW, NAT, route tables
    ecr/             repository with scan on push, immutable tags, lifecycle policy
    jenkins-host/    EC2 host, IAM role, security group, user data, optional ALB
    eks/             cluster, cluster role, 443 rule, access entries, OIDC provider
    nodegroup/       node role, launch template, managed node group
    alb-controller/  IAM policy (official, v3.6.0), IRSA role, Helm release
  stacks/
    01-base/         applied from the laptop
    02-eks/          applied from the Jenkins host
    03-addons/       applied from the Jenkins host
Jenkinsfile.infra    plan, approve, apply or destroy for 02-eks and 03-addons
CLAUDE.md            project conventions (region, naming, pinned versions)
```

## Prerequisites

**On the laptop**

| Tool | Version used |
|---|---|
| Terraform | 1.16.x |
| AWS CLI | v2 |
| Session Manager plugin for the AWS CLI | any recent |
| Git | any recent |
| Node.js and Docker | Node 24 LTS, Docker 29 (application work only) |

**In AWS**

- An AWS account and an IAM identity that can create VPC, EC2, IAM, ECR, EKS and ELB resources (for stack 01-base).
- A billing alarm (recommended).
- An S3 bucket for Terraform state in `ap-south-1`, created by hand, with versioning on and public access blocked. All three stacks use it, each with its own key.

Everything else (kubectl, Helm, Terraform, Docker, Jenkins) is installed on the Jenkins host by its user data.

## Deployment

### 1. State bucket name

Put your bucket name in these files (this repo uses `dentsu-demo-mumbai`):

- `terraform/stacks/*/backend.hcl`: `bucket = "<bucket>"`
- `terraform/stacks/*/terraform.tfvars`: `state_bucket_name = "<bucket>"`

### 2. Stack 01-base (from the laptop)

```bash
cd terraform/stacks/01-base
terraform init -backend-config=backend.hcl
terraform plan -out tfplan        # review: 33 to add
terraform apply tfplan            # about 5 minutes
terraform output
```

The host installs its tools on first boot (about 5 minutes). It then shows as Online in Systems Manager.

### 3. Set up Jenkins (once)

**Open a shell on the host:** run `$(terraform output -raw ssm_shell_command)`, or in the console go to EC2 → Instances → `dentsu-demo-jenkins` → Connect → Session Manager.

```bash
sudo cat /var/log/user-data.done                     # present when setup has finished
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

**Open the Jenkins UI** in either of two ways:

- **Port forward** (laptop with the AWS CLI): `$(terraform output -raw ssm_jenkins_port_forward_command)`, then open http://localhost:8080.
- **Through the Jenkins ALB** (any browser): in EC2 → Security Groups → `dentsu-demo-jenkins-alb`, add an inbound rule **HTTP, Source: My IP**. Then open `terraform output -raw jenkins_url`. Remove the rule when finished.

**Then, in Jenkins:**

1. Complete the setup wizard with the **suggested plugins**, and create an admin user.
2. If you use the ALB, set **Manage Jenkins → System → Jenkins URL** to the ALB URL. Without it, the approval buttons do not work.
3. Create two **Pipeline** jobs, each with "Pipeline script from SCM", SCM **Git**, branch `*/main`, and no credentials (both repositories are public):

| Job | Repository URL | Script path |
|---|---|---|
| `dentsu-infra` | https://github.com/santoshteli/dentsu-demo.git | `Jenkinsfile.infra` |
| `dentsu-app` | https://github.com/santoshteli/dentsu-demo-app.git | `Jenkinsfile` |

4. Run `dentsu-infra` once with **Build Now**, so Jenkins registers its parameters. That first run only plans `02-eks`; it changes nothing. Run `dentsu-app` for the first time in step 5, once the cluster exists; that first run also registers its polling trigger.

### 4. Stacks 02-eks and 03-addons (pipeline `dentsu-infra`)

**Build with Parameters → ACTION = `apply`, STACK = `all`.**

| Approval prompt | What happens | Time |
|---|---|---|
| APPLY 02-eks? Plan: 16 to add | EKS cluster, add-ons vpc-cni and kube-proxy, node group, CoreDNS. The verify stage waits for the node to be Ready. | about 15 min |
| APPLY 03-addons? Plan: 4 to add | IAM policy, IRSA role, controller Helm release. The verify stage checks the deployment and fails on permission errors in the controller logs. | about 2 min |

Each plan is saved as a build artifact (`plan-02-eks.txt`, `plan-03-addons.txt`). Other parameter values: `ACTION=plan` only shows changes; `STACK=02-eks` or `03-addons` runs one stack.

**Manual alternative** (on the Jenkins host, in a Session Manager shell):

```bash
sudo su - ec2-user
git clone https://github.com/santoshteli/dentsu-demo.git
cd dentsu-demo/terraform/stacks/02-eks          # then the same in 03-addons
terraform init -backend-config=backend.hcl
terraform plan -out tfplan
terraform apply tfplan
```

### 5. Application (pipeline `dentsu-app`)

**Build Now.** The pipeline:

1. Checks out the code and works out the image tag (the git SHA).
2. Runs `npm ci` and the tests.
3. Builds the Docker image.
4. Pushes it to ECR.
5. Applies the Kubernetes manifests.
6. Waits for the rollout. If the rollout fails, it rolls back.
7. Prints the application URL.

After that, every `git push` to the application repository is deployed automatically: Jenkins polls every 2 minutes, because a GitHub webhook cannot reach a private Jenkins. See the [application README](https://github.com/santoshteli/dentsu-demo-app#readme) for details.

## Validation

Run these on the Jenkins host (Session Manager shell, as `ec2-user`). Refresh kubeconfig first; this is needed again whenever the cluster is recreated.

```bash
aws eks update-kubeconfig --region ap-south-1 --name dentsu-demo
```

| Check | Command | Expected |
|---|---|---|
| Kubernetes version and private endpoint | `aws eks describe-cluster --name dentsu-demo --region ap-south-1 --query 'cluster.[version,resourcesVpcConfig.endpointPrivateAccess,resourcesVpcConfig.endpointPublicAccess,accessConfig.authenticationMode]' --output text` | `1.36  True  False  API` |
| Node group settings | `aws eks describe-nodegroup --cluster-name dentsu-demo --nodegroup-name dentsu-demo-ng --region ap-south-1 --query 'nodegroup.[capacityType,instanceTypes[0],amiType,scalingConfig.minSize,scalingConfig.desiredSize,scalingConfig.maxSize,status]' --output text` | `ON_DEMAND  t3.medium  AL2023_x86_64_STANDARD  1  1  1  ACTIVE` |
| Node is Ready | `kubectl get nodes` | 1 node, `Ready`, version `v1.36.x` |
| Add-ons | `aws eks list-addons --cluster-name dentsu-demo --region ap-south-1 --output text` | `coredns`, `kube-proxy`, `vpc-cni` |
| System pods | `kubectl get pods -n kube-system` | aws-node, kube-proxy, 2 coredns, aws-load-balancer-controller, all Running |
| Controller deployment | `kubectl -n kube-system get deploy aws-load-balancer-controller` | `READY 1/1` |
| Helm release | `helm list -n kube-system` | `aws-load-balancer-controller`, `deployed`, chart `3.6.0` |
| IngressClass | `kubectl get ingressclass` | `alb`, controller `ingress.k8s.aws/alb` |
| IRSA works | `kubectl -n kube-system get pod -l app.kubernetes.io/name=aws-load-balancer-controller -o jsonpath='{.items[0].spec.containers[0].env[*].name}'` | includes `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` |
| No permission errors | `kubectl -n kube-system logs deploy/aws-load-balancer-controller \| grep -ciE 'accessdenied\|unauthorizedoperation'` | `0` |
| Application pods | `kubectl -n dentsu-demo-app get deploy,pods,ingress` | 2/2 pods Running, readiness gates 1/1, Ingress with an ALB hostname |
| Application through the ALB (from anywhere) | `curl http://<ALB hostname>/health` and `curl http://<ALB hostname>/users` | `{"status":"ok"}` and the JSON list of users |

### Verified results

All of the above was run on 2026-10-11 against the deployed environment. Excerpts:

```
$ kubectl get nodes
NAME                                         STATUS   ROLES    AGE     VERSION
ip-10-0-24-119.ap-south-1.compute.internal   Ready    <none>   8m25s   v1.36.4-eks-3b4a6ca

$ aws eks describe-cluster ...   (version, private, public, authentication mode)
1.36    True    False   API

$ kubectl -n kube-system get deploy aws-load-balancer-controller
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
aws-load-balancer-controller   1/1     1            1           3m34s

$ kubectl get ingressclass
NAME   CONTROLLER            PARAMETERS   AGE
alb    ingress.k8s.aws/alb   <none>       3m35s

$ helm list -n kube-system
NAME                          NAMESPACE    REVISION  STATUS    CHART                               APP VERSION
aws-load-balancer-controller  kube-system  1         deployed  aws-load-balancer-controller-3.6.0  v3.6.0

$ kubectl -n dentsu-demo-app get pods
NAME                              READY   STATUS    RESTARTS   AGE     READINESS GATES
dentsu-demo-app-9876767cb-98qfd   1/1     Running   0          3m16s   1/1
dentsu-demo-app-9876767cb-wf9kx   1/1     Running   0          3m38s   1/1

$ curl http://<app ALB>/health
{"status":"ok"}

$ curl http://<app ALB>/users
[{"id":1,"name":"Asha Rao - V2","role":"admin"},{"id":2,"name":"Vikram Shah","role":"developer"},{"id":3,"name":"Meera Iyer","role":"viewer"}]
```

The last response comes from a code change that was committed and pushed with no manual step: Jenkins detected the commit, built and pushed the image, and rolled it out.

Also checked:

- The EKS control plane took 8 minutes 52 seconds to create.
- The node instance carries the project tags (`Name`, `Env`).
- The node's metadata service hop limit is 1, so pods cannot use the node's credentials.

## Teardown

Delete the application's Ingress before the cluster, so the controller removes the application ALB. An orphaned ALB would block VPC deletion. The pipeline does this for you:

1. **`dentsu-infra` → ACTION = `destroy`, STACK = `all`.** It destroys `03-addons` first, after deleting all Ingresses and waiting for their ALBs to go, then `02-eks`. Each stack asks for approval. Destroying `02-eks` on its own is refused while the controller is still installed.
2. **Stack 01-base, from the laptop, last:**

```bash
cd terraform/stacks/01-base
terraform plan -destroy -out tfplan
terraform apply tfplan
```

To pause between sessions instead, destroy only 02 and 03 and stop the Jenkins host; its Jenkins configuration is kept.

## Cost (approximate, ap-south-1)

| Running | Per hour |
|---|---|
| Stack 01-base (NAT gateway, Jenkins host, Jenkins ALB) | about $0.14 |
| Add EKS control plane, one t3.medium node and the application ALB | about $0.33 in total |
