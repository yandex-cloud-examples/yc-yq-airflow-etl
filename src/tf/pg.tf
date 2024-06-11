resource "yandex_mdb_postgresql_cluster" "pg-finance" {
  name                = "pg-finance"
  environment         = "PRESTABLE"
  network_id          = yandex_vpc_network.finance-network.id
  security_group_ids  = [ yandex_vpc_security_group.pgsql-sg.id ]
  deletion_protection = false

  config {
    version = 16
    resources {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-ssd"
      disk_size          = "20"
    }
  }

  host {
    zone      = var.net_zone
    name      = "pg-host-a"
    subnet_id = yandex_vpc_subnet.finance-subnet.id
    assign_public_ip = true
  }
}

resource "yandex_mdb_postgresql_database" "db" {
  cluster_id = yandex_mdb_postgresql_cluster.pg-finance.id
  name       = var.pg.username
  owner      = var.pg.username
  depends_on = [
    yandex_mdb_postgresql_user.user
  ]
}

resource "yandex_mdb_postgresql_user" "user" {
  cluster_id = yandex_mdb_postgresql_cluster.pg-finance.id
  name       = var.pg.username
  password   = var.pg.password
}


resource "yandex_vpc_security_group" "pgsql-sg" {
  name       = "pgsql-sg"
  network_id = yandex_vpc_network.finance-network.id

  ingress {
    description    = "PostgreSQL"
    port           = 6432
    protocol       = "TCP"
    v4_cidr_blocks = [ "0.0.0.0/0" ]
  }
}

resource "null_resource" "db_setup" {

  provisioner "local-exec" {
    command = templatefile("pg-command.tpl", {
    HOST = yandex_mdb_postgresql_cluster.pg-finance.host[0].fqdn
    USERNAME = var.pg.username
    ACC_NUM = var.account_pool_size
  })
    environment = {
      PGPASSWORD = "${var.pg.password}"
    }
    when = create
  }
  depends_on = [
    yandex_mdb_postgresql_user.user, yandex_mdb_postgresql_database.db
  ]
}
