terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"

    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "terraform-rg" {
  name     = "terraform-rg-azure"
  location = "East US"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "terraform-Vnet" {
  name                = "terraform-Vnet-Azure"
  resource_group_name = azurerm_resource_group.terraform-rg.name
  location            = azurerm_resource_group.terraform-rg.location
  address_space       = ["10.0.0.0/16"]

  tags = {
    environment = "dev"
  }

}

resource "azurerm_subnet" "terraform-Subnet" {
  name                 = "terraform-Subnet-Azure"
  resource_group_name  = azurerm_resource_group.terraform-rg.name
  virtual_network_name = azurerm_virtual_network.terraform-Vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_network_security_group" "terraform-NSG" {
  name                = "terraform-NSG-Azure"
  location            = azurerm_resource_group.terraform-rg.location
  resource_group_name = azurerm_resource_group.terraform-rg.name

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "terraform-NSG-dev-rule" {
  name                        = "terraform-NSG-dev-rule-Azure"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "88.156.176.0/20"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.terraform-rg.name
  network_security_group_name = azurerm_network_security_group.terraform-NSG.name
}

resource "azurerm_subnet_network_security_group_association" "terraform-NSG-rule-association" {
  subnet_id                 = azurerm_subnet.terraform-Subnet.id
  network_security_group_id = azurerm_network_security_group.terraform-NSG.id
}

resource "azurerm_public_ip" "terraform-IP" {
  name                = "terraform-IP-Azure"
  resource_group_name = azurerm_resource_group.terraform-rg.name
  location            = azurerm_resource_group.terraform-rg.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "terraform-NIC" {
  name                = "terraform-NIC-Azure"
  location            = azurerm_resource_group.terraform-rg.location
  resource_group_name = azurerm_resource_group.terraform-rg.name

  ip_configuration {
    name                          = "internal-IP"
    subnet_id                     = azurerm_subnet.terraform-Subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.terraform-IP.id
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_linux_virtual_machine" "terraform-VM" {
  count                 = 3
  name                  = "terraform-VM${count.index}-Azure"
  resource_group_name   = azurerm_resource_group.terraform-rg.name
  location              = azurerm_resource_group.terraform-rg.location
  size                  = "Standard_B1s"
  admin_username        = "adminuser"
  network_interface_ids = [azurerm_network_interface.terraform-NIC.id]

  custom_data = filebase64("customdata.tpl") // filebase64() function 

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/terraform-key.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference { // google publisher,offer,sku,version values for each disto
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", { // ${var.host_os} inserts "windows" or "linux" value depending on which os we are using
      hostname     = self.public_ip_address,
      user         = "adminuser",
      identityfile = "C:\\Users\\Wiktor\\.ssh\\terraform-key"
    })
    interpreter = var.host_os == "windows" ? ["Powershell", "-Command"] : ["bash", "-c"]
  }

  tags = {
    environment = "dev"
  }
}

data "azurerm_public_ip" "terraform-ip-data" {
  name                = azurerm_public_ip.terraform-IP.name
  resource_group_name = azurerm_resource_group.terraform-rg.name
}

output "public_ip_address" {
  value = "${join(", ", azurerm_linux_virtual_machine.terraform-VM.*.name)}: ${join(", ", data.azurerm_public_ip.terraform-ip-data.*.ip_address)}"
}



