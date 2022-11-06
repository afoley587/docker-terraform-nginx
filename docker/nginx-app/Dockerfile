FROM nginx:1.23.2-alpine
COPY ./nginx.conf.tmpl /nginx.conf.template
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]