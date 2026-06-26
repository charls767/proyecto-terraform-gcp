variable "project_id" {
  description = "ID exacto del proyecto de GCP donde se desplegara la infraestructura."
  type        = string

  validation {
    condition     = length(trimspace(var.project_id)) > 0
    error_message = "project_id no puede estar vacio."
  }
}

variable "region" {
  description = "Region para la subred."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona donde se crean las VMs."
  type        = string
  default     = "us-central1-a"
}

variable "name_prefix" {
  description = "Prefijo para nombrar recursos y evitar colisiones."
  type        = string
  default     = "tf-proyecto"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,40}[a-z0-9])?$", var.name_prefix))
    error_message = "name_prefix debe iniciar con una letra minuscula, usar solo letras minusculas, numeros o guiones, y terminar en letra o numero."
  }
}

variable "prod_weight" {
  description = "Peso de trafico hacia el Servicio Principal."
  type        = number
  default     = 100

  validation {
    condition     = var.prod_weight >= 0 && var.prod_weight <= 100
    error_message = "prod_weight debe estar entre 0 y 100."
  }
}

variable "contingency_weight" {
  description = "Peso de trafico hacia el Servicio de Contingencia."
  type        = number
  default     = 0

  validation {
    condition     = var.contingency_weight >= 0 && var.contingency_weight <= 100
    error_message = "contingency_weight debe estar entre 0 y 100."
  }
}

