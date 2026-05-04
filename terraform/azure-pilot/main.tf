# =============================================================================
# PILOT LIGHT en Azure (Azure DB for MySQL + VM con Docker)
# =============================================================================
# Esta infra SOLO se despliega cuando AWS cae (failover). En operacion
# normal NO existe y no cuesta nada.
#
# Componentes:
#   - VNet con dos subredes (una para la VM, otra delegada a MySQL)
#   - Azure DB for MySQL Flexible Server (B_Standard_B1s)
#   - VM Ubuntu con Docker (Standard_B1s)
#   - Private DNS para que la VM resuelva el FQDN privado de Azure DB
#
# Azure DB con subred delegada NO es accesible desde fuera de la VNet.
# La restauracion del .sql se hace desde la VM actuando como bastion.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  # Guardamos el state en el mismo bucket S3 que AWS (logico: el state
  # de Azure depende de credenciales de Azure que tenemos en GitHub
  # secrets, pero el bucket es S3 porque AWS Academy lo permite y es
  # gratis con la cuenta).
  backend "s3" {
    key    = "azure-pilot/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

variable "db_password" {
  description = "Contrasena de Azure DB. Inyectar con TF_VAR_db_password."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "La contrasena debe tener al menos 8 caracteres."
  }
}

variable "vm_admin_password" {
  description = "Contrasena del admin de la VM. Inyectar con TF_VAR_vm_admin_password."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.vm_admin_password) >= 12
    error_message = "Azure exige al menos 12 caracteres en la contrasena de VM."
  }
}

# -----------------------------------------------------------------------------
# DATA Group del DR
# -----------------------------------------------------------------------------
data "azurerm_resource_group" "dr" {
  name     = "tfg-final-spain-rg"
}

# -----------------------------------------------------------------------------
# Red
# -----------------------------------------------------------------------------
resource "azurerm_virtual_network" "dr" {
  name                = "tfg-pilot-vnet"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name
  address_space       = ["10.1.0.0/16"]

  tags = { Project = "TFG-MultiCloud" }
}

resource "azurerm_subnet" "vm" {
  name                 = "tfg-pilot-vm-subnet"
  resource_group_name  = data.azurerm_resource_group.dr.name
  virtual_network_name = azurerm_virtual_network.dr.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_subnet" "mysql" {
  name                 = "tfg-pilot-mysql-subnet"
  resource_group_name  = data.azurerm_resource_group.dr.name
  virtual_network_name = azurerm_virtual_network.dr.name
  address_prefixes     = ["10.1.2.0/24"]

  delegation {
    name = "mysql-delegation"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_private_dns_zone" "mysql" {
  name                = "alvaro-tfg.mysql.database.azure.com"
  resource_group_name = data.azurerm_resource_group.dr.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql" {
  name                  = "tfg-pilot-dns-link"
  resource_group_name   = data.azurerm_resource_group.dr.name
  private_dns_zone_name = azurerm_private_dns_zone.mysql.name
  virtual_network_id    = azurerm_virtual_network.dr.id
}

# -----------------------------------------------------------------------------
# Azure DB for MySQL Flexible Server
# -----------------------------------------------------------------------------
resource "azurerm_mysql_flexible_server" "dr" {
  name                = "tfg-pilot-mysql-alvaro-2026"
  resource_group_name = data.azurerm_resource_group.dr.name
  location            = data.azurerm_resource_group.dr.location

  administrator_login    = "admin_tfg"
  administrator_password = var.vm_admin_password

  sku_name = "B_Standard_B1ms"
  version  = "8.0.21"

  storage {
    size_gb = 20
    iops    = 360
  }

  delegated_subnet_id = azurerm_subnet.mysql.id
  private_dns_zone_id = azurerm_private_dns_zone.mysql.id

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  tags = { Project = "TFG-MultiCloud" }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.mysql]
}

resource "azurerm_mysql_flexible_database" "app" {
  name                = "tfg_app"
  resource_group_name = data.azurerm_resource_group.dr.name
  server_name         = azurerm_mysql_flexible_server.dr.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# -----------------------------------------------------------------------------
# VM Docker
# -----------------------------------------------------------------------------
resource "azurerm_public_ip" "vm" {
  name                = "tfg-pilot-vm-ip"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = { Project = "TFG-MultiCloud" }
}

resource "azurerm_network_security_group" "vm" {
  name                = "tfg-pilot-vm-nsg"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name

  security_rule {
    name                       = "HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "vm" {
  name                = "tfg-pilot-vm-nic"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

resource "azurerm_network_interface_security_group_association" "vm" {
  network_interface_id      = azurerm_network_interface.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

resource "azurerm_linux_virtual_machine" "docker" {
  name                = "tfg-pilot-docker-vm"
  resource_group_name = data.azurerm_resource_group.dr.name
  location            = data.azurerm_resource_group.dr.location
  size                = "Standard_B1ms"

  admin_username                  = "azureuser"
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.vm.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(<<-CLOUDINIT
    #cloud-config
    package_update: true
    packages:
      - docker.io
      - docker-compose
      - mysql-client
      - jq
    runcmd:
      - systemctl enable docker
      - systemctl start docker
      - usermod -aG docker azureuser
      - echo "OK" > /tmp/vm-setup-complete
  CLOUDINIT
  )

  tags = { Project = "TFG-MultiCloud" }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "vm_public_ip" {
  description = "IP publica de la VM Docker. Por aqui se accede a la app."
  value       = azurerm_public_ip.vm.ip_address
}

output "mysql_fqdn" {
  description = "FQDN privado de Azure DB. Solo resoluble desde dentro de la VNet."
  value       = azurerm_mysql_flexible_server.dr.fqdn
}

output "resource_group" {
  description = "Resource group del pilot light (para destruirlo en failback)."
  value       = data.azurerm_resource_group.dr.name
}
