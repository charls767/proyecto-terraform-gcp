# Evidencia — terraform destroy

Entregable obligatorio (Cierre de Proyecto): captura/log que evidencie la
ejecucion exitosa de `terraform destroy`, dejando el entorno GCP limpio.

## Pendiente de adjuntar

Reemplaza este texto pegando la captura de pantalla o el log final de tu ejecucion.
Para regenerar la evidencia:

```powershell
terraform destroy
terraform state list   # debe quedar vacio
```

Captura la salida final donde aparezca:

```
Destroy complete! Resources: N destroyed.
```

y el resultado vacio de `terraform state list`, confirmando que no quedan
recursos activos en la cuenta de GCP.
