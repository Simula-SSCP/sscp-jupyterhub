terraform {
  required_version = ">= 1.7"
  backend "gcs" {
    bucket = "tf-state-sscp-2025"
    prefix = "tofu/state"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.33.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36.0"
    }
  }
}
data "google_client_config" "provider" {}

provider "google" {
  project = "sscp-2025"
  region  = "europe-west1"
  zone    = "europe-west1-b"
}

locals {
  # gke_version  = "1.27.8-gke.1067004"
  cluster_name = "sss"
  location     = data.google_client_config.provider.region # regional cluster
  # region       = data.google_client_config.provider.region
  # zone = data.google_client_config.provider.zone

}

resource "google_artifact_registry_repository" "repo" {
  location      = local.location
  repository_id = "sss"
  description   = "summer school container registry"
  format        = "DOCKER"
}

resource "google_container_cluster" "cluster" {
  name     = local.cluster_name
  location = local.location

  enable_autopilot = true

  maintenance_policy {
    # times are UTC
    # allow maintenance only on weekends,
    # from late Western Friday night (10pm Honolulu UTC-10)
    # to early Eastern Monday AM (4am Sydney UTC+11)
    recurring_window {
      start_time = "2021-01-02T08:00:00Z"
      end_time   = "2021-01-03T17:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }

}

output "cluster_name" {
  value = google_container_cluster.cluster.name
}

provider "kubernetes" {
  host  = "https://${google_container_cluster.cluster.endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    google_container_cluster.cluster.master_auth[0].cluster_ca_certificate,
  )
}

# resource "kubernetes_namespace" "cert-manager" {
#   metadata {
#     name = "cert-manager"
#   }
#   depends_on = [google_container_cluster.cluster]
# }

resource "kubernetes_namespace" "hub" {
  metadata {
    name = "jupyterhub"
  }
  depends_on = [google_container_cluster.cluster]
}

provider "helm" {
  kubernetes {
    host  = "https://${google_container_cluster.cluster.endpoint}"
    token = data.google_client_config.provider.access_token
    cluster_ca_certificate = base64decode(
      google_container_cluster.cluster.master_auth[0].cluster_ca_certificate,
    )
  }
}

# resource "helm_release" "cert-manager" {
#   name       = "cert-manager"
#   namespace  = "cert-manager"
#   repository = "https://charts.jetstack.io"
#   chart      = "cert-manager"
#   version    = "v1.17.2"
#   set {
#     name  = "crds.enabled"
#     value = "true"
#   }
#   set {
#     name  = "ingressShim.defaultIssuerName"
#     value = "letsencrypt-prod"
#   }
#   set {
#     name  = "ingressShim.defaultIssuerKind"
#     value = "ClusterIssuer"
#   }
# }
