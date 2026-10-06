# Progress

Last updated: 2026-10-04 (end of the Phase 1 session).

## Phase status

| Phase | Scope | Status |
|---|---|---|
| 0 | AWS account, billing alarm, laptop tools, GitHub repo, state bucket, CLAUDE.md | **User owns.** CLAUDE.md is done. Other items not confirmed. |
| 1 | Stack 01-base: vpc, ecr and jenkins-host modules | **Code written, not applied** |
| 2 | Stack 02-eks: eks and nodegroup modules | Not started |
| 3 | Stack 03-addons: alb-controller module | Not started |
| 4 | Express app and Dockerfile | Not started |
| 5 | k8s manifests, deployed by hand | Not started |
| 6 | Jenkinsfile and Jenkins setup | Not started |
| 7 | README, teardown, rehearsal | README has the 01-base section only |

## What exists

- `terraform/modules/vpc`: VPC (10.0.0.0/16, DNS on), IGW, public subnets
  10.0.0.0/24 and 10.0.1.0/24 tagged `kubernetes.io/role/elb=1`, private subnets
  10.0.16.0/20 and 10.0.32.0/20 tagged `kubernetes.io/role/internal-elb=1`, one EIP
  with a NAT gateway in public[0], and public and private route tables.
  The `private_subnet_ids` output has `depends_on` on the NAT route, so consumers
  wait until the subnets have egress.
- `terraform/modules/ecr`: repository `dentsu-demo-app`. IMMUTABLE tags, scan on push,
  AES256 encryption, `force_delete = true`, lifecycle rule that keeps the last 10 images.
- `terraform/modules/jenkins-host`: the host instance.
  - Instance: AL2023 (from the SSM parameter, `ignore_changes = [ami]`), t3.medium in
    private[0], no public IP, no key pair, IMDSv2 with hop limit 1, 30 GB gp3
    encrypted disk, `user_data_replace_on_change = true`.
  - Security group: no inbound rules, all outbound.
  - Role `dentsu-demo-jenkins` has three parts:
    - `AmazonSSMManagedInstanceCore`.
    - Inline `ecr-push`, scoped to the repo.
    - Inline `terraform-stacks-02-03`: state bucket R/W, `eks:*`, EC2 SG/LT/describe,
      IAM role and policy management under `dentsu-demo-*`, OIDC providers for
      `oidc.eks.ap-south-1.amazonaws.com/*`, service-linked roles for eks,
      eks-nodegroup and autoscaling, the SSM `/aws/service/eks/*` parameters,
      CloudWatch log groups `/aws/eks/dentsu-demo-*`, and an explicit Deny of `iam:*`
      on its own role.
  - User data (`templates/user-data.sh.tftpl`) installs Java 21 Corretto, Jenkins LTS
    (official repo), Docker, Git, jq, unzip, kubectl 1.36.5, Helm 3.22.0 and Terraform
    1.16.4, with checksums verified. It also adds `jenkins` to the `docker` group.
    Log: `/var/log/user-data.log`. Completion marker: `/var/log/user-data.done`.
- `terraform/stacks/01-base`: wires the three modules together.
  - Outputs: vpc/subnet IDs, ECR URL, Jenkins instance ID, SG ID, role ARN, and the
    SSM shell and port-forward commands.
  - `backend.hcl` and `terraform.tfvars` hold the placeholder
    `REPLACE_WITH_STATE_BUCKET`. A variable validation rejects the placeholder.
- Empty placeholder dirs (`.gitkeep`): modules eks, nodegroup, alb-controller; stacks
  02-eks, 03-addons; app; k8s.
- `.gitignore`: covers Terraform state, plans, `.terraform/` and `node_modules`.
  `.terraform.lock.hcl` **is committed**.

## Tested vs untested

**Tested (static only):**
- `terraform fmt -recursive -check` is clean.
- `terraform validate` passes on 01-base (run with `init -backend=false`).
- The rendered user-data script passes `bash -n`.
- All pinned download URLs return 200: kubectl `.sha256`, Helm `.sha256sum`,
  Terraform `SHA256SUMS`, the Jenkins repo file.

**Untested (nothing has been applied):**
- `terraform plan` and `apply` against AWS.
- User data running on a real AL2023 instance: package names, the Jenkins repo GPG
  key import, service start.
- SSM session and port-forward to 8080, and Jenkins login.
- Whether the `terraform-stacks-02-03` IAM policy is enough for stacks 02 and 03.
  It was written from knowledge, not verified. Expect to add missing actions when
  02 and 03 first run.

## Known issues and risks

1. **Placeholders:** the state bucket name must be set in `01-base/backend.hcl` and
   `terraform.tfvars`.
2. **AWS CLI is missing on the laptop** (`aws not found` at the time of writing).
   It is needed for the SSM check.
3. **Re-pushing a tag fails:** ECR tags are IMMUTABLE, so pushing the same git-SHA tag
   twice fails. The Phase 6 Jenkinsfile must skip the push when the tag exists, or
   fail clearly.
4. **Changing user data replaces the host,** because `user_data_replace_on_change` is
   on. Jenkins configuration (jobs, plugins, credentials) is lost.
5. **Privilege escalation is possible:** the host role can create a `dentsu-demo-*`
   role with broad permissions. Accepted for the demo. The production answer is a
   permissions boundary or a separate deploy role or account.
6. **Lock file covers one platform:** `01-base/.terraform.lock.hcl` has darwin_arm64
   hashes only. That is fine because 01 runs only from the laptop. For the 02/03
   stacks, run `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`,
   or let the host create the lock file and commit it.
7. **Node.js is not on the host.** Phase 6 should run `npm ci` and `npm test` inside a
   `node` container, not install Node on the host.
8. **Nothing is committed to git yet.**

## Key decisions and why

| Decision | Reason |
|---|---|
| Three stacks, 02 and 03 run from the Jenkins host | The private endpoint is only reachable from inside the VPC, including for the Helm provider. |
| SSM Session Manager, no SSH, no inbound SG rules | No keys and no open ports. Access is audited through IAM. |
| Single NAT, no VPC endpoints | Cost. The HA answer is one NAT per AZ plus interface endpoints. |
| /20 private subnets | The VPC CNI assigns a VPC IP to every pod. |
| `internal-elb` tag on private subnets | Lets internal ALBs work later at no cost. |
| No `kubernetes.io/cluster/<name>` subnet tag | The LBC no longer needs it for subnet discovery. |
| IMMUTABLE ECR tags, keyed by git SHA | Every deployment is traceable, and rollback means redeploying an old SHA. |
| IMDSv2, hop limit 1 | Build containers cannot steal the host's instance-profile credentials. |
| IAM scoped by the `dentsu-demo-*` name prefix, Deny on own role | Least privilege without listing every role ARN in advance. |
| Inline policies on the Jenkins role | They live and die with the role, and fit the size limit. |
| AMI from SSM, `ignore_changes = [ami]` | Always launches the latest AL2023, but a new AMI does not replace a running host. |
| S3 native locking (`use_lockfile`) | No DynamoDB table needed (Terraform ≥ 1.10). |
| State bucket `dentsu-demo-mumbai` in ap-south-1, key `<stack>/terraform.tfstate` | Same region as the resources. One bucket for all three stacks. Created by hand, with versioning on and public access blocked. |
| Checksum-verified tool downloads | Supply-chain hygiene, and exact pinned versions. |
| Helm 3.22 (not 4.x) on the host | Matches what the Terraform Helm provider uses, and the chart docs assume v3. |

## Next steps

1. **User:** finish Phase 0. Install the AWS CLI v2 and the Session Manager plugin,
   create the state bucket in ap-south-1 (versioning on, public access blocked), set
   the billing alarm, push the repo to GitHub.
2. **User:** put the bucket name in `terraform/stacks/01-base/backend.hcl` and
   `terraform.tfvars`.
3. **User:** `terraform init -backend-config=backend.hcl`, `terraform plan -out tfplan`,
   review the plan (26 resources to add: 16 vpc, 2 ecr, 8 jenkins-host), `terraform apply tfplan`.
4. **Phase 1 check:** after about 5 minutes, open an SSM shell, confirm
   `/var/log/user-data.done` exists, read the initial admin password, port-forward
   8080, and log in to Jenkins. Fix user data if anything failed. The log is at
   `/var/log/user-data.log`.
5. **Next session, Phase 2:** plan, then write the `eks` and `nodegroup` modules and
   the `02-eks` stack.
   - EKS 1.36, private endpoint only, `authentication_mode = "API"`.
   - Cluster and node roles named `dentsu-demo-*`.
   - SG rule allowing 443 from the Jenkins SG to the cluster SG.
   - Access entry plus `AmazonEKSClusterAdminPolicy` for the Jenkins role. Or rely on
     `bootstrap_cluster_creator_admin_permissions`, since the host creates the cluster.
     Pick one.
   - OIDC provider.
   - Add-ons vpc-cni, kube-proxy and coredns, with coredns depending on the node group.
   - Remote state from `01-base`.
   - Its own `backend.hcl`.
