resource "yandex_iam_service_account" "sa" {
  folder_id = var.yc_folder_id
  name      = "etl-sa"
}

// Grant permissions
resource "yandex_resourcemanager_folder_iam_member" "sa-storage-editor" {
  folder_id = var.yc_folder_id
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa-yc-invoker" {
  folder_id = var.yc_folder_id
  role      = "yq.invoker"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa-airflow-intprov" {
  folder_id = var.yc_folder_id
  role      = "managed-airflow.integrationProvider"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "sa-pg-viewer" {
  folder_id = var.yc_folder_id
  role      = "managed-postgresql.viewer"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

// Create Static Access Keys
resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = yandex_iam_service_account.sa.id
  description        = "static access key for object storage"
}

resource "yandex_iam_service_account_key" "sa-auth-key" {
  service_account_id =  yandex_iam_service_account.sa.id
  description        = "Key for ETL solution"
  key_algorithm      = "RSA_2048"
}

resource "yandex_storage_bucket" "dag_bucket" {
  bucket = "dag-bucket"
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
}

resource "yandex_storage_bucket" "etl_bucket" {
  bucket = "etl-bucket"
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
}

resource "yandex_storage_object" "dag" {
  bucket = yandex_storage_bucket.dag_bucket.bucket
  key    = "dags/yq_dag.py"
  source = "../py/yq_dag.py"
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  depends_on = [ yandex_storage_bucket.dag_bucket ]
}

resource "local_file" "auth_key" {
  content  = templatefile("key.tpl.json", {
    key_id             = yandex_iam_service_account_key.sa-auth-key.id
    service_account_id = yandex_iam_service_account_key.sa-auth-key.service_account_id
    created_at         = yandex_iam_service_account_key.sa-auth-key.created_at
    key_algorithm      = yandex_iam_service_account_key.sa-auth-key.key_algorithm
    public_key         = jsonencode(yandex_iam_service_account_key.sa-auth-key.public_key)
    private_key        = jsonencode(yandex_iam_service_account_key.sa-auth-key.private_key)
  })
  filename = "auth_key.json"
}