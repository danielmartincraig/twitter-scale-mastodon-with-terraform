# Backend service module

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-arm64"]
  }
}

# EC2 instances for backend service
resource "aws_instance" "zookeeper" {
  count = var.instance_count

  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.iam_instance_profile
  key_name               = var.ssh_key_name
  monitoring             = var.enable_detailed_monitoring

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    server_id                       = count.index + 1
    zookeeper_service_unit          = file("${path.root}/systemd/zookeeper.service")
    zookeeper_config                = file("${path.root}/zoo.cfg")
    rama_config                     = file("${path.root}/rama.yaml")
    deploy_bucket                   = var.deploy_bucket
    rama_s3_key                     = var.rama_s3_key
    aws_region                      = var.aws_region
    rama_conductor_service_unit     = file("${path.root}/systemd/rama-conductor.service")
    rama_supervisor_service_unit    = file("${path.root}/systemd/rama-supervisor.service")
    mastodon_api_service_unit       = file("${path.root}/systemd/mastodon-api.service")
    git_sha                         = var.git_sha
  })

  tags = {
    Name        = "${var.environment}-backend-service-${count.index + 1}"
    Environment = var.environment
    Component   = "backend-service"
    ManagedBy   = "terraform"
    ServerID    = count.index + 1
  }

  lifecycle {
    create_before_destroy = true
  }
}
