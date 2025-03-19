# 基础阶段：安装 Node.js 和 pnpm
ARG DOCKER_MIRROR=""
#ARG DOCKER_MIRROR="#docker.m.daocloud.io/library/"
ARG NPM_MIRROR="https://registry.npmmirror.com"
ARG GOPROXY_MIRROR="https://goproxy.cn,direct"

FROM ${DOCKER_MIRROR}node:22-alpine AS base
RUN npm install -g pnpm
COPY web/ /app/web/

# 设置 pnpm 使用国内镜像源
WORKDIR /app/web
RUN pnpm config set registry $NPM_MIRROR

# 生产依赖阶段：安装生产依赖
FROM base AS prod-deps
WORKDIR /app/web
RUN cd /app/web && pnpm install --prod

# 构建阶段：安装所有依赖并构建前端
FROM base AS build
WORKDIR /app/web
COPY --from=prod-deps /app/web/node_modules ./node_modules
RUN cd /app/web && pnpm install  && pnpm run build

# Go 构建阶段：构建后端
FROM ${DOCKER_MIRROR}golang:alpine AS go-build
# 安装 git
RUN apk update && apk add --no-cache git  \
    && mkdir -p /www-server && chmod -R 777 /www-server

WORKDIR /www-server
COPY server/ .

# 设置环境变量并进行验证
ENV GOPROXY=${GOPROXY_MIRROR:-https://goproxy.cn,direct}
RUN go env -w GO111MODULE=on \
    && go env -w GOPROXY=$GOPROXY \
    && go env -w CGO_ENABLED=0 \
    && go mod download \
    && go mod verify \
    && go mod tidy \
    && go build -o server .

# 最终镜像阶段：使用 Nginx 和 Supervisor 管理服务
FROM ${DOCKER_MIRROR}alpine:latest

LABEL MAINTAINER="trainliang@gmail.com"

# 设置时区
ENV TZ=Asia/Shanghai
RUN apk update && apk add --no-cache tzdata openntpd supervisor nginx \
    && ln -sf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 新增：创建 Nginx 需要的项目目录并设置权限、
RUN mkdir -p /var/log/nginx /var/cache/nginx && chown -R nginx:nginx /var/log/nginx /var/cache/nginx && mkdir -p /www-server && chown -R 777 /www-server

# 复制前端构建结果到 Nginx 的默认目录
COPY --from=build /app/web/dist /usr/share/nginx/html

# 复制 Nginx 配置文件
COPY --from=build /app/web/.docker-compose/nginx/conf.d/my.conf /etc/nginx/http.d/my.conf

# 复制后端构建结果和配置文件
COPY --from=go-build /www-server/server /www-server/server
COPY --from=go-build /www-server/resource /www-server/resource/
COPY --from=go-build /www-server/config.docker.yaml /www-server/config.docker.yaml

# 创建 Supervisor 配置文件（需包含以下内容）
COPY supervisord.conf supervisord.conf

# 挂载目录：如果使用了sqlite数据库，路径请配置【/data】，容器命令示例：docker run -d -v /宿主机路径/gva.db:/data/gva.db -p 8888:8888 --name gva-server-v1 gva-server:1.0
VOLUME ["/uploads"]
VOLUME ["/data"]

# 暴露后端服务端口
EXPOSE 8080

COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
# 启动 Supervisor
CMD ["supervisord", "-c", "supervisord.conf"]
