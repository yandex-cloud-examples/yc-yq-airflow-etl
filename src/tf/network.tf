resource "yandex_vpc_network" "finance-network" { name = "etl-network" }

resource "yandex_vpc_subnet" "finance-subnet" {
  name           = "etl-subnet"
  zone           = var.net_zone
  network_id     = yandex_vpc_network.finance-network.id
  v4_cidr_blocks = ["10.11.0.0/24"]
}
