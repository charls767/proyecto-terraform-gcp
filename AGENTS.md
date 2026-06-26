# Guia para agentes LLM

Este repositorio despliega una arquitectura Terraform en GCP para cumplir el proyecto de Servicios en la Nube 2026-01. El sistema expone una unica IP publica mediante un Global external Application Load Balancer HTTP y distribuye trafico hacia dos VMs independientes usando pesos.

## Archivos que debes leer primero

- `README.md`: instrucciones de ejecucion, escenarios y limpieza.
- `variables.tf`: variables de proyecto, region, zona y pesos de trafico.
- `main.tf`: provider, APIs, red, VMs, grupos de instancia, health check, firewall, backends, URL map, proxy y forwarding rule.
- `outputs.tf`: IP, URL y nombres de backends.
- `terraform.tfvars.example`: plantilla segura para crear `terraform.tfvars`.

## Reglas del proyecto

- Para evaluar escenarios, modifica solo `terraform.tfvars`.
- No cambies `main.tf` para alternar entre produccion, mantenimiento o 50/50.
- No configures servidores por SSH ni desde la consola de GCP.
- No des IP publica directa a las VMs.
- No abras trafico `0.0.0.0/0` hacia las VMs.
- No subas `terraform.tfvars`, `.terraform/` ni archivos `terraform.tfstate`.

## Variables criticas

- `project_id`: ID exacto del proyecto GCP.
- `prod_weight`: peso hacia el Servicio Principal.
- `contingency_weight`: peso hacia el Servicio de Contingencia.

La suma de los pesos debe ser mayor que cero.

## Escenarios esperados

| Escenario | `prod_weight` | `contingency_weight` | Resultado |
|---|---:|---:|---|
| Produccion activa | 100 | 0 | Solo Servicio Principal |
| Mantenimiento total | 0 | 100 | Solo Servicio de Contingencia |
| Balance 50/50 | 50 | 50 | Ambos servicios en multiples peticiones |

## Recursos criticos

- `google_compute_instance.prod`
- `google_compute_instance.contingency`
- `google_compute_instance_group.prod`
- `google_compute_instance_group.contingency`
- `google_compute_backend_service.prod`
- `google_compute_backend_service.contingency`
- `google_compute_url_map.traffic`
- `google_compute_global_forwarding_rule.http`

## Cierre obligatorio

Despues de probar, ejecuta `terraform destroy` y confirma que `terraform state list` no muestre recursos. La rubrica advierte que dejar recursos activos puede invalidar la entrega por conflictos de nombres durante la revision.

