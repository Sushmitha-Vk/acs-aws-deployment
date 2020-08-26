output "rds-endpoint" {
  value = "${aws_rds_cluster.default.endpoint}:${aws_rds_cluster.default.port}"
}
