# Progress

Last updated: 2026-10-08 (Phase 2 code written).

## Phase status

| Phase | Scope | Status |
|---|---|---|
| 0 | AWS account, billing alarm, laptop tools, GitHub repo, state bucket, CLAUDE.md | Done by the user. Private repo `santoshteli/dentsu-demo`; state bucket `dentsu-demo-mumbai` (ap-south-1). |
| 1 | Stack 01-base: vpc, ecr and jenkins-host modules | **Applied and checked.** Jenkins host is Online in SSM; the user confirmed the Jenkins login. **Needs a re-apply** for the Jenkins IAM policy changes listed below. |
| 2 | Stack 02-eks: eks and nodegroup modules | **Code written, not applied.** `fmt` and `validate` pass. |
| 3 | Stack 03-addons: alb-controller module | Not started |
| 4 | Express app and Dockerfile | Not started |
| 5 | k8s manifests, deployed by hand | Not started |
| 6 | Jenkinsfile and Jenkins setup | Not started. A GitHub fine-grained token (read-only, this repo) is already stored in Jenkins credentials. |
| 7 | README, teardown, rehearsal | README has the 01-base section only |

## What exists

### Stack 01-base (applied)

- `modules/vpc`: VPC 10.0.0.0/16 with DNS on, IGW.
  - Public subnets 10.0.0.0/24 and 10.0.1.0/24, tagged `kubernetes.io/role/elb=1`.
  - Private subnets 10.0.16.0/20 and 10.0.32.0/20, tagged `kubernetes.io/role/internal-elb=1`.
  - One NAT gateway in public[0]. The `private_subnet_ids` output depends on the NAT
    route, so consumers wait until the subnets have egress.
- `modules/ecr`: repository `dentsu-demo-app`. IMMUTABLE tags, scan on push,
  `force_delete`, lifecycle rule keeping the last 10 images.
- `modules/jenkins-host`: AL2023 t3.medium in private[0].
  - Instance: no public IP, no SSH key, IMDSv2 with hop limit 1, 30 GB encrypted gp3.
  - Security group: no inbound rules, all outbound.
  - Role `dentsu-demo-jenkins`:
    - `AmazonSSMManagedInstanceCore`.
    - Inline `ecr-push`, scoped to the repository.
    - Inline `terraform-stacks-02-03`: state bucket, `eks:*`, EC2 describe, security
      groups, launch templates and `RunInstances`, IAM roles and policies under
      `dentsu-demo-*`, the EKS OIDC provider, EKS service-linked roles, and an explicit
      Deny of `iam:*` on its own role.
  - User data installs Java 21, Jenkins LTS, Docker, Git, kubectl 1.36.5, Helm 3.22.0
    and Terraform 1.16.4, with checksums verified, and adds `jenkins` to the `docker`
    group.
- Tags on every taggable resource: `Name`, `Env=dentsu-demo`, `Project`, `ManagedBy`,
  `Stack`.

### Stack 02-eks (written, not applied)

- `modules/eks`:
  - IAM role `dentsu-demo-eks-cluster` with `AmazonEKSClusterPolicy`.
  - `aws_eks_cluster` `dentsu-demo`: version 1.36, private endpoint only,
    `authentication_mode = "API"`, `bootstrap_cluster_creator_admin_permissions = false`,
    `bootstrap_self_managed_addons = false`, `upgrade_policy = STANDARD`.
  - An SG rule allowing 443 from the Jenkins SG into the cluster SG.
  - An access entry with `AmazonEKSClusterAdminPolicy` for each admin principal.
  - An IAM OIDC provider (no thumbprint).
- `modules/nodegroup`:
  - IAM role `dentsu-demo-eks-node` with WorkerNode, CNI and ECR PullOnly policies.
  - Launch template `dentsu-demo-eks-node`: 20 GB encrypted gp3 disk, IMDSv2 with hop
    limit 1, and tag specifications for the instance, volume and ENI (copied from the
    provider's default tags through the `aws_default_tags` data source). No AMI ID, so
    EKS picks the AMI from `ami_type` and merges its bootstrap.
  - Node group `dentsu-demo-ng`: `AL2023_x86_64_STANDARD`, ON_DEMAND, t3.medium,
    1/1/1, both private subnets.
- `stacks/02-eks`:
  - `data.tf` reads the 01-base outputs with `terraform_remote_state`.
  - `main.tf` calls the two modules. Admins are the Jenkins role plus
    `var.additional_admin_principal_arns`, which is empty by default.
  - `addons.tf`: vpc-cni `v1.22.4-eksbuild.3` and kube-proxy `v1.36.0-eksbuild.25`
    are created before the node group; coredns `v1.14.6-eksbuild.4` after it. These
    are the AWS default versions for 1.36 as of 2026-10-08.
  - The lock file has darwin_arm64 and linux_amd64 hashes.
- Expected plan: **16 to add.**
  - eks: role, attachment, cluster, SG rule, access entry, policy association, OIDC.
  - nodegroup: role, 3 attachments, launch template, node group.
  - 3 add-ons.

## Tested vs untested

**Tested:**
- Stack 01 apply, SSM session and Jenkins login.
- `fmt` and `validate` on all stacks.
- The managed policies and the EKS access policy referenced in the code exist.
- The add-on versions exist for 1.36 in ap-south-1.
- On 2026-10-08, the live Jenkins role was checked with `aws iam
  simulate-principal-policy`. The state bucket, EKS create/update/delete, SG rules,
  IAM under `dentsu-demo-*`, PassRole, OIDC, service-linked roles and ECR push were all
  allowed. Editing its own role, roles outside the prefix and other buckets were
  denied.

**Untested:**
- The stack 02 plan and apply.
- The IAM additions made after that simulation:
  - `iam:ListRoleTags`, `ListPolicyTags`, `ListOpenIDConnectProviderTags`.
  - `ec2:RunInstances`, `ModifyLaunchTemplate`, `DeleteLaunchTemplateVersions`.

  They are not live until 01-base is re-applied.
- Whether IMDS hop limit 1 on the nodes breaks anything. Nothing in this stack needs
  IMDS from a pod. The ALB controller in Phase 3 must be given `region` and `vpcId`
  explicitly, or it will try IMDS and fail.

## Known issues and risks

1. **01-base must be re-applied before 02.** The Jenkins role policy changed; the plan
   should show 1 in-place update. Without it, the node group fails because EKS requires
   the caller to have `ec2:RunInstances` when the launch template tags instances.
2. **Re-pushing a tag fails:** ECR tags are IMMUTABLE. The Phase 6 Jenkinsfile must skip
   the push when the tag already exists.
3. **Changing the Jenkins user data replaces the host,** and Jenkins configuration is
   lost.
4. **Privilege escalation is limited but possible.** The Jenkins role can create a
   broad `dentsu-demo-*` role, but it cannot create instance profiles or pass its own
   role, so `RunInstances` only reaches the node role. The production answer is a
   permissions boundary or a separate deploy role.
5. **A node group with 1/1/1 and `max_unavailable = 1`:** node updates take the only
   node down briefly. Acceptable for the demo.
6. **`bootstrap_self_managed_addons = false` is fixed at creation.** Changing it later
   replaces the cluster.
7. **Node.js is not on the host.** Phase 6 should run npm inside a `node` container.
8. **Cloning on the host:** the repo is private. Use the GitHub username and the
   fine-grained token as the password. Do not put the token in the clone URL.

## Key decisions and why

| Decision | Reason |
|---|---|
| Three stacks; 02 and 03 run from the Jenkins host | The private endpoint is only reachable inside the VPC, including for the Helm provider. |
| SSM Session Manager, no SSH, no inbound SG rules | No keys and no open ports; access is audited through IAM. |
| Single NAT, no VPC endpoints | Cost. The HA answer is one NAT per AZ plus interface endpoints. |
| /20 private subnets | The VPC CNI gives every pod a VPC IP. |
| IMMUTABLE ECR tags keyed by git SHA | Traceable deployments; rollback means redeploying an old SHA. |
| IMDSv2 with hop limit 1 (Jenkins host and nodes) | Containers and pods cannot read the instance role's credentials. Pods use IRSA. |
| IAM scoped by the `dentsu-demo-*` prefix, Deny on own role | Least privilege without listing every ARN in advance. |
| S3 native locking, state bucket `dentsu-demo-mumbai`, key `<stack>/terraform.tfstate` | No DynamoDB table; same region as the resources. |
| Checksum-verified, pinned tool downloads | Supply-chain hygiene. |
| Helm 3.22 on the host | Matches the Terraform Helm provider and the chart docs. |
| Admin through an explicit access entry, `bootstrap_cluster_creator_admin_permissions = false` | Visible and auditable in code. With `true`, EKS would create a hidden entry for the creator that conflicts with the declared one. |
| Only the Jenkins role is a cluster admin | The user chose to do all kubectl work from the Jenkins host. `additional_admin_principal_arns` exists for adding a console user later. |
| `bootstrap_self_managed_addons = false`, all three add-ons managed by EKS | Terraform owns the add-on versions. No unmanaged copies. |
| Add-on order: vpc-cni and kube-proxy, then nodes, then CoreDNS | Nodes need the CNI to be Ready; CoreDNS needs a node to run on. |
| Add-ons in the stack's `addons.tf`, not a module | Their order spans both modules. The one exception to "stacks only call modules". |
| Launch template for the nodes | The only way to tag node EC2 instances (Name, Env). Also gives an encrypted disk and IMDSv2. EKS requires the caller to have `ec2:RunInstances` for this. |
| CNI policy on the node role, not IRSA | Simpler for one node. The production answer is IRSA or Pod Identity for vpc-cni. |
| OIDC provider without a thumbprint | AWS verifies EKS issuers against its own CAs. Avoids the `tls` provider. |
| `upgrade_policy = STANDARD` | Avoids extended-support pricing ($0.60/hr instead of $0.10/hr). |

## Next steps

1. **Laptop:** commit and push. Then re-apply 01-base:
   `terraform plan -out tfplan`, expecting 1 in-place update of
   `module.jenkins_host.aws_iam_role_policy.terraform`; then `terraform apply tfplan`.
2. **Jenkins host (SSM shell):** `sudo su - ec2-user`, clone the repo, then:
   ```bash
   cd dentsu-demo/terraform/stacks/02-eks
   terraform init -backend-config=backend.hcl
   terraform plan -out tfplan    # expect 16 to add
   terraform apply tfplan        # about 15–20 minutes
   ```
3. **Phase 2 check:**
   ```bash
   $(terraform output -raw update_kubeconfig_command)
   kubectl get nodes               # 1 node Ready, v1.36.x
   kubectl get pods -n kube-system # aws-node, kube-proxy, 2 coredns Running
   ```
   Also confirm the node EC2 instance has the `Name` and `Env` tags.
4. **Next session, Phase 3:** the `alb-controller` module and the `03-addons` stack.
   - The official `iam_policy.json` for the pinned controller version.
   - An IRSA role scoped to `system:serviceaccount:kube-system:aws-load-balancer-controller`,
     using `oidc_provider_arn` and `oidc_issuer` from 02-eks.
   - `helm_release` with `clusterName`, `region`, `vpcId`, the role annotation and
     `replicaCount = 1`.
   - The Helm provider authenticates with `aws eks get-token` from the host.
