locals {
  ecs_task_execution_iam_name = "${var.name}-ecs-task-execution"
  ecs_task_iam_name           = "${var.name}-ecs-task"
  enabled_ecs_task_execution  = var.enabled && var.create_ecs_task_execution_role ? 1 : 0
  enabled_ecs_task            = var.enabled && var.create_ecs_task_role ? 1 : 0
  security_groups             = compact(concat(["${aws_security_group.ecs_default.id}"], var.security_groups))
}

data "aws_iam_policy_document" "ecs_task_execution_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
data "aws_iam_policy_document" "ecs_task_role_assume_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "ecs-tasks.amazonaws.com",
      ]
    }
  }
}

data "aws_iam_policy" "ecs_task_execution" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


resource "aws_iam_policy" "ecs_task_execution" {
  count = local.enabled_ecs_task_execution

  name   = local.ecs_task_execution_iam_name
  policy = data.aws_iam_policy.ecs_task_execution.policy
  path   = var.iam_path
}

resource "aws_iam_role" "ecs_task_execution" {
  count = local.enabled_ecs_task_execution

  name               = local.ecs_task_execution_iam_name
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role_policy.json
  path               = var.iam_path
  tags               = merge({ "Name" = local.ecs_task_execution_iam_name }, var.tags)
}

resource "aws_iam_role" "ecs_task_role" {
  count              = local.enabled_ecs_task
  name               = local.ecs_task_iam_name
  assume_role_policy = data.aws_iam_policy_document.ecs_task_role_assume_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  count = local.enabled_ecs_task_execution

  role       = aws_iam_role.ecs_task_execution[0].name
  policy_arn = aws_iam_policy.ecs_task_execution[0].arn
}

resource "aws_ecs_task_definition" "default" {
  count                    = var.enabled ? 1 : 0
  family                   = var.name
  task_role_arn            = var.create_ecs_task_role ? join("", aws_iam_role.ecs_task_role.*.arn) : var.ecs_task_role_arn
  execution_role_arn       = var.create_ecs_task_execution_role ? join("", aws_iam_role.ecs_task_execution.*.arn) : var.ecs_task_execution_role_arn
  container_definitions    = var.container_definitions
  cpu                      = var.cpu
  memory                   = var.memory
  requires_compatibilities = var.requires_compatibilities
  network_mode             = "awsvpc"
  tags                     = merge({ "Name" = var.name }, var.tags)
}

resource "aws_security_group" "ecs_default" {
  name   = "${var.name}-default"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
