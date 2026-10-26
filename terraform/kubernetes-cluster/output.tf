output "public_ip" {
  value = azurerm_public_ip.public-ip.ip_address
}

# Save with: terraform output -raw kubeconfig > kubeconfig
output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

# Save with: terraform output -raw talosconfig > talosconfig
output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}
