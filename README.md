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

First, all code in this blog post is hosted [here](). The directory
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

I invite you to snoop around the template files and the shell script on your own time!

# Terraform