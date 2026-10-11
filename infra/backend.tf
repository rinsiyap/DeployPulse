terraform {
  backend "s3" {
    bucket       = "deploypulse-tfstate-749680934466-us-east-2"
    key          = "deploypulse/dev/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
