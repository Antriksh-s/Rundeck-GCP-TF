terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

# Enable Compute Engine API automatically
resource "google_project_service" "compute_api" {
  project            = var.gcp_project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# Firewall Rule allowing Rundeck Web UI on port 4440
resource "google_compute_firewall" "allow_rundeck" {
  name       = "allow-rundeck-4440"
  network    = "default"
  depends_on = [google_project_service.compute_api]

  allow {
    protocol = "tcp"
    ports    = ["4440"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["rundeck-server"]
}

# Compute Engine Instance
resource "google_compute_instance" "rundeck_vm" {
  name         = "rundeck-poc-vm"
  machine_type = var.machine_type
  zone         = var.gcp_zone
  tags         = ["rundeck-server"]
  depends_on   = [google_project_service.compute_api]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default"
    access_config {
      // Ephemeral public IP
    }
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e

    # Update system and install Docker & Docker Compose
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Fetch External IP
    PUBLIC_IP=$(curl -s -4 ifconfig.me || curl -s api.ipify.org)

    mkdir -p /opt/rundeck
    cat << 'DOCKERCOMPOSE' > /opt/rundeck/docker-compose.yml
    version: '3.8'

    services:
      database:
        image: postgres:15-alpine
        container_name: rundeck-db
        environment:
          POSTGRES_DB: rundeck
          POSTGRES_USER: rundeck
          POSTGRES_PASSWORD: rundeckpassword
        volumes:
          - postgres_data:/var/lib/postgresql/data
        healthcheck:
          test: ["CMD-SHELL", "pg_isready -U rundeck"]
          interval: 5s
          timeout: 5s
          retries: 5

      rundeck:
        image: rundeck/rundeck:5.1.0
        container_name: rundeck-server
        restart: always
        ports:
          - "4440:4440"
        environment:
          RUNDECK_GRAILS_URL: http://$${PUBLIC_IP}:4440
          RUNDECK_DATABASE_DRIVER: org.postgresql.Driver
          RUNDECK_DATABASE_URL: jdbc:postgresql://database:5432/rundeck
          RUNDECK_DATABASE_USERNAME: rundeck
          RUNDECK_DATABASE_PASSWORD: rundeckpassword
        depends_on:
          database:
            condition: service_healthy

      target-node:
        image: ubuntu:22.04
        container_name: target-node
        command: >
          sh -c "apt-get update && apt-get install -y openssh-server python3 sudo &&
                 mkdir /var/run/sshd && echo 'root:rootpass' | chpasswd &&
                 sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config &&
                 /usr/sbin/sshd -D"

    volumes:
      postgres_data:
    DOCKERCOMPOSE

    # Replace variable with actual public IP
    sed -i "s/\$${PUBLIC_IP}/$PUBLIC_IP/g" /opt/rundeck/docker-compose.yml

    # Launch Docker Compose Stack
    cd /opt/rundeck
    docker compose up -d
  EOF

  service_account {
    scopes = ["cloud-platform"]
  }
}

output "rundeck_url" {
  value       = "http://${google_compute_instance.rundeck_vm.network_interface[0].access_config[0].nat_ip}:4440"
  description = "Access URL for the Rundeck Web Console"
}