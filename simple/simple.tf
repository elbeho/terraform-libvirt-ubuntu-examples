# variables that can be overriden
variable "hostname" { default = "simple" }
variable "domain" { default = "localdomain" }
variable "memoryMB" { default = 1024*1 }
variable "cpu" { default = 1 }
variable "image_path" { default = "../../matlab-rep/terraform/input/qcow/Rocky-8-GenericCloud-LVM-8.7-20230215.0.x86_64.qcow2" }


terraform { 
  required_version = ">= 0.12"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.1"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.3"
    }
  }
}

# instance the provider
provider "libvirt" {
  uri = "qemu:///system"
}

# fetch the latest ubuntu release image from their mirrors
resource "libvirt_volume" "os_image" {
  name   = "${var.hostname}-os-volume"
  pool = "default"
  source = "${var.image_path}"
  format = "qcow2"
}

# Use CloudInit ISO to add ssh-key to the instance
resource "libvirt_cloudinit_disk" "commoninit" {
  name = "${var.hostname}-commoninit.iso"
  pool = "default"
  #user_data = data.template_file.user_data.rendered
  #network_config = data.template_file.network_config.rendered
  user_data = data.cloudinit_config.config.rendered
}


data "cloudinit_config" "config" {
  gzip          = false
  base64_encode = false

  part {
    filename     = "cloud_init.yaml"
    content_type = "text/cloud-config"

    content = templatefile("${path.module}/cloud_init.cfg", {
       hostname = var.hostname
       fqdn = "${var.hostname}.${var.domain}"
    })
  }
  part {
    filename     = "network_config_dhcp.yaml"
    content_type = "text/cloud-config"

    content = file("${path.module}/network_config_dhcp.cfg")
  }

}


# Create the machine
resource "libvirt_domain" "domain-ubuntu" {
  name = var.hostname
  memory = var.memoryMB
  vcpu = var.cpu

  disk {
       volume_id = libvirt_volume.os_image.id
  }
  network_interface {
       network_name = "default"
  }

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  # IMPORTANT
  # Ubuntu can hang is a isa-serial is not present at boot time.
  # If you find your CPU 100% and never is available this is why
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type = "spice"
    listen_type = "address"
    autoport = "true"
  }
}


output "ips" {
  # show IP, run 'terraform refresh' if not populated
  value = libvirt_domain.domain-ubuntu.*.network_interface.0.addresses
}


