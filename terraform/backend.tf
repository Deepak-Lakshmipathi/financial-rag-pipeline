terraform {
  backend "s3" {
    bucket         = "prog1-finrag-terraform-state"
    key            = "financial-rag/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}