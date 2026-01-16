terraform {
  cloud {
    hostname     = "tfe91.hc-0ecd51335ae74f1089a9a431017.gcp.sbx.hashicorpdemo.com"
    organization = "test"

    workspaces {
      name = "test"
    }
  }
}
resource "null_resource" "namde" {
}