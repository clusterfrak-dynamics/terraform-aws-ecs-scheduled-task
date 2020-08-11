locals {
  enabled_sns_topic = var.enabled && var.create_sns_topic ? 1 : 0
}

resource "aws_sns_topic" "ecs_cfn_sns_topic" {
  count       = local.enabled_sns_topic
  name_prefix = var.name
}
