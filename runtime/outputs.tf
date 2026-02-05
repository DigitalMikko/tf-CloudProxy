output "egress_public_ip" {
  value = local.egress_ip
}

output "container_app_name" {
  value = azapi_resource.container_app.name
}