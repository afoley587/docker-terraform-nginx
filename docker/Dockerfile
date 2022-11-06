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