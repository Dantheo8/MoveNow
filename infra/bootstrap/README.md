# Bootstrap

Everything the lab and its CI need before the first deployment. It has its own lifecycle: it is
applied by hand, once, by someone with the Owner role on the project, and the lab never touches it.

| Resource | Purpose |
| --- | --- |
| State bucket `<project>-<prefix>-tfstate` | Remote state of the lab (prefix `lab`) and saved plans (`plans/`, deleted after 3 days). Private, versioned, uniform access, public access prevented |
| Workload identity pool and GitHub provider | Lets GitHub Actions exchange its short-lived OIDC token for Google credentials. Only tokens carrying the repository's and owner's numeric ids, issued for `deploy_branch`, are accepted |
| `<prefix>-ci-plan` service account | Plan jobs. Reads the project and the state; can only add new objects under `plans/` |
| `<prefix>-ci-apply` service account | Apply and destroy jobs. Usable only by jobs of the `deploy_environment` GitHub environment, which requires an approval |
| `<prefix>-producer` service account | Identity the producer runs as. The lab grants it publish rights on the positions topic; `producer_impersonators` may act as it |

No key is created anywhere: there is no secret to store in GitHub.

## Who can do what

| Identity | Can be used by | Project roles | State bucket |
| --- | --- | --- | --- |
| `ci-plan` | `repo:<owner>/<repo>:ref:refs/heads/main` | `viewer`, `iam.securityReviewer` | `storage.objectViewer`, and `storage.objectCreator` on `plans/` only: it cannot change the state or replace a saved plan |
| `ci-apply` | `repo:<owner>/<repo>:environment:lab` | `browser`, `bigquery.admin`, `monitoring.editor`, `pubsub.admin`, `serviceusage.serviceUsageAdmin` | `storage.objectAdmin` |

Why it is built this way:

- **Immutable ids.** The trust condition checks `repository_id` and `repository_owner_id`, not names:
  if the repository were deleted or renamed, someone recreating the same name would get other ids.
  It also requires the token to come from `deploy_branch`, so a job on another branch cannot use
  the `lab` environment to obtain the apply identity.
- **No escalation.** The apply identity has no role able to change service account policies, so
  it cannot grant itself access to another identity. That is why the bootstrap, run by an Owner,
  creates the producer identity and its impersonation rights.
- **A reviewed plan stays the reviewed plan.** The plan identity cannot write the state or
  overwrite an object: plans run without the state lock, and each saved plan is a new object whose
  sha256 is shown in the run summary and checked by the apply job before applying.

The apply roles are project-wide on Pub/Sub, BigQuery, Monitoring and APIs: narrower than Owner or
Editor, broader than a production target would allow. Add a role to `apply_roles` when a new module
needs one.

## 1. Apply

```sh
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars    # fill it in; ignored by Git
gcloud auth application-default login
terraform init
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output github_variables
```

The state of the bootstrap is local (`terraform.tfstate`, ignored by Git). Once the bucket exists,
move it there so it is not lost: add the block below inside `terraform { }` in `versions.tf`, then
run `terraform init -migrate-state`.

```hcl
backend "gcs" {
  bucket = "<state_bucket output>"
  prefix = "bootstrap"
}
```

## 2. Configure GitHub (repository admin)

1. **Settings, Secrets and variables, Actions, Variables**: create one repository variable per
   entry of `terraform output github_variables`.
2. **Settings, Environments, New environment `lab`**: add required reviewers (someone other than the
   author of the change) and restrict deployment branches to `main`.

Until `GCP_WIF_PROVIDER` exists, the CI only runs the validation job.

## 3. Use

- **Deploy**: merge into `main`. The workflow validates, plans with `ci-plan` and shows the plan in
  the run summary. A reviewer approves the `apply` job, which applies that exact plan with
  `ci-apply`, then runs `scripts/nominal-path-test.sh`.
- **Destroy**: Actions, Terraform destroy, Run workflow on `main`, then approve it in `lab`. The
  job destroys the lab with `ci-apply`, then `scripts/inventory.sh` lists what remains.
  The bootstrap's resources, including the producer identity, are kept on purpose.
- **Locally**: `cd infra/envs/lab && terraform init -backend-config="bucket=<state_bucket>"`.

## Good to know

- Deleting a workload identity pool keeps its id reserved for 30 days: re-creating it with the same
  prefix fails during that time.
- `github_repository` is case-sensitive; get the two ids with
  `gh api repos/OWNER/NAME --jq '.id, .owner.id'`.
- To let someone run the producer as its identity, add them to `producer_impersonators` and
  re-apply the bootstrap.
- The repository is public: workflow logs and the plan shown in the run summary are public. Plan
  files themselves stay in the private bucket. The configuration holds no secret values.
