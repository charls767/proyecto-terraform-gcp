# Proyecto Terraform - Trafico ponderado en GCP

Este repositorio despliega una arquitectura en Google Cloud Platform usando Terraform. El objetivo es exponer una unica IP publica y distribuir el trafico HTTP hacia dos servicios independientes mediante pesos configurados en `terraform.tfvars`.

## Arquitectura

```mermaid
flowchart LR
    U["Usuario en internet"] --> IP["IP publica unica"]
    IP --> FR["Global forwarding rule :80"]
    FR --> PROXY["Target HTTP proxy"]
    PROXY --> URLMAP["URL map con pesos"]
    URLMAP -->|"prod_weight"| BP["Backend produccion"]
    URLMAP -->|"contingency_weight"| BC["Backend contingencia"]
    BP --> VMP["VM produccion"]
    BC --> VMC["VM contingencia"]
```

La solucion crea una VPC custom, una subred, dos VMs `e2-micro` sin IP publica directa, dos grupos de instancia, un health check HTTP, un firewall limitado a los rangos de Google Load Balancing y un Global external Application Load Balancer HTTP.

## Requisitos previos

- Terraform instalado.
- `gcloud` (Google Cloud SDK) instalado.
- Una cuenta de Google con acceso al proyecto `moonlit-buckeye-486820-c0` (el profesor ya tiene rol `roles/editor` en el, segun la rubrica).

## Autenticacion (paso unico, no requiere editar ningun archivo)

El `project_id` ya viene fijado en `terraform.tfvars`, asi que **nadie necesita editar los `.tf`**. Lo unico que cada persona debe hacer una sola vez en su maquina es iniciar sesion con su propia cuenta de Google:

```powershell
gcloud auth application-default login
```

Eso abre el navegador, inicias sesion y Terraform ya puede desplegar. **No** es necesario `gcloud config set project` para `terraform apply`: Terraform toma el proyecto desde `terraform.tfvars`, no desde la configuracion de `gcloud`.

> `gcloud config set project` solo se necesita para los comandos auxiliares de `gcloud` (como `get-health`). En este README esos comandos ya incluyen `--project`, asi que tampoco hace falta configurarlo.

## Variables

| Variable | Descripcion | Ejemplo |
|---|---|---|
| `project_id` | ID exacto del proyecto GCP. | `mi-proyecto-gcp` |
| `region` | Region de la subred. | `us-central1` |
| `zone` | Zona donde se crean las VMs. | `us-central1-a` |
| `name_prefix` | Prefijo de nombres para evitar colisiones. | `tf-proyecto` |
| `prod_weight` | Peso hacia el servicio principal. | `100` |
| `contingency_weight` | Peso hacia el servicio de contingencia. | `0` |

La suma de `prod_weight` y `contingency_weight` debe ser mayor que cero. Cada peso debe estar entre `0` y `100`.

## Configuracion

El repositorio incluye un `terraform.tfvars` ya versionado con el `project_id` y el Escenario 1 activo, de modo que se ejecuta con un solo `terraform apply` sin pasos manuales. Para cambiar de escenario, edita unicamente los pesos en `terraform.tfvars` (descomenta el bloque del escenario deseado). El `project_id` no es un dato secreto: es el identificador del proyecto sobre el que se otorga acceso IAM al revisor.

> El archivo `terraform.tfvars.example` se conserva como plantilla de referencia.

## Ejecucion

```powershell
gcloud auth application-default login   # paso unico de autenticacion
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Al terminar, consulta la IP publica unica:

```powershell
terraform output lb_url
terraform output -raw lb_ip
```

Los backends pueden tardar entre 3 y 10 minutos en aparecer saludables tras el primer despliegue.

## Escenarios de evaluacion

| Escenario | `prod_weight` | `contingency_weight` | Resultado esperado |
|---|---:|---:|---|
| Produccion activa | 100 | 0 | Todas las respuestas muestran `Bienvenido al Servicio Principal - Versión Producción` |
| Mantenimiento total | 0 | 100 | Todas las respuestas muestran `Error 503 - Sitio en Mantenimiento Programado` |
| Balance 50/50 | 50 | 50 | Varias peticiones muestran ambos servicios |

Para probar despues de cada cambio de pesos:

```powershell
terraform apply
$ip = terraform output -raw lb_ip
1..20 | ForEach-Object {
  curl.exe -s -H "Cache-Control: no-cache" "http://$ip"
}
```

Para el escenario `50/50`, si las peticiones desde una sola terminal salen muy cargadas hacia un servicio, prueba con un `Host` distinto por solicitud para observar mejor la distribucion ponderada:

```powershell
$ip = terraform output -raw lb_ip
1..80 | ForEach-Object {
  $hostName = "test-$([guid]::NewGuid().ToString('N')).example.com"
  curl.exe -s -H "Host: $hostName" -H "Cache-Control: no-cache, no-store" "http://$ip/?t=$([guid]::NewGuid())"
}
```

Para revisar la salud de los backends:

```powershell
gcloud compute backend-services get-health "$(terraform output -raw prod_backend_name)" --global --project moonlit-buckeye-486820-c0
gcloud compute backend-services get-health "$(terraform output -raw contingency_backend_name)" --global --project moonlit-buckeye-486820-c0
```

## Evidencias

Guarda en `evidencias/` capturas o logs de:

- Escenario 1: produccion activa.
- Escenario 2: mantenimiento total.
- Escenario 3: balance 50/50.
- Ejecucion final exitosa de `terraform destroy`.

## Limpieza obligatoria

Ejecuta siempre:

```powershell
terraform destroy
terraform state list
```

`terraform state list` no debe mostrar recursos despues de la destruccion. Revisa tambien en GCP que no queden VMs, balanceadores, VPCs, reglas de firewall ni direcciones IP externas creadas por este proyecto.

## Entrega

El repositorio debe enviarse por correo con el asunto exacto:

```text
[Servicios Nube 2026-01] Proyecto Terraform - Grupo [Numero de Grupo]
```

Ejemplo:

```text
[Servicios Nube 2026-01] Proyecto Terraform - Grupo 3
```

## Advertencia de costos

Aunque se usan recursos pequenos, la infraestructura puede generar costos mientras este desplegada. Ejecuta `terraform destroy` al terminar las pruebas.
