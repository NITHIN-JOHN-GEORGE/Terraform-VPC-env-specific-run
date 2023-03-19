variable "env" {
  type        = string
  description = "please enter your one environment name eg dev,qa or prod"
}

variable "region" {
  type = string
  description = "please enter a valid region for vpc launching"
}

variable "vpc_cidr" {
  type        = string
  description = "please enter a valid cidr range for your vpc in string eg: 10.1.0.0/16"
}
variable "vpc_name" {
  type        = string
  description = "please enter a vpc_name for your new vpc"
}

variable "vpc_tags" {
  type = map(string)
  description = "please enter a custom tag for your vpc in a key value pair"
}
variable "eks_cluster_name" {
  type        = string
  description = "Assume your eks cluster name and enter here, this is used under your vpc tags"
}
variable "public_subnets_cidr" {
  type = list(string)
  description = "please enter your public subnet's cidr's in a list of string. note => if you want 3 public subnets you can enter 3 cidrs ranges for that"
}

variable "public_subnet_tags" {
  type = map(string)
  description = "please enter a custom tag for your public_subnet_tags in a key value pair"
}

variable "availability_zones" {
  type = list(string)
  description = "please enter your availability_zones for your subnets in a  list of string note => if you want 3 subnets in 3 differnt zone plaese enter 3 zones. You can follow single avilablility zone or multi availability zone method as your wish"
}

variable "private_subnets_cidr" {
  type = list(string)
  description = "please enter your private subnet's cidr's in a list of string note => if you want 3 private subnets you can enter 3 cidrs ranges for that"
}

variable "private_subnet_tags" {
  type = map(string)
  description = "please enter a custom tag for your private_subnet in a key value pair "
}

variable "public_route_table_routes" {
  type = list(map(string))
  default = []
  description = "if you have a route, please eneter your private routes as key value pairs eg [{},{}] otherwise leave it..... in a pair keys are ipv6_cidr_block,egress_only_gateway_id,gateway_id,instance_id,nat_gateway_id,network_interface_id,transit_gateway_id,vpc_endpoint_id,vpc_peering_connection_id eg => [{ cidr_block = ,ipv6_cidr_block =  ,egress_only_gateway_id  = ,gateway_id  = ,instance_id = ,nat_gateway_id  = ,network_interface_id = ,transit_gateway_id = ,vpc_endpoint_id = ,vpc_peering_connection_id = },{}... ]"                
}

variable "private_route_table_routes" {
  type    = list(map(string))
  default = []
  description = "if you have a route, please eneter your private routes as key value pairs eg [{},{}] otherwise leave it..... in a pair keys are ipv6_cidr_block,egress_only_gateway_id,gateway_id,instance_id,nat_gateway_id,network_interface_id,transit_gateway_id,vpc_endpoint_id,vpc_peering_connection_id eg => [{ cidr_block = ,ipv6_cidr_block =  ,egress_only_gateway_id  = ,gateway_id  = ,instance_id = ,nat_gateway_id  = ,network_interface_id = ,transit_gateway_id = ,vpc_endpoint_id = ,vpc_peering_connection_id = },{}... ]"                
}


variable "vpc_flowlog" {
  type = bool #value must be true or false
  description = "please enter true or false"
}


variable "vpc_flowlog_bucket_retention" { #enter the retention of s3bucket
  type = number
  description = "please eneter your flowlog s3 bucket retention period in number of days"
}

variable "vpc_flowlog_destination_type" {
  type = string #value must be #s3 or cloudwatch_log_group
  description = "please enter your vpc flowlog backend type s3 or cloudwatch_log_group"
}

variable "AWS_SECRET_KEY" {
 description = "to run terraform code in workspace please enter your AWS_SECRET_KEY"
}

variable "AWS_ACCESS_KEY" {
 description = "to run terraform code in workspace please enter your AWS_ACCESS_KEY"
}
