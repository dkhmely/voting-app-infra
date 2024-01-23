variable "deployment_locations" {
  type = list(object({
    location = string
    vm_sku   = string
  }))
}