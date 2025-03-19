#!/bin/sh
mkdir -p /data/log \
    && touch /data/log/nginx-out.log /data/log/nginx-err.log /data/log/server-out.log /data/log/server-err.log /data/log/nginx-server-error.log /data/log/supervisord.log \
    && chown -R 1000:1000 /data/log \
    && chmod -R 755 /data/log

# 判断文件是否存在，如果不存在则复制
if [ ! -f /data/config.docker.yaml ]; then
    cp /www-server/config.docker.yaml /data/config.docker.yaml
fi

exec "$@"