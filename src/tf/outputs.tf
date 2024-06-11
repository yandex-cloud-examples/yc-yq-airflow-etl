output "access_key" {
  value = yandex_iam_service_account_static_access_key.sa-static-key.access_key
}
output "secret_key" {
  sensitive = true
  value = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
}