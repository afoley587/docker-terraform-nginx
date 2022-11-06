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

resource "docker_image" "nginx_app" {
  name = "nginxapp"
  
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset("${path.module}/../docker/nginx-app", "*") : filesha1("${path.module}/../docker/nginx-app/${f}")]))
  }

  build {
    path = "${path.module}/../docker/nginx-app"
    tag  = ["nginxapp:latest"]
  }
}

resource "docker_image" "nginx_lb" {
  name = "nginxlb"
  
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset("${path.module}/../docker/nginx-loadbalancer", "*") : filesha1("${path.module}/../docker/nginx-loadbalancer/${f}")]))
  }

  build {
    path = "${path.module}/../docker/nginx-loadbalancer"
    tag  = ["nginxlb:latest"]
  }
}

resource "docker_network" "nginx_network" {
  name = "nginx"
}

resource "docker_container" "nginx_hello_world" {
  name = "nginx-hello-world"
  image = docker_image.nginx_app.image_id
  env = ["MESSAGE=HELLO WORLD"]

  networks_advanced {
    name = docker_network.nginx_network.id
  }

}

resource "docker_container" "nginx_goodbye_world" {
  name = "nginx-goodbye-world"
  image = docker_image.nginx_app.image_id
  env = ["MESSAGE=GOODBYE WORLD"]

  networks_advanced {
    name = docker_network.nginx_network.id
  }

}

resource "docker_container" "nginx_lb" {
  name = "nginx-lb"
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