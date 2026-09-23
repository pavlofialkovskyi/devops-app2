resource "aws_autoscaling_group" "app" {
  name                = "devops-app2-asg"
  min_size            = 1
  desired_capacity    = 1
  max_size            = 3
  vpc_zone_identifier = [aws_subnet.private_app_a.id, aws_subnet.private_app_b.id]

  health_check_type = "ELB"
  target_group_arns = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  tag {
    key                 = "Name"
    value               = "devops-app2"
    propagate_at_launch = true
  }
}