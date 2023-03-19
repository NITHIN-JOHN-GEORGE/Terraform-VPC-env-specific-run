locals {
  env = ["prod", "qa", "dev"]
}

data "aws_caller_identity" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

#----------vpc code block------------------------------

resource "aws_vpc" "vpc" {
  # count                = var.env == local.env ? 1 : 0
  count                = contains(local.env, var.env) ? 1 : 0
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge({
    ManagedBy = "terraform"
    Name      = "${var.vpc_name}-vpc"
    Env       = var.env
  "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  "kubernetes.io/cluster/${var.eks_cluster_name}" = "owned" }, var.vpc_tags)

}

#----------------Public subnet--------------------------------------

resource "aws_subnet" "public" {
  vpc_id                  = element(aws_vpc.vpc.*.id, count.index)
  count                   = length(var.public_subnets_cidr)
  cidr_block              = element(var.public_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true

  tags = merge({
    ManagedBy                                       = "terraform"
    subnets                                         = "public"
    Name                                            = "${var.vpc_name}-${element(var.availability_zones, count.index)}-public${count.index + 1}"
    Infra                                           = "Stormx-V2"
    Env                                             = var.env
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "owned"
    "karpenter.sh/discovery" = var.eks_cluster_name
    "kubernetes.io/role/elb" = 1 }, var.public_subnet_tags)

  depends_on = [aws_vpc.vpc]
}

#------internet-gateway | will be used by the public subnets-----------------------

resource "aws_internet_gateway" "ig" {
  count  = contains(local.env, var.env) ? 1 : 0
  vpc_id = element(aws_vpc.vpc.*.id, count.index)

  tags = {
    MangedBy = "terraform"
    Name     = "${var.vpc_name}-igw"
    Env      = var.env
  }
  depends_on = [aws_subnet.public]
}

#---------------Public subnets route table------------------------------------------

resource "aws_route_table" "public" {
  count  = contains(local.env, var.env) ? 1 : 0
  vpc_id = element(aws_vpc.vpc.*.id, count.index)

  dynamic "route" {
    for_each = var.public_route_table_routes
    content {
      cidr_block                = lookup(route.value, "cidr_block", null)
      ipv6_cidr_block           = lookup(route.value, "ipv6_cidr_block", null)
      egress_only_gateway_id    = lookup(route.value, "egress_only_gateway_id", null)
      gateway_id                = lookup(route.value, "gateway_id", null)
      instance_id               = lookup(route.value, "instance_id", null)
      nat_gateway_id            = lookup(route.value, "nat_gateway_id", null)
      network_interface_id      = lookup(route.value, "network_interface_id", null)
      transit_gateway_id        = lookup(route.value, "transit_gateway_id", null)
      vpc_endpoint_id           = lookup(route.value, "vpc_endpoint_id", null)
      vpc_peering_connection_id = lookup(route.value, "vpc_peering_connection_id", null)
    }
  }

  tags = {
    MangedBy    = "terraform"
    Name        = "${var.vpc_name}-public-route-table"
    Environment = var.env
  }
  depends_on = [aws_internet_gateway.ig]
}

#---------------route for public route table to internet gateway---------------------(default route)------------
locals {
  public_route_cidr = ["0.0.0.0/0"]
}

resource "aws_route" "default_public_internet_gateway_route" {
  count                  = length(local.public_route_cidr)
  route_table_id         = element(aws_route_table.public.*.id, count.index)
  destination_cidr_block = element(local.public_route_cidr, count.index)
  gateway_id             = element(aws_internet_gateway.ig.*.id, count.index)
  depends_on             = [aws_route_table.public]
}

#---------------Associate the public route table to public subnets---------------------------------------

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = element(aws_route_table.public.*.id, count.index)
  depends_on     = [aws_route.default_public_internet_gateway_route]
}

#---------Private subnets--------------------------------------------

resource "aws_subnet" "private" {
  vpc_id                  = element(aws_vpc.vpc.*.id, count.index)
  count                   = length(var.private_subnets_cidr)
  cidr_block              = element(var.private_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = false

  tags = merge({
    MangedBy                                        = "terraform"
    subnets                                         = "private"
    Name                                            = "${var.vpc_name}-${element(var.availability_zones, count.index)}-private${count.index + 1}"
    Env                                             = var.env
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "owned"
    "karpenter.sh/discovery" = var.eks_cluster_name
    "kubernetes.io/role/internal-elb"               = 1
  }, var.private_subnet_tags)

  depends_on = [aws_vpc.vpc]
}

#-----elastic ip for the nat gateway | nat static ip-----------------------------------------

resource "aws_eip" "nat_eip" {
  count      = var.env != "prod" && contains(local.env, var.env) ? 1 : 0
  vpc        = true
  depends_on = [aws_internet_gateway.ig]
  tags       = {
    MangedBy = "terraform"
    Name     = "${var.vpc_name}-nat_eip"
    Env      = var.env
  }
}

#-----conditional block----elastic ip for the prod env nat gateway | nat static ip------------------

resource "aws_eip" "nat_eip_prod" {
  count      = var.env == "prod" && contains(local.env, var.env) ? length(var.availability_zones) : 0
  vpc        = true
  depends_on = [aws_internet_gateway.ig]
  tags       = {
    MangedBy = "terraform"
    Name     = "${var.vpc_name}-nat_eip"
    Env      = var.env
  }
}

#----------------Nat gateway for the private subnets----------------------------------------------

resource "aws_nat_gateway" "nat" {
  count         = var.env != "prod" && contains(local.env, var.env) ? 1 : 0
  allocation_id = element(aws_eip.nat_eip.*.id, count.index)
  subnet_id     = element(aws_subnet.public.*.id, 0)
  depends_on    = [aws_internet_gateway.ig]
  tags = {
    MangedBy = "terraform"
    Name     = "${var.vpc_name}-nat"
    Env      = var.env
  }
}

#--------conditional block------production environment -Nat gateway-------------------------------

resource "aws_nat_gateway" "prodnat" {
  count         = var.env == "prod" && contains(local.env, var.env) ? length(var.availability_zones) : 0
  allocation_id = element(aws_eip.nat_eip_prod.*.id, count.index)
  subnet_id     = element(aws_subnet.public.*.id, count.index)
  depends_on    = [aws_internet_gateway.ig]
  tags = {
    MangedBy = "terraform"
    Name     = "${var.vpc_name}-${element(var.availability_zones, count.index)}-nat${count.index + 1}"
    Env      = var.env
  }
}

#--------------Private subnets route table-----------------------------------------------------

resource "aws_route_table" "private" {
  count  = var.env != "prod" && contains(local.env, var.env) ? 1 : 0
  vpc_id = element(aws_vpc.vpc.*.id, count.index)

  dynamic "route" {
    for_each = var.private_route_table_routes
    content {
      ipv6_cidr_block           = lookup(route.value, "ipv6_cidr_block", null)
      egress_only_gateway_id    = lookup(route.value, "egress_only_gateway_id", null)
      gateway_id                = lookup(route.value, "gateway_id", null)
      instance_id               = lookup(route.value, "instance_id", null)
      nat_gateway_id            = lookup(route.value, "nat_gateway_id", null)
      network_interface_id      = lookup(route.value, "network_interface_id", null)
      transit_gateway_id        = lookup(route.value, "transit_gateway_id", null)
      vpc_endpoint_id           = lookup(route.value, "vpc_endpoint_id", null)
      vpc_peering_connection_id = lookup(route.value, "vpc_peering_connection_id", null)
    }
  }

  tags = {
    MangedBy    = "terraform"
    Name        = "${var.vpc_name}-private-route-table"
    Environment = var.env
  }
}

#--------------------------conditional block----private route table for prod only----------------------------

resource "aws_route_table" "prod_private" {
  count  = var.env == "prod" && contains(local.env, var.env) ? length(var.availability_zones) : 0
  vpc_id = element(aws_vpc.vpc.*.id, count.index)

  dynamic "route" {
    for_each = var.private_route_table_routes
    content {
      ipv6_cidr_block           = lookup(route.value, "ipv6_cidr_block", null)
      egress_only_gateway_id    = lookup(route.value, "egress_only_gateway_id", null)
      gateway_id                = lookup(route.value, "gateway_id", null)
      instance_id               = lookup(route.value, "instance_id", null)
      nat_gateway_id            = lookup(route.value, "nat_gateway_id", null)
      network_interface_id      = lookup(route.value, "network_interface_id", null)
      transit_gateway_id        = lookup(route.value, "transit_gateway_id", null)
      vpc_endpoint_id           = lookup(route.value, "vpc_endpoint_id", null)
      vpc_peering_connection_id = lookup(route.value, "vpc_peering_connection_id", null)
    }
  }

  tags = {
    MangedBy    = "terraform"
    Name        = "${var.vpc_name}-${element(var.availability_zones, count.index)}-route-table${count.index + 1}"
    Environment = var.env
  }
}

#------------------route for private route table to nat gateway- (default route)------------------------

locals {
  private_route_cidr = ["0.0.0.0/0","0.0.0.0/0","0.0.0.0/0"]
}

resource "aws_route" "default_route_nat_gateway" {
  count                  = var.env != "prod" && contains(local.env, var.env) ? length(var.private_subnets_cidr) : 0
  route_table_id         = element(aws_route_table.private.*.id, count.index)
  destination_cidr_block = element(local.private_route_cidr, count.index)
  nat_gateway_id         = element(aws_nat_gateway.nat.*.id, count.index)
}

#---------conditional block---------route for private route table to prod Nat gateway only-------------------------

resource "aws_route" "default_prod_route_nat_gateway" {
  count                  = var.env == "prod" && contains(local.env, var.env) ? length(var.private_subnets_cidr) : 0
  route_table_id         = element(aws_route_table.prod_private.*.id, count.index)
  destination_cidr_block = element(local.private_route_cidr, count.index)
  nat_gateway_id         = element(aws_nat_gateway.prodnat.*.id, count.index)
}

#-------------Associate the private route table to private subnets-------------------

resource "aws_route_table_association" "private" {
  count          = var.env != "prod" && contains(local.env, var.env) ? length(var.private_subnets_cidr) : 0
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

#----------conditional block Associate the private prod route table to prod private subnets-------------------

resource "aws_route_table_association" "prod_private" {
  count          = var.env == "prod" && contains(local.env, var.env) ? length(var.private_subnets_cidr) : 0
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.prod_private.*.id, count.index)
}

#-------conditional block----aws flow log with s3 bucket  -----------------------------

resource "aws_flow_log" "vpc_flowlog" {
  count                = var.vpc_flowlog == true && contains(local.env, var.env) && var.vpc_flowlog_destination_type == "s3" ? 1 : 0
  log_destination      = element(aws_s3_bucket.vpc_flowlog_bucket.*.arn, count.index)
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = element(aws_vpc.vpc.*.id, count.index)
  destination_options {
    file_format        = "parquet"
    per_hour_partition = true
  }
  tags = {
    MangedBy = "terraform"
    VPC_Name = "${var.vpc_name}-vpc"
    Name     = "${var.vpc_name}-vpc-flowlog"
    Env      = var.env
    log_destination  = "s3"
  }
  depends_on = [aws_s3_bucket.vpc_flowlog_bucket]
}

#---------conditional block -S3 bucket for vpc flow log ----------

resource "aws_s3_bucket" "vpc_flowlog_bucket" {
  count  = var.vpc_flowlog == true && contains(local.env, var.env) && var.vpc_flowlog_destination_type == "s3" ? 1 : 0
  bucket = "${var.vpc_name}-vpc-flowlog-bucket-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags = {
    Name = "${var.vpc_name}-vpc-flowlog-bucket-${data.aws_caller_identity.current.account_id}"
    MangedBy = "terraform"
    Env  = var.env
  }
  depends_on = [aws_subnet.private]
}

#-------conditional block acl--make s3 bucket private --------------

resource "aws_s3_bucket_acl" "vpc_flowlog_bucket_acl" {
  count  = var.vpc_flowlog == true && contains(local.env, var.env) && var.vpc_flowlog_destination_type == "s3" ? 1 : 0
  bucket     = element(aws_s3_bucket.vpc_flowlog_bucket.*.id, count.index)
  acl        = "private"
  depends_on = [aws_s3_bucket.vpc_flowlog_bucket]
}

#---------conditional block ---s3 bucket versioning block---(by default not enabled)-------

resource "aws_s3_bucket_versioning" "vpc_flowlog_bucket_versioning" {
  count  = var.vpc_flowlog == true && contains(local.env, var.env) && var.vpc_flowlog_destination_type == "s3" ? 1 : 0
  bucket = element(aws_s3_bucket.vpc_flowlog_bucket.*.id, count.index)
  versioning_configuration {
    status = "Disabled"
  }
  depends_on = [aws_s3_bucket.vpc_flowlog_bucket]
}

#--------conditional block----s3 bucket lifecycle policy-----------

resource "aws_s3_bucket_lifecycle_configuration" "vpc_flowlog_bucket_lifecycle" {
  count  = var.vpc_flowlog == true && contains(local.env, var.env) && var.vpc_flowlog_destination_type == "s3" ? 1 : 0
  bucket = element(aws_s3_bucket.vpc_flowlog_bucket.*.id, count.index)
  rule {
    id = "rule-1"
    expiration {
      days = var.vpc_flowlog_bucket_retention
    }
    status = "Enabled"
  }
  depends_on = [aws_s3_bucket.vpc_flowlog_bucket]
}

#---------conditional block------AWS VPC flow log with cloud-Watch--log group----------------------------------

resource "aws_flow_log" "vpc_flowlog_Cloudwatch" {
  count           = var.vpc_flowlog == true && contains(local.env, var.env) && var.vpc_flowlog_destination_type == "cloudwatch_log_group" ? 1 : 0
  iam_role_arn    = element(aws_iam_role.vpcflow_log_group_role.*.arn, count.index)
  log_destination = element(aws_cloudwatch_log_group.vpc_flowlog_loggroup.*.arn, count.index)
  traffic_type    = "ALL"
  vpc_id          = element(aws_vpc.vpc.*.id, count.index)
  tags = {
    MangedBy = "terraform"
    VPC_Name = "${var.vpc_name}-vpc"
    Name     = "${var.vpc_name}-vpc-flowlog"
    Env      = var.env
    log_destination  = "aws_cloudwatch_log_group"
  }
  depends_on      = [aws_cloudwatch_log_group.vpc_flowlog_loggroup]
}

#-------conditional block cloud watch log group-------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flowlog_loggroup" {
  count           = var.vpc_flowlog == true && contains(local.env, var.env) && var.vpc_flowlog_destination_type == "cloudwatch_log_group" ? 1 : 0
  name            = "${var.vpc_name}-flow-log-group"
  tags = {
    MangedBy = "terraform"
    VPC_Name = "${var.vpc_name}-vpc"
    Name     = "${var.vpc_name}-flow-log-group"
    Env      = var.env
  }
  depends_on = [aws_iam_role.vpcflow_log_group_role]

}

#--------conditional block iam role for cloud watch log group ------------------------

resource "aws_iam_role" "vpcflow_log_group_role" {
  count           = var.vpc_flowlog == true && contains(local.env, var.env) && var.vpc_flowlog_destination_type == "cloudwatch_log_group" ? 1 : 0
  name  = "vpcflow_log_group_role"

  assume_role_policy = jsonencode({
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    },
  ]
  tags = {
    MangedBy = "terraform"
    VPC_Name = "${var.vpc_name}-vpc"
    Name     = "vpcflow_log_group_role"
    Env      = var.env
    used_by  = "vpcflow_log_group_role"
  }
})

  depends_on         = [aws_subnet.private]
}

#-------conditional block iam role policy for vpc flow log  cloud watch log group-------- 

resource "aws_iam_role_policy" "vpc_flowloggroup_role_policy" {
  count           = var.vpc_flowlog == true && contains(local.env, var.env) && var.vpc_flowlog_destination_type == "cloudwatch_log_group" ? 1 : 0
  name  = "vpcflow_log_group_iam_role_policy"
  role  = element(aws_iam_role.vpcflow_log_group_role.*.id, count.index)

  policy     = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
depends_on         = [aws_iam_role.vpcflow_log_group_role]
}

#----------default vpc network acl block--------------------

resource "aws_network_acl" "default_network_acl" {
  count = contains(local.env, var.env) ? 1 : 0
  vpc_id = element(aws_vpc.vpc.*.id, count.index)
  subnet_ids = [
  coalesce(element(aws_subnet.private.*.id, 0), ""),
  coalesce(element(aws_subnet.private.*.id, 1), ""),
  coalesce(element(aws_subnet.private.*.id, 2), ""),
  coalesce(element(aws_subnet.public.*.id, 0), ""),
  coalesce(element(aws_subnet.public.*.id, 1), ""),
  coalesce(element(aws_subnet.public.*.id, 2), "")
  ]
    ingress{
      from_port   = 1024   
      to_port     = 65535    
      protocol    = "tcp"
      cidr_block  = "0.0.0.0/0"
      action      = "allow"
      rule_no      = 500
    }
  
  egress{
      from_port   = 0    # allow  from all ports
      to_port     = 0   # allow  to all ports
      protocol    = "-1" # allow all protocols
      cidr_block  = "0.0.0.0/0"
      action      = "allow"
      rule_no      = 100

     }
  
  tags = {
    Name = "${var.vpc_name}-default_network_acl"
    MangedBy = "terraform"
    VPC_Name = "${var.vpc_name}-vpc"
    Env      = var.env
  }
  
}
