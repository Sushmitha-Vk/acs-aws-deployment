terraform {
  backend "s3" {
    # Replace this with your bucket name!
    bucket         = "nab-pe-terraform-acs-61-deployment"
    key            = "dpaul-srch-1930/terraform.tfstate"
    region         = "ap-southeast-2"
    # Replace this with your DynamoDB table name!
    # dynamodb_table = "acs-61-deployment-state-lock"
    encrypt        = false
  }
}

# Remote State data source
data "terraform_remote_state" "network" {
  backend = "s3"
  config {
    bucket         = "nab-pe-terraform-acs-61-deployment"
    key            = "dpaul-srch-1930/terraform.tfstate"
    region         = "ap-southeast-2"
  }
}