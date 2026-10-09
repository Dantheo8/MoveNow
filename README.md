# MoveNow, group 3

A lab pipeline for vehicle positions on Google Cloud. Vehicles publish positions to Pub/Sub. A
BigQuery subscription writes them to a partitioned table. Messages that keep failing go to a
dead-letter topic, where they wait to be fixed and replayed. Terraform deploys everything, through
a GitHub Actions pipeline with an approval before each apply.

## Repository

| Path | Content |
| --- | --- |
| `movenow/` | The course kit: position producer and dashboard (not graded) |
| `infra/bootstrap/` | Applied once by hand: state bucket, CI identities, producer identity |
| `infra/envs/lab/` | The deployed environment: assembles the modules below |
| `infra/modules/` | `messaging`, `delivery`, `analytics`, `observability` |
| `infra/schemas/positions.json` | Table schema, which is also the message contract |
| `scripts/` | Validation, nominal path test, inventory after destroy, demo scripts |
| `.github/workflows/` | CI: validate, plan, approve, apply and test; manual destroy |
| `docs/` | [Architecture and choices](docs/architecture.md), [runbook](docs/runbook.md) |

## Deploy

1. **Bootstrap**, once, with the Owner role on the project: see
   [infra/bootstrap/README.md](infra/bootstrap/README.md).
2. **GitHub setup**, by the repository owner: the Actions variables printed by the bootstrap, and
   an environment `lab` with required reviewers, limited to `main`.
3. **Merge into `main`.** The pipeline validates, plans, waits for an approval, applies the
   reviewed plan, then checks that a test batch reaches BigQuery.

Pull requests and pushes to `dev` only run the validation, without cloud access. Before pushing,
run `./scripts/terraform-validate.sh`.

## Destroy

1. Actions → **Terraform destroy** → run on `main` → approve. The job then lists what remains.
2. At the very end of the course, destroy the bootstrap by hand (`terraform destroy` in
   `infra/bootstrap`, after emptying the state bucket).
