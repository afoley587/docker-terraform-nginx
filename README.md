# Blog

This blog post is for the new SRE or Cloud Developer who has heard
of terraform, but is hesitant to create an AWS account or GCP account
because of the possibly incurred costs or it just seems daunting. First, 
let me say, that the aforementioned cloud providers have amazing free
tiers, and I encourage anyone who is curious to sign up for them and begin
playing around with them!

But I also understand it can be somewhat daunting.

This post is going to show you how you can still get pretty proficient with
terraform, but all on localhost (using docker to fake a cloud).

Our project today will be using terraform to:

* Create some docker images
* Create an NGINX Load balancer (akin to an AWS Load Balancer)
* Create two NGINX apps (akin to AWS EC2 Instances)
* Create a docker network (akin to VPC)

And, along the way, we will be going over some fun tips and tricks.

So lets get started.

# Project Layout

First, all code in this blog post is hosted [here](https://github.com/afoley587/docker-terraform-nginx). The directory
layout is pretty simple, anything docker related goes in the `docker`
directory, and anything related to terraform goes in the `terraform` directory.

# Docker

Now, lets get to building our images. We said previously that we are going to
have a few NGINX components running:

1. A load balancer
2. Some web apps

Now, this isn't an NGINX tutorial, so we are going to focus more on the docker 
side of the house. Our Dockerfile is super small and is actually shared across both
the load balancer and the apps. Let's walk through it line-by-line.

The file, in its entirety is:
```shell
# Pull image from docker hub
FROM nginx:1.23.2-alpine

# Create a build argument that will dictate
# which template we copy into the container
# (the app one or the load balancer one)
ARG TEMPLATE_FILE

# Copy the template in
COPY ./$TEMPLATE_FILE /nginx.conf.template

# Copy the entrypoint in
COPY ./entrypoint.sh /entrypoint.sh

# Set entrypoint as runnable
RUN chmod +x /entrypoint.sh

# Set entrypoint.sh as entrypoint command for
# the container
ENTRYPOINT ["/entrypoint.sh"]
```

So, we:

* Pull an image from dockerhub
* Create a build argument that we can pass to the docker daemon
* Copy a template from our machine into the docker image
* Copy a shell script from our machine into the docker image
* Mark the shell script as runnable
* Mark the shell script as the entrypoint to the container

By having the build argument, we can have one dockerfile for both our
applications and our load balancer. Note that this isn't a typical practice, 
but allows us to keep this post slightly more brief.

We can test our image to make sure it builds:

```shell
cd docker && docker build . -t nginx-testing --build-arg=TEMPLATE_FILE=nginx.app.conf.tmpl
```

and you'll see something like

```shell
[+] Building 0.5s (9/9) FINISHED                                                                                                                                      
 => [internal] load build definition from Dockerfile                                                                                                             0.0s
 => => transferring dockerfile: 37B                                                                                                                              0.0s
 => [internal] load .dockerignore                                                                                                                                0.0s
 => => transferring context: 2B                                                                                                                                  0.0s
 => [internal] load metadata for docker.io/library/nginx:1.23.2-alpine                                                                                           0.4s
 => [1/4] FROM docker.io/library/nginx:1.23.2-alpine@sha256:2452715dd322b3273419652b7721b64aa60305f606ef7a674ae28b6f12d155a3                                     0.0s
 => [internal] load build context                                                                                                                                0.0s
 => => transferring context: 73B                                                                                                                                 0.0s
 => CACHED [2/4] COPY ./nginx.app.conf.tmpl /nginx.conf.template                                                                                                 0.0s
 => CACHED [3/4] COPY ./entrypoint.sh /entrypoint.sh                                                                                                             0.0s
 => CACHED [4/4] RUN chmod +x /entrypoint.sh                                                                                                                     0.0s
 => exporting to image                                                                                                                                           0.0s
 => => exporting layers                                                                                                                                          0.0s
 => => writing image sha256:4b0e0dda45822535320ace713239434c662d1657cbfc2a07ca4e491dca39ea74                                                                     0.0s
 => => naming to docker.io/library/nginx-testing                                                                                                                 0.0s

Use 'docker scan' to run Snyk tests against images to find vulnerabilities and learn how to fix them
```

I invite you to snoop around the template files and the shell script on your own time!

# Terraform
Now that we have our dockerfiles, we can begin writing up our terraform to build and deploy our images.

Typically, we would want to break apart our terraform into separate
files which makes your code much more readable. For example, in a production
scenario, I might a `images.tf`, `containers.tf`, `variables.tf`, `locals.tf`, etc.
To keep things succint, we will just put everything into one file, `main.tf`.

If we start from the top of the file, the first block we encounter is the `terraform`
settings block. The settings block is used for terraform configurations, remote
backends, required providers, etc. In our case, the only setting we are going
to set is the `required_providers` setting. This tells terraform that we
want to use version 2.23.0 or the kreuzwerker/docker provider. Pinning to specific
versions is typically a good practice in case breaking changes are added to future releases.

```hcl
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
```

The second block we come to is a `provider` block. `provider` blocks
tell terraform how to configure your providers. In our case, we want 
terraform to submit the docker api calls to our unix socket at `unix:///var/run/docker.sock`.

```hcl
/* The docker provider settings 
 * In our case, we will use the docker unix socket
 * as our host. Full configuration parameters
 * are here
 * https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs
 */
provider "docker" {
  host = "unix:///var/run/docker.sock"
}

```

Up to this point, terraform knows how to configure itself and the single provider
we are using. Next, we will add our variables, both input variables and computed
variables. 

The `variable` blocks define input variables that a user can override using a few
different methods described [here](https://developer.hashicorp.com/terraform/language/values/variables). In our code, we define two input variables, one for `external_port`, and one
for `num_server_apps`.

```hcl
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
```

This tells terraform two things:
* A user can define their own external port number. It should be a number that is between
  8000 and 12000. If its not, we should error out because its not acceptable.
* A user can request between 1 and 10 nginx app instances to sit behind our load balancer.
  Again, this should be a number and should be between 1 and 10.

Next, we get into some computed variables, or `local` variables. Note that these can
be literals, however, we are using terraform to compute them and save them so we can
reference them later:

```hcl
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
```

Locals are very useful, and they allow us to compute some pretty complex things on the
fly, and then we can easily use those complex things later. In our case, we define
`nginx_base_path` which will tell terraform where to find our docker files. We also define
`server_block_arr` which will be computed using attributes of each docker container we create.
If we set `num_server_apps` to 1, then this local will have a single entry and will look like:

```shell
server_block_arr = ["server nginx-0"]
```

If we set `num_server_apps` to 5, then it will grow dynamically:

```shell
server_block_arr = [
  "server nginx-0", "server nginx-1", 
  "server nginx-2", "server nginx-3", 
  "server nginx-4"
]
```

If you're curious as to why that local grew, then stay tuned. We will talk about that in
just a moment.

Now, we can finally create actual resources from our provider!

Let's start by building our docker images:

```hcl
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
```

You'll see we are building two docker images, one for our nginx applications and one
for the load balancer. They look extrememly similar to each other, but have varying
build arguments (remember that from the docker section?). If we look at the `nginx_app`
resource, we are:

* Building the docker image and will name it `nginxapp`
* We will rebuild the image anytime any of the images in the `local.nginx_base_path` changes
* Build the image using the `local.nginx_base_path` as our base path, tag it as `nginxapp:latest`,
  and pass the `TEMPLATE_FILE` argument to it.

Notice how we are referencing our locals in here, instead of re-writing the long docker path
each time.

With our images created, we can now start deploying them and their supporting infrastructure.
First, we create a docker network using the `docker_network` resource.

```hcl
/* A docker network for each of our containers
 * to use. This way, they can all reach eachother
 * by hostname and it wont interfere with any
 * other containers on the system and nothing
 * will interfere with them.
 */
resource "docker_network" "nginx_network" {
  name = "nginx"
}
```

Then we deploy our nginx applications using the `docker_container` resource:
```hcl
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

```

 Note that the
`count` attribute tells terraform to "Make a variable number of these". So, if our user set 
`num_server_apps` to 7, we would get 7 different docker containers deployed. Each container
is going to get a unique name of `nginx-<index>` where `<index>` ranges from 0 to
`num_server_apps` - 1 because terraform is zero indexed. This count attribute is why
our `server_block_arr` grew dynamically before. It was looping over each 
`docker_container.nginx_apps` resource to make sure it accounted for each container. It 
then attached the containers to the docker network we created before using terraform interpolation.

Finally, we can create the load balancer in a very similar fashion:

```hcl
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
```

Note that we are again using interpolation for the image id to use as well as the network id.

# Running

We can run this pretty simply and easily all through terraform:

```shell
prompt> cd terraform
prompt> terraform init
prompt> terraform apply
```

We can verify that our containers are deployed by running a `docker ps`:

```shell
prompt> docker ps
CONTAINER ID   IMAGE          COMMAND            CREATED          STATUS          PORTS                  NAMES
b768e06e815a   6cd099260405   "/entrypoint.sh"   25 seconds ago   Up 25 seconds   0.0.0.0:8080->80/tcp   nginx-lb
4effc029ccca   4b0e0dda4582   "/entrypoint.sh"   26 seconds ago   Up 26 seconds   80/tcp                 nginx-0
26340ad1f612   4b0e0dda4582   "/entrypoint.sh"   26 seconds ago   Up 26 seconds   80/tcp                 nginx-3
735538040cd7   4b0e0dda4582   "/entrypoint.sh"   26 seconds ago   Up 25 seconds   80/tcp                 nginx-1
893161b4f95b   4b0e0dda4582   "/entrypoint.sh"   26 seconds ago   Up 25 seconds   80/tcp                 nginx-2
022aa19cb5a6   4b0e0dda4582   "/entrypoint.sh"   26 seconds ago   Up 25 seconds   80/tcp                 nginx-4
```

Note that we now have `num_server_apps` nginx apps, and one load balancer listening on `external_port`!

And we can test out our load balancing:

```shell
PORT=8080 # Set to same as the var.external_port
for i in {1..10}; do
  curl http://localhost:${PORT};
  sleep 1;
  echo ""
done
```

And our output would look something like:

```shell
HELLO WORLD FROM 0
HELLO WORLD FROM 1
HELLO WORLD FROM 2
HELLO WORLD FROM 3
HELLO WORLD FROM 4
HELLO WORLD FROM 0
HELLO WORLD FROM 1
HELLO WORLD FROM 2
HELLO WORLD FROM 3
HELLO WORLD FROM 4
```

# References
* [GitHub Repo](https://github.com/afoley587/docker-terraform-nginx)