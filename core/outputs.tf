output "egress_public_ip" {
  value = azurerm_public_ip.egress.ip_address
}