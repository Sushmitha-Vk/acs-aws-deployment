### URLs to be applied to alfresco-global.properties
locals {
  lb_url = "${var.alb-dns}"
  internal_lb_url = "${var.internal-nlb-dns}"
  db_url = "jdbc:${var.rds-engine}:\\/\\/${var.rds-endpoint}\\/${var.rds-name}?useUnicode=yes\\&characterEncoding=UTF-8\\&useSSL=false"
  mq_user = "${var.mq-user}"
  mq_password = "${var.mq-password}"
  mq_failover = "failover:(${var.mq-ssl-endpoint-1},${var.mq-ssl-endpoint-2})?timeout=30000"  

  elasticsearch_url = "${var.elasticsearch-url}"
  instance_name = "${var.resource-prefix}-${var.vpc-id}"
  alfresco_application_name = "${var.resource-prefix}-alfresco-solr-${var.autoscaling-group-image-id}"  
  search_application_name = "${var.resource-prefix}-search-solr-${var.autoscaling-group-image-id}"  

  solr_shard_method   = "${var.solr_shard_method}"
  solr_shard_size     = "${var.solr_shard_size}"
  solr_lsblk_name  = "nvme2n1" # NVMe based instance types device name for Rx EC2 instance type
  solr_device_name = "/dev/nvme2n1"  
  solr_mount_point = "/data/solr"
  ebs_block_device_name = "/dev/nvme1n1" # /dev/xvdb

}

### Alfresco with autoscaling ###
resource "aws_security_group" "alfresco-solr-sg" {
  name = "${var.resource-prefix}-solr-sg"
  description = "Alfresco instance security group"
  vpc_id = "${var.vpc-id}"

  ingress {
    from_port = "8080"
    to_port = "8080"
    protocol = "tcp"
    security_groups = ["${var.alb-sg-id}"]
    description = "Alfresco Tomcat"
  }

  ingress {
    from_port = "61617"
    to_port = "61617"
    protocol = "tcp"
    security_groups = ["${var.vpc-default-sg-id}"]
    description = "AmazonMQ"
  }

  ingress {
    from_port = "9090"
    to_port = "9090"
    protocol = "tcp"
    security_groups = ["${var.alb-sg-id}"]
    description = "Alfresco Zeppelin"
  }

  ingress {
    from_port = "8983"
    to_port = "8983"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Alfresco Solr"
  }

  ingress {
    from_port = "22"
    to_port = "22"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.resource-prefix}-alfresco-solr-sg"
    Environment = "${var.resource-prefix}"
    Owner = "${var.resource-owner}"
    Customer = "${var.resource-customer}"
  }
}

resource "aws_ebs_volume" "alfresco-solr-ebs-volume" {

  count = "${var.autoscaling-group-desired-capacity}"
  size  = "${var.solr-ebs-volume-size}"
  type  = "${var.solr-ebs-volume-type}"
  iops  = "${var.solr-ebs-volume-iops}"
  availability_zone = "${element(split(",",var.aws-availability-zones), 0)}"
 
  tags {
    Name  =  "${var.resource-prefix}-alfresco-solr-ebs-volume-${count.index}"
    Environment = "${var.resource-prefix}"
    Owner = "${var.resource-owner}"
    Customer = "${var.resource-customer}"
  }
}

# Launch configuration 
resource "aws_launch_configuration" "solr-lcfg" {
  count = "${var.autoscaling-group-desired-capacity}"
  name_prefix   = "${var.resource-prefix}-solr-lcfg-${count.index}-"
  image_id = "${var.autoscaling-group-image-id}"
  instance_type = "${var.autoscaling-group-instance-type}"
  iam_instance_profile = "${aws_iam_instance_profile.alfresco-solr-profile.id}"
  key_name = "${var.autoscaling-group-key-name}"
  security_groups = ["${aws_security_group.alfresco-solr-sg.id}"]

  # Create ebs volumes caching content store
  ebs_block_device {
    device_name           = "/dev/xvdb"
    volume_type           = "gp2"
    volume_size           = "${var.cachedcontent-ebs-volume-size}"
    delete_on_termination = true
    encrypted             = true
    iops                  = 0
    snapshot_id           = ""
    no_device             = false
  }
  user_data = <<EOF
#!/bin/bash
sudo su

# Log everything we do.
set -x
exec > /var/log/user-data.log 2>&1

ALFRESCO_HOME="/opt/alfresco-content-services"
INSIGHT_HOME="/opt/alfresco-search-services"
ALFRESCO_GLOBAL_PROPERTIES="$ALFRESCO_HOME/tomcat/shared/classes/alfresco-global.properties"

REGION=$(curl 169.254.169.254/latest/meta-data/placement/availability-zone/ | sed 's/[a-z]$//')
INSTANCE_ID=`curl http://169.254.169.254/latest/meta-data/instance-id`
VOLUME_ID="${element(aws_ebs_volume.alfresco-solr-ebs-volume.*.id, count.index)}"
DEVICE_NAME="${local.solr_device_name}"
MOUNT_POINT="${local.solr_mount_point}"
LSBLK_NAME="${local.solr_lsblk_name}"
EBS_BLOCK_DEVICE_NAME="${local.ebs_block_device_name}"

SOLR_SHARD_METHOD="${local.solr_shard_method}"
SOLR_SHARD_INSTANCE=${count.index}
SOLR_SHARD_SIZE=${local.solr_shard_size}
SOLR_SHARD_COUNT=${var.autoscaling-group-desired-capacity}
SOLR_SHARD_RANGE="$[SOLR_SHARD_INSTANCE * SOLR_SHARD_SIZE]-$[(SOLR_SHARD_INSTANCE + 1) * SOLR_SHARD_SIZE]"

# wait for ebs volume to be attached
while :
do
    # self-attach ebs volume
    aws --region $REGION ec2 attach-volume --volume-id $VOLUME_ID --instance-id $INSTANCE_ID --device /dev/xvdf

    if lsblk | grep $LSBLK_NAME; then
        echo "attached"
        break
    else
        sleep 5
    fi
done

# create fs if needed
if file -s $DEVICE_NAME | grep "$DEVICE_NAME: data"; then
    echo "creating fs"
    mkfs -t ext4 $DEVICE_NAME
fi

# mount it
mkdir -p $MOUNT_POINT
echo "$DEVICE_NAME       $MOUNT_POINT   ext4    defaults,nofail  0 2" >> /etc/fstab
echo "mounting"
mount -a
chown -R --verbose alfresco:alfresco $MOUNT_POINT

# Hostname with escaped '.' char for Sed
HOSTNAME=$(hostname | sed 's/[.]/\\./g')
# Path with escaped '/' char for Sed
DATA_DIR_ROOT=$(echo $MOUNT_POINT | sed 's/\//\\\//g')
# Setup JDK 11
sed -i "s/SOLR_JAVA_HOME=/SOLR_JAVA_HOME=\/opt\/alfresco-content-services\/jdk-11.0.1/g" $INSIGHT_HOME/solr.in.sh
ALFRESCO_SOLRCORE=$INSIGHT_HOME/solrhome/alfresco/conf/solrcore.properties
sed -i "s/solr[.]host=localhost/solr\.host=$HOSTNAME/g" $ALFRESCO_GLOBAL_PROPERTIES    
sed -i "s/solr[.]host=localhost/solr\.host=$HOSTNAME/g" $INSIGHT_HOME/solrhome/conf/shared.properties
sed -i "s/#SOLR_HOST=\"192[.]168[.]1[.]1\"/SOLR_HOST=\"$HOSTNAME\"/g" $INSIGHT_HOME/solr.in.sh
# Setup Alfresco Core
sed -i "s/^[#]*\s*data\.dir\.root=.*/data\.dir\.root=$DATA_DIR_ROOT/g" $ALFRESCO_SOLRCORE
sed -i "s/^[#]*\s*shard\.method=.*/shard\.method=$SOLR_SHARD_METHOD/g" $ALFRESCO_SOLRCORE
echo -e "\n" >> $ALFRESCO_SOLRCORE
echo "shard.instance=$SOLR_SHARD_INSTANCE" >> $ALFRESCO_SOLRCORE
echo "shard.range=$SOLR_SHARD_RANGE" >> $ALFRESCO_SOLRCORE
echo "shard.count=$SOLR_SHARD_COUNT" >> $ALFRESCO_SOLRCORE

cat
### set alfresco-global.properties ###
ALFRESCO_STAGEMONITOR_PROPERTIES=$ALFRESCO_HOME/tomcat/shared/classes/stagemonitor.properties
INSIGHT_STAGEMONITOR_PROPERTIES=$INSIGHT_HOME/solr/server/stagemonitor.properties
sed -i 's/MQ-USER/${local.mq_user}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/MQ-PASSWORD/${local.mq_password}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's|MQ-FAIL-OVER|${local.mq_failover}|g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/INTERNAL-LB-URL/${local.internal_lb_url}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/LB-URL/${local.lb_url}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/DB-DRIVER/${var.rds-driver}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/DB-USERNAME/${var.rds-username}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/DB-PASSWORD/${var.rds-password}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/DB-NAME/${var.rds-name}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/DB-URL/${local.db_url}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/S3-BUCKET-LOCATION/${var.s3-bucket-location}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/SOLR-SECURE-COMMS/${var.solr-secureComms}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/ENABLE-TIMESTAMP-PROPAGATION/${var.enable-timestamp-propagation}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/THUMBNAIL-GENERATE/${var.thumbnail-generate}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/S3-BUCKET-NAME/${var.resource-prefix}-repo-bucket/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/JOD-CONVERTER-PORT/${var.jod-converter-port}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/PDF-RENDERER-PORT/${var.pdf-renderer-port}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/IMAGE-MAGICK-PORT/${var.image-magick-port}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/TIKA-PORT/${var.tika-port}/g' $ALFRESCO_GLOBAL_PROPERTIES
sed -i 's/SHARED-FILE-STORE-PORT/${var.shared-file-store-port}/g' $ALFRESCO_GLOBAL_PROPERTIES    
sed -i 's/@@instance_name@@/${local.instance_name}/g' $ALFRESCO_STAGEMONITOR_PROPERTIES
sed -i 's/@@application_name@@/${local.alfresco_application_name}/g' $ALFRESCO_STAGEMONITOR_PROPERTIES
sed -i 's/@@elasticsearch_url@@/${local.elasticsearch_url}/g' $ALFRESCO_STAGEMONITOR_PROPERTIES
sed -i 's/@@instance_name@@/${local.instance_name}/g' $INSIGHT_STAGEMONITOR_PROPERTIES
sed -i 's/@@application_name@@/${local.search_application_name}/g' $INSIGHT_STAGEMONITOR_PROPERTIES
sed -i 's/@@elasticsearch_url@@/${local.elasticsearch_url}/g' $INSIGHT_STAGEMONITOR_PROPERTIES

# Mount EBS cache volume
mkfs -t ext4 $EBS_BLOCK_DEVICE_NAME
mkdir -p $INSIGHT_HOME/contentstore
mount $EBS_BLOCK_DEVICE_NAME $INSIGHT_HOME/contentstore
echo "$EBS_BLOCK_DEVICE_NAME       /opt/alfresco-search-services/contentstore    ext4    defaults,nofail 0 0" >> /etc/fstab
chown -R alfresco:alfresco $INSIGHT_HOME/contentstore

# Run Services
setenforce 0
systemctl enable tomcat
systemctl start tomcat
systemctl enable solr
systemctl start solr
systemctl enable zeppelin
systemctl start zeppelin    

EOF

  lifecycle {
    create_before_destroy = true
  }
}

# Auto scaling group #
resource "aws_autoscaling_group" "solr-asg" {
  count = "${var.autoscaling-group-desired-capacity}"
  name = "${element(aws_launch_configuration.solr-lcfg.*.id, count.index)}-solr-asg-${count.index}"
  launch_configuration = "${element(aws_launch_configuration.solr-lcfg.*.id, count.index)}"
  # vpc_zone_identifier = ["${var.private-subnet-1-id}", "${var.private-subnet-2-id}"]
  vpc_zone_identifier = ["${var.private-subnet-1-id}"]
  min_size = 1
  max_size = 1
  desired_capacity = 1
  target_group_arns = ["${aws_alb_target_group.zeppelin-target-group.arn}", "${aws_alb_target_group.solr-target-group.arn}", "${aws_alb_target_group.solr-ui-target-group.arn}"]

  tag {
    key = "Name"
    value = "${var.resource-prefix}-alfresco-solr-${count.index}"    
    propagate_at_launch = true
  }

  tag {
    key = "Environment"
    value = "${var.resource-prefix}"
    propagate_at_launch = true
  }

  tag {
    key = "Owner"
    value = "${var.resource-owner}"
    propagate_at_launch = true
  }

  tag {
    key = "Customer"
    value = "${var.resource-customer}"
    propagate_at_launch = true
  }    

  lifecycle {
    create_before_destroy = true
  }
}

# Connect applications to the Load Balancer
resource "aws_alb_target_group" "zeppelin-target-group" {
  name     = "${var.resource-prefix}-zeppelin-tg"
  port     = 9090
  protocol = "HTTP"
  vpc_id   = "${var.vpc-id}"
  deregistration_delay = 10

  health_check {
    interval            = 30
    path                = "/zeppelin"
    port                = "9090"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    protocol            = "HTTP"
    matcher             = "200,301,302"
  }  

 tags {
    Name = "${var.resource-prefix}-zeppelin-tg"
    Environment = "${var.resource-prefix}"
    Owner = "${var.resource-owner}"
    Customer = "${var.resource-customer}"
  }
}

resource "aws_alb_target_group" "solr-target-group" {
  name     = "${var.resource-prefix}-solr-tg"
  port     = 8983
  protocol = "TCP"
  vpc_id   = "${var.vpc-id}"
  stickiness = []

  deregistration_delay = 10

 tags {
    Name = "${var.resource-prefix}-solr-tg"
    Environment = "${var.resource-prefix}"
    Owner = "${var.resource-owner}"
    Customer = "${var.resource-customer}"
  }

}

resource "aws_alb_target_group" "solr-ui-target-group" {
  name     = "${var.resource-prefix}-solr-ui-tg"
  port     = 8983
  protocol = "HTTP"
  vpc_id   = "${var.vpc-id}"

  deregistration_delay = 10

  health_check {
    interval            = 30
    path                = "/solr"
    port                = "8983"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    protocol            = "HTTP"
    matcher             = "200,301,302"
  }  

  tags {
    Name = "${var.resource-prefix}-solr-ui-tg"
    Environment = "${var.resource-prefix}"
    Owner = "${var.resource-owner}"
    Customer = "${var.resource-customer}"
  }

}

resource "aws_alb_listener_rule" "solr-ui-rule" {
  listener_arn = "${var.alb-listener-arn}"
  priority     = 86

  action {
    type = "forward"
    target_group_arn = "${aws_alb_target_group.solr-ui-target-group.arn}"
  }
  condition {
    field  = "path-pattern"
    values = ["/solr*"]
  }
}

resource "aws_alb_listener_rule" "acs-zeppelin-rule" {
  listener_arn = "${var.alb-listener-arn}"
  priority     = 87

  action {
    type = "forward"
    target_group_arn = "${aws_alb_target_group.zeppelin-target-group.arn}"
  }
  condition {
    field  = "path-pattern"
    values = ["/zeppelin*"]
  }
}

# Define a listener
resource "aws_alb_listener" "solr-nlb-listener" {
  load_balancer_arn = "${var.internal-nlb-arn}"
  port              = "8983"
  protocol          = "TCP"

  default_action {
    target_group_arn = "${aws_alb_target_group.solr-target-group.arn}"
    type             = "forward"
  }
}

### Create a role to allow Alfresco to access S3 buckets ###
resource "aws_iam_instance_profile" "alfresco-solr-profile" {
  name = "${var.resource-prefix}-alfresco-solr-instance-profile"
  role = "${aws_iam_role.role.name}"
}

# Role for EC2 instance
resource "aws_iam_role" "role" {
  name = "${var.resource-prefix}-alfresco-solr-s3-role"
  assume_role_policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF
}

# Policy for S3 access
resource "aws_iam_policy" "s3-policy" {
  name        = "${var.resource-prefix}-alfresco-solr-s3-policy"
  description = "S3  policy"

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": "*"
        }
    ]
  }
  EOF
}

# Policy for code deploy
resource "aws_iam_policy" "sqs-sns-policy" {
  name        = "${var.resource-prefix}-alfresco-solr-sqs-sns-policy"
  description = "SQS SNS policy"

  policy = <<-EOF
  {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Effect": "Allow",
              "Resource": "*",
              "Action": [
                  "sqs:SendMessage",
                  "sqs:GetQueueUrl",
                  "sns:Publish"
              ]
          }
      ]
  }
  EOF
}

# Policy for volume attach
resource "aws_iam_policy" "ebs-policy" {
  name        = "${var.resource-prefix}-alfresco-solr-ebs-policy"
  description = "EBS Attach policy"

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AttachVolume",
                "ec2:DetachVolume"
            ],
            "Resource": [
                "arn:aws:ec2:*:*:volume/*",
                "arn:aws:ec2:*:*:instance/*"
            ]
        }
    ]
  }
  EOF
}

# Attach policies to role
resource "aws_iam_policy_attachment" "s3-policy-attach" {
  name       = "${var.resource-prefix}-policy-attachment"
  roles      = ["${aws_iam_role.role.name}"]
  policy_arn = "${aws_iam_policy.s3-policy.arn}"
}

resource "aws_iam_policy_attachment" "sqs-sns-policy-attach" {
  name       = "${var.resource-prefix}-policy-attachment"
  roles      = ["${aws_iam_role.role.name}"]
  policy_arn = "${aws_iam_policy.sqs-sns-policy.arn}"
}

resource "aws_iam_policy_attachment" "ebs-policy-attach" {
  name       = "${var.resource-prefix}-policy-attachment"
  roles      = ["${aws_iam_role.role.name}"]
  policy_arn = "${aws_iam_policy.ebs-policy.arn}"
}