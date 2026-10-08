module "analytics" {
  source = "../../modules/analytics"

  project_id = "groupe3inssettp"
  location   = "europe-west9"

  dataset_id = "movenow"
  table_id   = "positions"

  schema = file("${path.module}/../../schemas/positions.json")

  partition_field = "event_time"
  retention_days  = 7

  labels = {
    projet        = "movenow"
    environnement = "lab"
  }
}