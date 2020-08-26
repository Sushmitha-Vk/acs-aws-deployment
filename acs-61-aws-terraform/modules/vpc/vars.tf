### VPC ###
variable "aws-availability-zones" {
  type = "string"
  description = "AWS zones"
}
variable "vpc-cidr" {
  type = "string"
  description = "VPC CIDR"
}
### Resource prefix ##
variable "resource-prefix" {
  type = "string"
  description = "Prefix name to identify resources"
}

### Tags ###
variable "resource-owner" {
  type = "string"
  description = "Owner Tag"
}
variable "resource-customer" {
  type = "string"
  description = "Customer Tag"
}

