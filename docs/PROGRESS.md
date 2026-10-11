# Progress

Last updated: 2026-10-11 (Phase 3 applied and verified).

## Phase status

| Phase | Scope | Status |
|---|---|---|
| 0 | AWS account, billing alarm, laptop tools, GitHub repo, state bucket, CLAUDE.md | Done by the user. **Public** repo `santoshteli/dentsu-demo` (recreated on 2026-10-11 to drop a commit that contained a plan file; secret scanning and push protection on); state bucket `dentsu-demo-mumbai` (ap-south-1). |
| 1 | Stack 01-base: vpc, ecr and jenkins-host modules | **Applied and checked.** Jenkins host is Online in SSM; the user confirmed the Jenkins login. **Needs a re-apply** for the Jenkins IAM policy changes listed below. |
| 2 | Stack 02-eks: eks and nodegroup modules | **Applied through `Jenkinsfile.infra` and verified (2026-10-11).** 1 node Ready on v1.36.4-eks; vpc-cni, kube-proxy and coredns installed; endpoint private only; node instance tagged Name and Env, IMDS hop limit 1. |
| 3 | Stack 03-addons: alb-controller module | **Applied through `Jenkinsfile.infra` and verified (2026-10-11).** Deployment 1/1; Helm release deployed (chart 3.6.0); IngressClass `alb`; pod has `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` (IRSA); 0 permission errors in the logs. |
| 4 | Express app and Dockerfile | **Done and checked (2026-10-11)** in the separate repo **dentsu-demo-app** (public). Tests pass; image builds, runs as non-root, `/health` and `/users` return 200, SIGTERM exits 0. |
| 5 | k8s manifests, deployed by hand | Not started. Manifests go in dentsu-demo-app `k8s/`. |
| 6 | Jenkinsfile and Jenkins setup | App pipeline not started. Jenkins on the rebuilt host is set up (wizard done, suggested plugins). **`Jenkinsfile.infra` written, not yet run.** |
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
- **Jenkins ALB (applied and tested 2026-10-11:** target healthy, HTTP 200 from the
  user's IP after adding a console rule) in `modules/jenkins-host/alb.tf`,
  switched on by `enable_jenkins_alb` (default true):
  - Internet-facing ALB `dentsu-demo-jenkins-alb` in the public subnets, HTTP :80 to a
    target group on the host's port 8080 (health check `/login`).
  - ALB security group `dentsu-demo-jenkins-alb`: **no inbound rule by default**. Add
    HTTP from "My IP" in the console when needed; `jenkins_alb_allowed_cidrs` exists but
    stays empty in git. Egress only to the Jenkins SG on 8080.
  - The host SG gains one rule: 8080 from the ALB SG. The host stays in the private
    subnet with no public IP and is not replaced.
  - Outputs `jenkins_url` and `jenkins_alb_security_group_id`. Expected plan: 7 to add.
  - Reason: the demo runs on a Dentsu Windows machine with only a browser, so no
    AWS CLI or SSM port-forward. The shell comes from the console's Session Manager.

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

### Stack 03-addons (applied and verified)

- `modules/alb-controller`:
  - `iam-policy-v3.6.0.json`: the official policy from the v3.6.0 tag, byte-identical
    (sha256 16f232c9…). The file name carries the version; `controller_version` picks it,
    so a version bump without a new policy file fails at plan time.
  - `aws_iam_policy` and `aws_iam_role` `dentsu-demo-alb-controller`. IRSA trust:
    `sts:AssumeRoleWithWebIdentity` from the cluster OIDC provider, conditions `sub` =
    `system:serviceaccount:kube-system:aws-load-balancer-controller` and `aud` =
    `sts.amazonaws.com`.
  - `helm_release` `aws-load-balancer-controller`, chart 3.6.0 from
    `https://aws.github.io/eks-charts`, in kube-system, `wait = true`. Values:
    clusterName, region, vpcId, replicaCount 1, service account (named, with the role
    annotation), `defaultTags` (Env, Project, ManagedBy) for the ALBs it creates,
    `enableServiceMutatorWebhook = false`.
- `stacks/03-addons`: AWS 6.67.0 and Helm 3.3.0 providers (lock file for darwin_arm64
  and linux_amd64). The Helm provider uses the 02-eks endpoint and CA and
  `aws eks get-token`, so it must run on the Jenkins host. Reads 01-base (vpc_id) and
  02-eks (cluster, OIDC) from remote state.
- Expected plan: **4 to add.**
- `Jenkinsfile.infra` 03 verify stage now fails on AccessDenied, UnauthorizedOperation or
  WebIdentityErr in the controller logs, and prints the deployment and IngressClass.

### Application repo: dentsu-demo-app (Phase 4)

- Separate public repo `santoshteli/dentsu-demo-app`, local folder `../dentsu-demo-app`.
  `sample-app-1` was reviewed and not reused (plain http on localhost, Node 18, no
  lock file, root user, a GitHub Actions workflow pushing to Docker Hub and an Argo CD
  repo, noisy history).
- Express 5.3.0 (exact); `src/app.js` exports `createApp()`; `src/server.js` listens on
  `0.0.0.0:3000` (PORT and HOST overridable) and closes cleanly on SIGTERM/SIGINT.
- `GET /health` returns `{"status":"ok"}`; `GET /users` returns 3 static users.
- Tests: built-in `node:test` (`npm test` = `node --test "test/**/*.test.js"`; a bare
  directory argument does not work in Node 24). 3 tests: /health, /users, 404.
- Dockerfile on `node:24.21.0-alpine3.24`: build stage runs `npm ci` and `npm test`;
  runtime stage `npm ci --omit=dev`, `NODE_ENV=production`, `USER node`, `EXPOSE 3000`.
  Image about 63 MB.
- The laptop builds arm64 images. EKS nodes are x86_64, so images for the cluster must
  be built on the Jenkins host (x86_64) or with `--platform linux/amd64`.
- The laptop's Docker uses the legacy builder (no buildx); fine for local checks.

### Infra pipeline

- `Jenkinsfile.infra`, used by a Jenkins Pipeline job `dentsu-infra` that reads it from SCM.
- Parameters: `ACTION` (plan, apply, destroy; plan is the default) and `STACK`
  (02-eks, 03-addons, all). `all` applies 02 then 03, and destroys 03 then 02.
- Per stack: init and validate, plan (`-detailed-exitcode`, saved as a build
  artifact), manual approval showing the plan summary, apply of the saved plan, then
  verify (nodes Ready for 02, controller rollout for 03).
- Before destroying 03, it deletes all Ingresses and waits, so the controller removes
  the ALBs. Before destroying 02, it refuses if the controller is still installed.
- No triggers; one build at a time; 30-minute approval timeout; 45-minute apply
  timeout; plan files are deleted after each build. It runs as the `jenkins` user with
  the instance role, so no stored keys.
- 01-base is never run here, because it contains the Jenkins host.

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

- `Jenkinsfile.infra` runs: plan-only build and approval gate work (2026-10-11).
- First 02 apply through the pipeline (2026-10-11): cluster ACTIVE in 8m52s; OIDC,
  access entry, 443 rule, vpc-cni and kube-proxy created. **The node group failed:**
  EKS calls `iam:GetRole` on `AWSServiceRoleForAmazonEKSNodegroup`, and while that
  role does not exist IAM checks the ARN *without* the `aws-service-role/` path. The
  simulator confirmed `role/AWSServiceRoleFor...` was denied and the path form was
  allowed. Fix: add `role/AWSServiceRoleFor*` to `IamReadServiceLinkedRoles`
  (01-base re-apply needed). No node group was created, so re-running apply 02 should
  plan only the node group and CoreDNS.

- Re-run after the fix: node group and CoreDNS created; `kubectl get nodes` from the host
  shows 1 node Ready. kubectl in a shell needs `aws eks update-kubeconfig` per Linux user;
  without it kubectl falls back to localhost:8080, which is Jenkins.

**Untested:**
- Destroying 02-eks through the pipeline, and a timed rebuild.
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
8. **Never commit plan or state files.** `.gitignore` covers `tfplan*`, `*.tfplan` and
   `*.tfstate*`. A plan file was committed once and removed by recreating the repo.

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
| Infra pipeline for 02 and 03 only, with an approval gate | Repeatable destroy and rebuild for rehearsals, and a demo of IaC through CI. 01-base stays on the laptop because the pipeline runs on the host it creates. |
| Jenkins behind its own ALB, not a public IP on the host | Browser-only demo machine. Host stays private and is not rebuilt. Plain HTTP (no domain), limited to the client IP added in the console. |
| Separate ALBs for Jenkins and the app | Jenkins must be reachable before the cluster and controller exist, and during teardown after Ingresses are deleted. The app ALB is created by the controller from the Ingress, as the assignment requires. |
| Load Balancer Controller v3.6.0 | Latest; same IAM policy as v3.5.0; fixes an SG reconciliation bug for ALB Ingresses. Gateway API "action required" notes don't apply (Ingress only). |
| Official IAM policy committed to the repo | Reviewable and fixed to the pinned version, as the assignment asks. Not downloaded at plan time. |
| `enableServiceMutatorWebhook = false` | The webhook sees every Service creation with failurePolicy Fail; with 1 replica a controller restart would block even ClusterIP Services. Only Ingress is used. |
| region and vpcId passed to the chart | Required by the assignment, and needed because node IMDS hop limit 1 hides instance metadata from pods. |
| Separate app repo dentsu-demo-app | Platform and app have different lifecycles and owners; app commits only trigger the app pipeline. The infra README maps every deliverable to its repo, because the assignment says "repo". |
| `upgrade_policy = STANDARD` | Avoids extended-support pricing ($0.60/hr instead of $0.10/hr). |

## Next steps

1. **Laptop:** commit and push. Then re-apply 01-base:
   `terraform plan -out tfplan`, expecting 1 in-place update of
   `module.jenkins_host.aws_iam_role_policy.terraform`; then `terraform apply tfplan`.
2. **Jenkins host (SSM shell):** `sudo su - ec2-user`, clone the repo (public, no token needed), then:
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
