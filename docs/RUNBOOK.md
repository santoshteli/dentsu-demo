# Runbook: create, verify and tear down the environment

Short, browser-only steps: everything below works from a machine with just a web browser (AWS Console, Session Manager, Jenkins, GitHub). No AWS CLI, Terraform or SSH is needed on that machine. Steps marked **(laptop)** use a laptop with the AWS CLI and this repo.

Starting point: stack `01-base` is applied (VPC, NAT, ECR, Jenkins host and its ALB), and no EKS cluster exists. See the [README](../README.md) for the first-time setup.

## Keep handy

| Item | Value |
|---|---|
| Region | Asia Pacific (Mumbai) `ap-south-1` |
| Jenkins URL | AWS Console → EC2 → Load Balancers → `dentsu-demo-jenkins-alb` → DNS name, opened with `http://` (laptop: `terraform output -raw jenkins_url` in `terraform/stacks/01-base`) |
| Security group to open for Jenkins | `dentsu-demo-jenkins-alb` |
| Jenkins host (EC2 instance name) | `dentsu-demo-jenkins` |
| Jenkins jobs | `dentsu-infra` (cluster), `dentsu-app` (application) |
| Repositories | [dentsu-demo](https://github.com/santoshteli/dentsu-demo), [dentsu-demo-app](https://github.com/santoshteli/dentsu-demo-app) |

You need your AWS Console login (with MFA) and your GitHub login (for the code change in step 8).

## Before you start (laptop)

0. If the Jenkins host is stopped, start it **at least 15 minutes before** you need Jenkins, and wait for **Online**:

   ```bash
   cd terraform/stacks/01-base
   aws ec2 start-instances --region ap-south-1 --instance-ids $(terraform output -raw jenkins_instance_id)
   aws ssm describe-instance-information --region ap-south-1 --filters Key=InstanceIds,Values=$(terraform output -raw jenkins_instance_id) --query 'InstanceInformationList[0].PingStatus' --output text
   ```

1. No cluster exists (empty output). If one exists, run the teardown at the end of this document.

   ```bash
   aws eks list-clusters --region ap-south-1 --output text
   ```

2. In Jenkins, **Manage Jenkins → System → Jenkins URL** is the Jenkins ALB URL. If it says `localhost:8080`, the approval buttons do nothing.
3. `dentsu-demo-jenkins-alb` has no leftover inbound rules.
4. Do not push to the application repo while the cluster is down: the app pipeline would start and fail at "Deploy to EKS".

## 1. Sign in

- Open a **private browser window**.
- Sign in to the AWS Console with MFA, and switch the region to **ap-south-1**.

## 2. Open Jenkins

- **EC2 → Security Groups → `dentsu-demo-jenkins-alb` → Edit inbound rules → Add rule**
- Type **HTTP**, Source **My IP** → **Save rules**.
- Open the Jenkins URL and log in.

## 3. Open a shell on the Jenkins host

- **EC2 → Instances → `dentsu-demo-jenkins` → Connect → Session Manager → Connect**

```bash
sudo su - ec2-user
```

## 4. Create the cluster and the Load Balancer Controller

**`dentsu-infra` → Build with Parameters → ACTION = `apply`, STACK = `all` → Build.**

- First approval: **"APPLY 02-eks? Plan: 16 to add, 0 to change, 0 to destroy."** → **Yes, apply 02-eks**.
  - About 15 minutes. The verify stage prints the node as **Ready**.
- Second approval: **"APPLY 03-addons? Plan: 4 to add, 0 to change, 0 to destroy."** → **Yes, apply 03-addons**.
  - About 2 minutes. The verify stage prints the controller as **1/1**, with no permission errors.
- Optional: open the build artifacts **plan-02-eks.txt** and **plan-03-addons.txt** to show the reviewed plans.

## 5. Check the cluster

The cluster is new, so refresh kubeconfig first:

```bash
aws eks update-kubeconfig --region ap-south-1 --name dentsu-demo
kubectl get nodes
kubectl -n kube-system get deploy aws-load-balancer-controller
kubectl get ingressclass
```

- Expect 1 node **Ready**, the controller **1/1**, and an IngressClass **alb**.

The API endpoint is private:

```bash
aws eks describe-cluster --name dentsu-demo --region ap-south-1 --query 'cluster.resourcesVpcConfig.[endpointPrivateAccess,endpointPublicAccess]' --output text
```

- Expect **True False**.

## 6. Deploy the application

**`dentsu-app` → Build Now.** (This job has no parameters.)

- Stages: Checkout, npm ci and test, Docker build, Push to ECR, Deploy to EKS, Rollout status, ALB URL.
- "Push to ECR" may report that the image is already in ECR: tags are immutable, so an unchanged commit is not pushed twice.
- About 5 minutes. A new ALB takes 2 to 3 minutes to get an address.
- The end of the console output shows **Application URL: http://…/users**.

## 7. Open the application

- Open the Application URL from step 6: **/users** and **/health**.
- In the shell:

```bash
kubectl -n dentsu-demo-app get deploy,pods,svc,ingress
```

- Expect 2 pods **Running** with **READINESS GATES 1/1**, and the ALB hostname on the Ingress.

## 8. Code change through CI/CD

In the application repository on GitHub:

1. Open **src/app.js** → pencil icon (**Edit**).
2. Change one name, for example `'Vikram Shah'` to `'Vikram Shah - Demo'`.
3. **Commit changes** directly to **main**.

Then do not click anything in Jenkins:

- Within about 2 minutes, `dentsu-app` starts a build marked **"Started by an SCM change"**.
- It pushes a new image tag (the new commit SHA) and rolls it out with no downtime.
- Refresh **/users**: the new name appears.

## 9. Roll back (optional)

```bash
kubectl -n dentsu-demo-app rollout undo deployment/dentsu-demo-app
kubectl -n dentsu-demo-app rollout status deployment/dentsu-demo-app
```

- Refresh **/users**: the previous name is back.
- The permanent way: revert the commit on GitHub; the pipeline redeploys.

## 10. Finish

1. Delete the **My IP** rule from `dentsu-demo-jenkins-alb`.
2. Sign out of Jenkins, GitHub and the AWS Console, and close the private window.
3. Later (laptop): change the Jenkins admin password, and run the teardown below.

## Teardown (cluster, controller and application ALB)

**`dentsu-infra` → ACTION = `destroy`, STACK = `all`.** It removes `03-addons` first, then `02-eks`.

- First approval: **"DESTROY 03-addons? … 4 to destroy."** After approval it deletes the application's Ingress and waits until its ALB is gone, then removes the controller (about 2 minutes).
- Second approval: **"DESTROY 02-eks? … 16 to destroy."** (about 10 to 15 minutes)

Check (laptop):

```bash
aws eks list-clusters --region ap-south-1 --output text
aws elbv2 describe-load-balancers --region ap-south-1 --query 'LoadBalancers[].LoadBalancerName' --output text
```

- Expect no cluster, and only `dentsu-demo-jenkins-alb` left.
- Stack `01-base`, ECR and its images stay (about $0.14 per hour).
- Optional: stop the Jenkins host until next time. Its Jenkins configuration is kept.

  ```bash
  cd terraform/stacks/01-base
  aws ec2 stop-instances --region ap-south-1 --instance-ids $(terraform output -raw jenkins_instance_id)
  ```

## If something goes wrong

| Problem | Fix |
|---|---|
| Jenkins URL does not load | Add the **My IP** rule again; the machine's public IP may have changed. |
| Approval button does nothing | Set **Manage Jenkins → System → Jenkins URL** to the Jenkins ALB URL, refresh the build page, and approve again. Or use **Paused for Input** in the build's left menu. |
| kubectl prints a Jenkins login page, or times out | Run `aws eks update-kubeconfig --region ap-south-1 --name dentsu-demo` again. |
| `dentsu-app` fails: "Cluster dentsu-demo not found" | Run step 4 first. |
| `dentsu-app` does not start after a commit | Click **Build Now** once. |
| ALB URL stage is UNSTABLE (no answer yet) | A new ALB's DNS can take a few more minutes. Wait, then refresh the URL. |
| The 03-addons verify stage reports permission errors | `kubectl -n kube-system logs deploy/aws-load-balancer-controller`, and look for the AWS action that was denied. |
| A build fails | Open the last successful build of that job and review its stages, then fix and re-run. |
