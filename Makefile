PROJECT         ?= groupe3inssettp
REGION          ?= europe-west9
PREFIX          ?= g3-movenow
DATASET         ?= movenow
TF_STATE_BUCKET ?= bucket-gcs-movenow

TOPIC        := $(PREFIX)-positions
SUBSCRIPTION := $(PREFIX)-positions-bq
INSPECTION   := $(PREFIX)-positions-dead-letter-inspection
TABLE        := $(PROJECT).$(DATASET).positions
LAB          := infra/envs/lab
BOOTSTRAP    := infra/bootstrap

.DEFAULT_GOAL := help
.PHONY: help validate fmt bootstrap-plan bootstrap-apply github-vars init plan apply destroy outputs \
	test state dead-letters duplicates inventory kit-local kit-demo dashboard

help:
	@echo "Usage: make <command> [PROJECT=... REGION=... PREFIX=... DATASET=... TF_STATE_BUCKET=...]"
	@echo ""
	@echo "Code"
	@echo "  validate         Check formatting and validate every Terraform folder, like the CI"
	@echo "  fmt              Format the Terraform code"
	@echo ""
	@echo "Bootstrap (once, Owner role)"
	@echo "  bootstrap-plan   Init the bootstrap and save a plan"
	@echo "  bootstrap-apply  Apply the saved bootstrap plan"
	@echo "  github-vars      Print the variables to create in GitHub"
	@echo ""
	@echo "Lab"
	@echo "  init             Init the lab with the remote state"
	@echo "  plan             Show what would change (deploy through the CI)"
	@echo "  apply            Apply locally, asks for confirmation (prefer the CI)"
	@echo "  destroy          Destroy locally, asks for confirmation (prefer the destroy workflow)"
	@echo "  outputs          Show the lab outputs"
	@echo ""
	@echo "Checks on the deployed lab"
	@echo "  test             Nominal path: 10 positions must reach BigQuery"
	@echo "  state            State of the BigQuery subscription (ACTIVE when it can write)"
	@echo "  dead-letters     Show failed messages without removing them"
	@echo "  duplicates       event_ids written more than once in the last day"
	@echo "  inventory        After a destroy: list what remains"
	@echo ""
	@echo "Kit (http://localhost:8080)"
	@echo "  kit-local        Kit with the Pub/Sub emulator, needs Docker"
	@echo "  kit-demo         Kit dashboard in memory, no Docker, no GCP"
	@echo "  dashboard        Kit dashboard reading the real BigQuery table"
	@echo ""
	@echo "Current values: PROJECT=$(PROJECT) REGION=$(REGION) PREFIX=$(PREFIX) DATASET=$(DATASET) TF_STATE_BUCKET=$(TF_STATE_BUCKET)"

validate:
	./scripts/terraform-validate.sh

fmt:
	terraform fmt -recursive infra

bootstrap-plan:
	cd $(BOOTSTRAP) && terraform init && terraform plan -out=bootstrap.tfplan

bootstrap-apply:
	cd $(BOOTSTRAP) && terraform apply bootstrap.tfplan

github-vars:
	cd $(BOOTSTRAP) && terraform output github_variables

init:
	cd $(LAB) && terraform init -backend-config="bucket=$(TF_STATE_BUCKET)"

plan:
	cd $(LAB) && terraform plan

apply:
	cd $(LAB) && terraform apply

destroy:
	cd $(LAB) && terraform destroy

outputs:
	cd $(LAB) && terraform output

test:
	./scripts/nominal-path-test.sh $(PROJECT) $(TOPIC) $(TABLE) $(REGION)

state:
	gcloud pubsub subscriptions describe $(SUBSCRIPTION) --project=$(PROJECT) --format='value(state)'

dead-letters:
	gcloud pubsub subscriptions pull $(INSPECTION) --project=$(PROJECT) --limit=10

duplicates:
	bq query --nouse_legacy_sql --location=$(REGION) --project_id=$(PROJECT) \
	  "SELECT event_id, COUNT(*) AS copies FROM \`$(TABLE)\` WHERE event_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY) GROUP BY event_id HAVING copies > 1"

inventory:
	./scripts/inventory.sh $(PROJECT) $(PREFIX) $(DATASET)

kit-local:
	cd movenow && docker compose up --build

kit-demo:
	cd movenow/tableau && node server.mjs

dashboard:
	cd movenow/tableau && npm ci && SOURCE=bigquery GOOGLE_CLOUD_PROJECT=$(PROJECT) BQ_TABLE=$(TABLE) \
	  BQ_LOCATION=$(REGION) SUBSCRIPTION=$(SUBSCRIPTION) DEAD_LETTER_SUBSCRIPTION=$(INSPECTION) node server.mjs
