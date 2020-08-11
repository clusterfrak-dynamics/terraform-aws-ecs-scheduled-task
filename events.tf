locals {
  ecs_events_iam_name = "${var.name}-ecs-events"
  enabled_ecs_events  = var.enabled && var.create_ecs_events_role ? 1 : 0
}

data "aws_iam_policy_document" "ecs_events_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_events_policy" {
  statement {
    effect = "Allow"
    actions = [
      "states:StartExecution"
    ]
    resources = [
      aws_sfn_state_machine.ecs_sfn_state_machine[0].arn
    ]
  }
}

resource "aws_iam_policy" "ecs_events" {
  count  = local.enabled_ecs_events
  name   = local.ecs_events_iam_name
  policy = data.aws_iam_policy_document.ecs_events_policy.json
  path   = var.iam_path
}

resource "aws_iam_role" "ecs_events" {
  count = local.enabled_ecs_events

  name               = local.ecs_events_iam_name
  assume_role_policy = data.aws_iam_policy_document.ecs_events_assume_role_policy.json
  path               = var.iam_path
  description        = var.description
  tags               = merge({ "Name" = local.ecs_events_iam_name }, var.tags)
}

resource "aws_iam_role_policy_attachment" "ecs_events" {
  count      = local.enabled_ecs_events
  role       = aws_iam_role.ecs_events[0].name
  policy_arn = aws_iam_policy.ecs_events[0].arn
}

resource "aws_cloudwatch_event_rule" "default" {
  count = var.enabled ? 1 : 0

  name        = var.name
  description = var.description
  is_enabled  = var.is_enabled

  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "default" {
  count = var.enabled ? 1 : 0

  target_id = var.name
  arn       = aws_sfn_state_machine.ecs_sfn_state_machine[0].arn
  rule      = aws_cloudwatch_event_rule.default[0].name
  role_arn  = var.create_ecs_events_role ? join("", aws_iam_role.ecs_events.*.arn) : var.ecs_events_role_arn
}
