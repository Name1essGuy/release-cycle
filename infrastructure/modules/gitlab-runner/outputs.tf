output "ip" {
  value = yandex_compute_instance.runner.network_interface.0.nat_ip_address
}

output "ssh" {
  value = "ssh ubuntu@${yandex_compute_instance.runner.network_interface.0.nat_ip_address}"
}