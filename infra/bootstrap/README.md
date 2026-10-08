# Bootstrap

Everything the lab and its CI need before the first deployment. It has its own lifecycle: it is
applied by hand, once, by someone with the Owner role on the project, and the lab never touches it.

| Resource | Purpose |
| --- | --- |
| State bucket `<project>-<prefix>-tfstate` | Remote state of the lab (prefix `lab`) and saved plans (`plans/`, deleted after 3 days). Private, versioned, uniform access, public access prevented |
| Workload identity pool and GitHub provider | Lets GitHub Actions exchange its short-lived OIDC token for Google credentials. Only tokens from `github_repository` are accepted |
| `<prefix>-ci-plan` service account | Plan jobs. Read only. Usable only by workflows running on `deploy_branch` |
| `<prefix>-ci-apply` service account | Apply and destroy jobs. Usable only by jobs of the `deploy_environment` GitHub environment, which requires an approval |

No key is created anywhere: there is no secret to store in GitHub.

## Who can do what

| Identity | Can be used by | Project roles | State bucket |
| --- | --- | --- | --- |
| `ci-plan` | `repo:<owner>/<repo>:ref:refs/heads/main` | `viewer`, `iam.securityReviewer` | `storage.objectAdmin` (state lock, saved plans) |
| `ci-apply` | `repo:<owner>/<repo>:environment:lab` | `browser`, `bigquery.admin`, `iam.serviceAccountAdmin`, `pubsub.admin`, `serviceusage.serviceUsageAdmin` | `storage.objectAdmin` |

The apply roles are project-wide: narrower than Owner or Editor, broader than a production
target would allow. Add a role to `apply_roles` when a new module needs one, for example
`roles/monitoring.editor` for alerts.

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
   entry of `terraform output github_variables`. Optionally add `TF_PRODUCER_IMPERSONATORS`, a JSON
   list such as `["user:first.last@example.com"]`.
2. **Settings, Environments, New environment `lab`**: add required reviewers (someone other than the
   author of the change) and restrict deployment branches to `main`.

Until `GCP_WIF_PROVIDER` exists, the CI only runs the validation job.

## 3. Use

- **Deploy**: merge into `main`. The workflow validates, plans with `ci-plan` and shows the plan in
  the run summary. A reviewer approves the `apply` job, which applies that exact plan with
  `ci-apply`, then runs `scripts/nominal-path-test.sh`.
- **Destroy**: Actions, Terraform destroy, Run workflow on `main`, type `destroy lab`. The destroy
  plan is shown, approved in `lab`, applied, then `scripts/inventory.sh` lists what remains.
- **Locally**: `cd infra/envs/lab && terraform init -backend-config="bucket=<state_bucket>"`.

## Good to know

- Deleting a workload identity pool keeps its id reserved for 30 days: re-creating it with the same
  prefix fails during that time.
- The repository name in `github_repository` is case-sensitive.
- The repository is public: workflow logs and the plan shown in the run summary are public. Plan
  files themselves stay in the private bucket. The configuration holds no secret values.
