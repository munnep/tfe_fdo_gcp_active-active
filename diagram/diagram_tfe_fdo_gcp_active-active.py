from diagrams import Cluster, Diagram
from diagrams.onprem.compute import Server
from diagrams.gcp.compute import ComputeEngine
from diagrams.gcp.database import SQL, Memorystore
from diagrams.gcp.storage import Filestore
from diagrams.gcp.network import LoadBalancing

# Variables
title = "VPC with 1 public subnet for the TFE client \n and 1 private subnet for the TFE instances \nservices subnet for PostgreSQL and Redis"
outformat = "png"
filename = "diagram_tfe_fdo_gcp_active-active"
direction = "TB"


with Diagram(
    name=title,
    direction=direction,
    filename=filename,
    outformat=outformat,
) as diag:
    # Non Clustered
    user = Server("user")

    # Cluster 
    with Cluster("gcp"):
        with Cluster("vpc"):
          with Cluster("subnet_public1"):
            ec2_client = ComputeEngine("Client_machine")
            loadbalancer = LoadBalancing("Load Balancer")
          with Cluster("subnet_private1"):
            ec2_tfe_server = ComputeEngine("TFE_server")  
          with Cluster("subnet_services"):
            postgresql = SQL("PostgreSQL database")
            redis = Memorystore("Redis database")
        bucket = Filestore("TFE bucket")   
               
    # Diagram

    user >> loadbalancer >> ec2_tfe_server >> [postgresql, 
                                               redis,
                                               bucket]
   
    user >> ec2_client
diag
