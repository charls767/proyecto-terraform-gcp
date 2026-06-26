output "lb_ip" {
  description = "IP publica unica del balanceador."
  value       = google_compute_global_address.lb_ip.address
}

output "lb_url" {
  description = "URL HTTP para probar el servicio."
  value       = "http://${google_compute_global_address.lb_ip.address}"
}

output "prod_backend_name" {
  description = "Nombre del backend service de produccion para revisar salud con gcloud."
  value       = google_compute_backend_service.prod.name
}

output "contingency_backend_name" {
  description = "Nombre del backend service de contingencia para revisar salud con gcloud."
  value       = google_compute_backend_service.contingency.name
}

