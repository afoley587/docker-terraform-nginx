/* The terraform settings 
 * Things like backend configuration, required providers,
 * etc. go in here
 * https://developer.hashicorp.com/terraform/language/settings
 */
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "2.23.0"
    }
  }
}

/* The docker provider settings 
 * In our case, we will use the docker unix socket
 * as our host. Full configuration parameters
 * are here
 * https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs
 */
provider "docker" {
  host = "unix:///var/run/docker.sock"
}

/* Our input variables. Note that we added constraints on our
 * variables using validation blocks.
 */
variable "external_port" {
  default     = 8080
  type        = number
  description = "The external port that our load balancer will listen on. Must be between 8000 and 12000."
  validation {
    condition     = 8000 < var.external_port && var.external_port < 12000
    error_message = "Port must be a number between 8000 and 12000."
  }
}

variable "num_server_apps" {
  default     = 5
  type        = number
  description = "The number of nginx apps to spin up. Must be between 1 and 10 (exclusive)."
  validation {
    condition     = 0 < var.num_server_apps && var.num_server_apps < 10
    error_message = "Number of apps must be a number between 1 and 10."
  }
}

/* Local variables to be used throughout the terraform code
 * Note that the nginx_base_path will expand to the current
 * directory that terraform is running in, plus ../docker.
 * server_block_arr uses a for loop to create an array 
 * of strings based on the name of our nginx container names.
 * For example:
 * server_block_arr = [
 *    "server nginx1",
 *    "server nginx2"
 * ]
 */
locals {
  nginx_base_path  = "${path.module}/../docker"
  server_block_arr = [for d in docker_container.nginx_apps : "server ${d.name}"]
}

/* Building our docker images with the docker_image resource
 * Note that we use another for loop in our triggers. We loop 
 * through each file in our nginx_base_path directory using the 
 * fileset method. We then create a sha1 sum of each file in there
 * using the filesha1, and join the array into a string using the 
 * join function.
 */
resource "docker_image" "nginx_app" {
  name = "nginxapp"

  triggers = {
    dir_sha1 = sha1(
      join(
        "",
        [for f in fileset(local.nginx_base_path, "*") : filesha1("${local.nginx_base_path}/${f}")]
      )
    )
  }

  build {
    path = local.nginx_base_path
    tag  = ["nginxapp:latest"]
    build_arg = {
      TEMPLATE_FILE : "nginx.app.conf.tmpl"
    }
  }
}

resource "docker_image" "nginx_lb" {
  name = "nginxlb"

  triggers = {
    dir_sha1 = sha1(
      join(
        "",
        [for f in fileset(local.nginx_base_path, "*") : filesha1("${local.nginx_base_path}/${f}")]
      )
    )
  }

  build {
    path = local.nginx_base_path
    tag  = ["nginxlb:latest"]
    build_arg = {
      TEMPLATE_FILE : "nginx.lb.conf.tmpl"
    }
  }
}


/* A docker network for each of our containers
 * to use. This way, they can all reach eachother
 * by hostname and it wont interfere with any
 * other containers on the system and nothing
 * will interfere with them.
 */
resource "docker_network" "nginx_network" {
  name = "nginx"
}

/* Now we deploy our docker containers. Note that the 
 * nginx_apps resource uses a count object. So if we
 * set num_server_apps to 8, we will get 8 containers
 * named nginx-0, nginx-1, ...., nginx-7. Each of 
 * them will then each have a unique message like
 * HELLO WORLD FROM 2.
 */
resource "docker_container" "nginx_apps" {
  count = var.num_server_apps
  name  = "nginx-${count.index}"
  image = docker_image.nginx_app.image_id
  env   = ["MESSAGE=HELLO WORLD FROM ${count.index}"]

  networks_advanced {
    name = docker_network.nginx_network.id
  }
}

resource "docker_container" "nginx_lb" {
  name  = "nginx-lb"
  image = docker_image.nginx_lb.image_id

  env = [
    "SERVERS=${join(";", local.server_block_arr)}",
  ]

  ports {
    external = var.external_port
    internal = "80"
  }

  networks_advanced {
    name = docker_network.nginx_network.id
  }
}