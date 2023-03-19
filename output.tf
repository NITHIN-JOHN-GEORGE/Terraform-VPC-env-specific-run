output "vpc_id" {
  value = element(aws_vpc.vpc.*.id, 0)
}

output "vpc_arn" {
  value = element(aws_vpc.vpc.*.arn, 0)
}

output "public_subnet_id" {
  value = join("", aws_subnet.public[*].id)
}

output "private_subnet_id" {
  value = join("", aws_subnet.private[*].id)
}
output "natip" {
  value = (aws_eip.nat_eip.*.id)
}
output "prodnatip" {
  value = join("", aws_eip.nat_eip_prod[*].id)
}
