terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  project = "societatea-hermes"
}

resource "google_compute_network" "vaultwarden" {
  name = "vaultwarden"
}

resource "google_compute_instance" "vaultwarden" {
  name = "vaultwarden"
  machine_type = "e2-micro"
  zone = "us-central1-a"

  tags = ["http-server", "https-server"]

  boot_disk {
    initialize_params {
    image = "cos-cloud/cos-stable"
    size = 30
    }
  }

  network_interface {
    network = google_compute_network.vaultwarden.self_link
    access_config {
    }
  }

  metadata = {
    startup-script = file("startup.sh")
  }
  service_account {
    scopes = ["compute-rw"]
  }
}

resource "google_compute_firewall" "vaultwarden_http" {
  name = "vaultwarden-http"
  network = google_compute_network.vaultwarden.self_link

  allow {
    protocol = "tcp"
    ports = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags = ["http-server"]
}

resource "google_compute_firewall" "vaultwarden_https" {
  name = "vaultwarden-https"
  network = google_compute_network.vaultwarden.self_link

  allow {
    protocol = "tcp"
    ports = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags = ["https-server"]
}

output "vaultwarden_ip" {
  value = google_compute_instance.vaultwarden.network_interface.0.access_config.0.nat_ip
}