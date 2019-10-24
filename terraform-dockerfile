FROM hashicorp/terraform:light
RUN apk add bash jq
COPY drpcli /usr/bin/drpcli
RUN chmod 755 /usr/bin/drpcli
ENTRYPOINT /usr/bin/drpcli machines processjobs