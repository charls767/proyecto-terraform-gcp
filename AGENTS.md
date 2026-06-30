# AGENTS.md — Guía para agentes LLM

Este documento explica la estructura, lógica y comportamiento del repositorio `proyecto-terraform-gcp` a un agente de IA que necesite leerlo, auditarlo, modificarlo o desplegarlo.

---

## Propósito del proyecto

Este repositorio implementa infraestructura como código (IaC) en **Google Cloud Platform (GCP)** usando **Terraform**. El objetivo es desplegar un balanceador de carga HTTP global con dos backends independientes y controlar la distribución del tráfico entre ellos mediante variables numéricas, sin modificar el código fuente de la arquitectura.

---

## Estructura de archivos

```
proyecto-terraform-gcp/
├── main.tf                    # Definición completa de todos los recursos GCP
├── variables.tf               # Declaración de variables con validaciones
├── outputs.tf                 # Valores que Terraform expone tras el despliegue
├── terraform.tfvars           # Valores reales versionados (project_id + escenario activo)
├── terraform.tfvars.example   # Plantilla de referencia
├── .gitignore                 # Excluye archivos de estado (.tfstate)
├── .terraform.lock.hcl        # Lock file del proveedor hashicorp/google ~> 6.0
├── evidencias/                # Carpeta con capturas de pantalla de los tres escenarios
└── README.md                  # Manual de uso para humanos
```

> **Importante:** El archivo `terraform.tfvars` **está versionado** e incluye el `project_id` y el escenario activo, por lo que el proyecto se despliega con un solo `terraform apply` sin pasos previos. Para cambiar de escenario se editan únicamente `prod_weight` y `contingency_weight` en ese archivo. Lo único excluido por `.gitignore` es el estado (`*.tfstate`).

---

## Variables — el único punto de control

Todas las variables se declaran en `variables.tf`. Para modificar el comportamiento del sistema, se edita únicamente `terraform.tfvars`.

| Variable             | Tipo   | Default       | Descripción                                                     |
|----------------------|--------|---------------|-----------------------------------------------------------------|
| `project_id`         | string | *(requerido)* | ID exacto del proyecto GCP. No puede estar vacío.               |
| `region`             | string | `us-central1` | Región donde se crea la subred.                                 |
| `zone`               | string | `us-central1-a`| Zona donde se despliegan las VMs.                              |
| `name_prefix`        | string | `tf-proyecto` | Prefijo de todos los nombres de recursos. Solo minúsculas y guiones. |
| `prod_weight`        | number | `100`         | Peso de tráfico hacia el Servicio Principal (0–100).            |
| `contingency_weight` | number | `0`           | Peso de tráfico hacia el Servicio de Contingencia (0–100).      |

**Regla crítica:** `prod_weight + contingency_weight` debe ser mayor que 0. Esta restricción se implementa como un `precondition` en el `google_compute_url_map` de `main.tf` (detiene el `apply` con error si la suma es 0) y como validaciones individuales de rango en `variables.tf`.

---

## Arquitectura desplegada

El flujo de tráfico es el siguiente:

```
Internet → IP pública global (google_compute_global_address)
         → Global Forwarding Rule (puerto 80, TCP)
         → Target HTTP Proxy
         → URL Map con weighted_backend_services
               ├── Backend Service "prod"     ← peso: prod_weight
               │       └── Instance Group "prod-ig"
               │               └── VM "prod-vm" (e2-micro, Debian 12, sin IP pública)
               └── Backend Service "contingency" ← peso: contingency_weight
                       └── Instance Group "contingency-ig"
                               └── VM "contingency-vm" (e2-micro, Debian 12, sin IP pública)
```

Todos los recursos comparten el mismo prefijo definido por `name_prefix`. La VPC es custom (`auto_create_subnetworks = false`) con subred `10.10.0.0/24`.

---

## Lógica del traffic splitting en `main.tf`

El mecanismo clave es el bloque `local.active_weighted_backend_services`, que construye dinámicamente la lista de backends activos:

- Si `prod_weight > 0`, el backend de producción se incluye con ese peso.
- Si `contingency_weight > 0`, el backend de contingencia se incluye con ese peso.
- Si un peso es `0`, ese backend **no aparece en la lista** de weighted services, evitando errores de validación de GCP (que no acepta peso 0 en `weighted_backend_services`).

El `default_service` del URL Map también se actualiza dinámicamente: apunta al backend de producción si su peso es mayor que 0, o al de contingencia si producción está en 0. Esto garantiza que siempre haya un servicio por defecto válido.

---

## Escenarios de evaluación

Para cambiar de escenario, editar `terraform.tfvars` y ejecutar `terraform apply`:

**Escenario 1 — Producción activa (100% → Principal):**
```hcl
prod_weight        = 100
contingency_weight = 0
```
Resultado esperado: todas las respuestas muestran `Bienvenido al Servicio Principal - Versión Producción`.

**Escenario 2 — Mantenimiento total (100% → Contingencia):**
```hcl
prod_weight        = 0
contingency_weight = 100
```
Resultado esperado: todas las respuestas muestran `Error 503 - Sitio en Mantenimiento Programado`.

**Escenario 3 — Balance 50/50:**
```hcl
prod_weight        = 50
contingency_weight = 50
```
Resultado esperado: peticiones consecutivas alternan entre ambos servicios.

---

## Cómo funciona el servidor web en cada VM

Las VMs no requieren configuración manual post-despliegue. El contenido web se genera mediante `metadata_startup_script`, definido en `locals` dentro de `main.tf`. El script de arranque:

1. Crea el directorio `/opt/web/`.
2. Escribe el archivo `index.html` con el mensaje correspondiente al servicio.
3. Registra y activa un servicio `systemd` llamado `simple-web.service` que ejecuta `python3 -m http.server 80`.

Este servidor responde en el puerto 80 sin dependencias externas adicionales (solo Python 3, disponible por defecto en Debian 12).

---

## Seguridad de red

- Las VMs **no tienen IP pública** (`network_interface` sin `access_config`).
- La regla de firewall `allow-health-checks` solo permite tráfico TCP en el puerto 80 desde los rangos de los health checkers de Google Load Balancing: `130.211.0.0/22` y `35.191.0.0/16`.
- No existe ninguna regla que permita acceso SSH externo desde internet.

---

## Outputs disponibles tras `terraform apply`

| Output                    | Descripción                                                        |
|---------------------------|--------------------------------------------------------------------|
| `lb_ip`                   | Dirección IP pública del balanceador.                              |
| `lb_url`                  | URL HTTP completa para probar en el navegador.                     |
| `prod_backend_name`       | Nombre del backend service de producción (para usar con `gcloud`). |
| `contingency_backend_name`| Nombre del backend service de contingencia.                        |

---

## Comandos de despliegue y verificación

```bash
# Configuración inicial (una sola vez)
gcloud auth application-default login
gcloud config set project TU_PROJECT_ID

# Despliegue
terraform init
terraform validate
terraform plan
terraform apply

# Verificar IP pública
terraform output lb_ip

# Verificar salud de los backends
gcloud compute backend-services get-health $(terraform output -raw prod_backend_name) --global
gcloud compute backend-services get-health $(terraform output -raw contingency_backend_name) --global

# Limpieza obligatoria al terminar
terraform destroy
```

> Los backends pueden tardar entre 3 y 10 minutos en quedar saludables tras el primer despliegue. Si la IP responde con error 502, es normal durante ese período de inicialización.

---

## Restricciones que el agente debe respetar

1. **No modificar los archivos `.tf`** para cambiar escenarios. Solo editar `terraform.tfvars`.
2. **No dejar recursos activos** tras las pruebas. Ejecutar siempre `terraform destroy` al finalizar y confirmar con `terraform state list` que queda vacío.
3. **`terraform.tfvars` SÍ está versionado** e incluye el `project_id` para que el repositorio sea autocontenido. Para cambiar de escenario solo se editan los pesos en ese archivo.
4. **No subir `terraform.tfstate` ni `terraform.tfstate.backup`.** Están excluidos por `.gitignore`. Si el agente realiza pruebas locales, debe destruir los recursos antes de que el profesor haga el despliegue de revisión; de lo contrario, GCP rechazará el despliegue por nombres duplicados.
5. El proveedor requerido es `hashicorp/google ~> 6.0` con Terraform `>= 1.5.0`.

---

## Notas de compatibilidad

- La propiedad `load_balancing_scheme = "EXTERNAL_MANAGED"` en los backend services y en el forwarding rule es requerida para usar `weighted_backend_services` en el URL Map con el proveedor google `~> 6.0`. No cambiar a `EXTERNAL`.
- El `precondition` del `url_map` valida la suma de pesos en tiempo de plan y detiene el `apply` si es 0.
- La imagen de las VMs es `debian-cloud/debian-12`. No cambiar a versiones anteriores sin verificar disponibilidad de Python 3.
