terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "2.23.0"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

locals {
  nginx_app_path = "${path.module}/../docker/nginx-app"
  nginx_lb_path  = "${path.module}/../docker/nginx-loadbalancer"
}

resource "docker_image" "nginx_app" {
  name = "nginxapp"

  triggers = {
    dir_sha1 = sha1(
      join(
        "",
        [for f in fileset(local.nginx_app_path, "*") : filesha1("${local.nginx_app_path}/${f}")]
      )
    )
  }

  build {
    path = local.nginx_app_path
    tag  = ["nginxapp:latest"]
  }
}

resource "docker_image" "nginx_lb" {
  name = "nginxlb"

  triggers = {
    dir_sha1 = sha1(
      join(
        "",
        [for f in fileset(local.nginx_lb_path, "*") : filesha1("${local.nginx_lb_path}/${f}")]
      )
    )
  }

  build {
    path = local.nginx_lb_path
    tag  = ["nginxlb:latest"]
  }
}

resource "docker_network" "nginx_network" {
  name = "nginx"
}

resource "docker_container" "nginx_hello_world" {
  name  = "nginx-hello-world"
  image = docker_image.nginx_app.image_id
  env   = ["MESSAGE=HELLO WORLD"]

  networks_advanced {
    name = docker_network.nginx_network.id
  }
}

resource "docker_container" "nginx_goodbye_world" {
  name  = "nginx-goodbye-world"
  image = docker_image.nginx_app.image_id
  env   = ["MESSAGE=GOODBYE WORLD"]

  networks_advanced {
    name = docker_network.nginx_network.id
  }
}

resource "docker_container" "nginx_lb" {
  name  = "nginx-lb"
  image = docker_image.nginx_lb.image_id

  env = [
    "SERVER_ONE=${docker_container.nginx_hello_world.name}",
    "SERVER_TWO=${docker_container.nginx_goodbye_world.name}"
  ]

  ports {
    external = "8080"
    internal = "80"
  }

  networks_advanced {
    name = docker_network.nginx_network.id
  }
}