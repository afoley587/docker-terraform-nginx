FROM nginx:1.23.2-alpine
ARG TEMPLATE_FILE
COPY ./$TEMPLATE_FILE /nginx.conf.template
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]