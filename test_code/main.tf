terraform {
  cloud {
    hostname = "tfe91.aws.munnep.com"
    organization = "test"

    workspaces {
      name = "test"
    }
  }
}
resource "null_resource" "name" {
}