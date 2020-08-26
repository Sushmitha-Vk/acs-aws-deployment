### Resources tagging - use <initials>-<project>###
resource-prefix="nab-pe-1930"
resource-owner="PBF"
resource-customer="NAB"

### AWS variables ###
aws-region = "ap-southeast-2"
vpc-cidr = "10.0.0.0/16"
vpc-name = "nab-terraform-vpc"
aws-availability-zones = "ap-southeast-2a,ap-southeast-2b"

### Alfresco common variables ###
autoscaling-group-key-name = "nab-poc-v1"
s3-bucket-location = "ap-southeast-2"
cachedcontent-ebs-volume-size = "75"

### Stagemonitor properties ###
elasticsearch-url = "https:\\/\\/search-nab-srch-1930-uvd2d2ab63sorozntk5icjgomy.ap-southeast-2.es.amazonaws.com"

### Alfresco Repo variables ###
autoscaling-repo-group-image-id = "ami-0f7874e0842abf1f1"
autoscaling-repo-group-instance-type = "m5.2xlarge" # High speed instance with 8 CPU, 32 GiB Memory
autoscaling-repo-group-max-size = "6"
autoscaling-repo-group-desired-capacity = "6"
autoscaling-repo-group-min-size = "0"
repo-catalina-opts="-Xms2048M -Xmx8192M"
jod-converter-port=8090
pdf-renderer-port=8091
image-magick-port=8092
tika-port=8093
shared-file-store-port=8094
solr-secureComms="none"
enable-timestamp-propagation = "false"
thumbnail-generate = "false"

### Alfresco Solr variables ###
autoscaling-solr-group-image-id = "ami-0b4f570b736f5d73d"
autoscaling-solr-group-instance-type = "r5.2xlarge" # memory optimized instance 8 CPU, 64 GiB Memory
autoscaling-solr-group-desired-capacity = "21"
solr_shard_method   = "DB_ID_RANGE"
solr_shard_size     = "60000000"
solr-ebs-volume-size = "200"
solr-ebs-volume-type = "io1" # i.e. gp2, io1, standard, 
solr-ebs-volume-iops = "6000" # min=10 x volume-size, max=30 x volume size
jod-converter-port=8090
pdf-renderer-port=8091
image-magick-port=8092
tika-port=8093
shared-file-store-port=8094
solr-opts="-Dsolr.log.level=INFO"
solr-catalina-opts=""
solr-secureComms="none"
enable-timestamp-propagation = "false"
thumbnail-generate = "false"

### Transformation Service variables ###
autoscaling-ts-group-image-id = "ami-05e3b1029a89dc3df"
autoscaling-ts-group-instance-type = "m5.2xlarge"
autoscaling-ts-group-max-size = "5"
autoscaling-ts-group-desired-capacity = "1"
autoscaling-ts-group-min-size = "0"
ansible_alfresco_user= "alfresco"
ansible_libreoffice_port = "8090"
ansible_libreoffice_java_mem_opts = "-Xms512m -Xmx512m"
ansible_pdf_renderer_port = "8091"
ansible_pdf_renderer_java_mem_opts = "-Xms128m -Xmx128m"
ansible_imagemagick_port = "8092"
ansible_imagemagick_java_mem_opts = "-Xms256m -Xmx256m"
ansible_tika_port = "8093"
ansible_tika_java_mem_opts = "-Xms256m -Xmx256m"
ansible_shared_file_store_port = "8094"
ansible_shared_file_store_java_mem_opts ="-Xms256m -Xmx256m"
ansible_shared_file_store_path = "/opt/efs"
ansible_transform_router_port = "8095"
ansible_transform_router_java_mem_opts = "-Xms512m -Xmx512m"

### Database varaibles ###
rds-engine = "aurora-postgresql"
rds-engine-jdbc = "postgresql"
rds-engine-version = "10.7"
rds-instance-class = "db.r5.12xlarge" #3.1GHZ 24Core 48cpu
rds-instance-count = "1"
# rds-storage-size = "5"
# rds-storage-type = "gp2"
rds-username = "alfresco"
rds-password = "admin2019"
rds-driver = "org.postgresql.Driver"
rds-port = "5432"
rds-name = "alfresco"

### Bastion node ###
bastion-image-id="ami-08eb5f0ca3cdcb77e"

### ActiveMQ ###
mq-user = "alfresco"
mq-password = "!Alfresco2019"