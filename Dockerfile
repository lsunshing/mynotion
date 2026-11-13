# MyNotion 容器镜像：三阶段，运行镜像里只有服务端源码、前端产物和服务端的生产依赖。
#
#   docker build -t mynotion .
#   docker compose up -d
#
# 在中国大陆构建，两个源都要换（Docker Hub 与 npm 都不通）：
#   docker build \
#     --build-arg NODE_IMAGE=docker.m.daocloud.io/library/node:24-slim \
#     --build-arg NPM_REGISTRY=https://registry.npmmirror.com \
#     -t mynotion .

ARG NODE_IMAGE=node:24-slim
# 默认走 npm 官方源；在中国大陆构建可覆盖为 registry.npmmirror.com。
# 必须是 Debian 系（glibc）：rolldown/vite 的平台二进制在 alpine(musl) 上没有对应包。
ARG NPM_REGISTRY=https://registry.npmjs.org

# ---------- 1. 前端产物：需要 devDependencies（vite + rolldown），只有这里用得到 ----------
FROM ${NODE_IMAGE} AS web-build
ARG NPM_REGISTRY
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    COREPACK_NPM_REGISTRY=${NPM_REGISTRY} \
    npm_config_registry=${NPM_REGISTRY}
WORKDIR /app
# 先只拷清单，依赖层就能被 Docker 缓存住，改源码不会重新装依赖。
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/server/package.json apps/server/
COPY apps/web/package.json apps/web/
COPY packages/shared/package.json packages/shared/
RUN corepack enable && pnpm install --frozen-lockfile
COPY apps ./apps
COPY packages ./packages
RUN pnpm --filter @mynotion/web build

# ---------- 2. 运行期依赖：只装服务端那三个生产依赖，浏览器用的包不进镜像 ----------
FROM ${NODE_IMAGE} AS server-deps
ARG NPM_REGISTRY
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    COREPACK_NPM_REGISTRY=${NPM_REGISTRY} \
    npm_config_registry=${NPM_REGISTRY}
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/server/package.json apps/server/
COPY apps/web/package.json apps/web/
COPY packages/shared/package.json packages/shared/
RUN corepack enable && pnpm install --frozen-lockfile --prod --filter=@mynotion/server...

# ---------- 3. 运行镜像 ----------
FROM ${NODE_IMAGE} AS runtime
WORKDIR /app

# 服务端直接跑 TypeScript（Node 24 的 type-stripping），所以源码就是运行产物，不需要构建步骤。
COPY --from=server-deps /app ./
COPY apps/server/src ./apps/server/src
COPY packages/shared/src ./packages/shared/src
COPY scripts ./scripts
# 前端产物只有这一份进镜像，源码和 devDependencies 都留在构建阶段。
COPY --from=web-build /app/apps/web/dist ./apps/web/dist

ENV HOST=0.0.0.0 \
    PORT=8791 \
    DATA_FILE=/data/mynotion.db

# 数据库、访问凭证、备份都落在 /data：挂一个卷出来，容器重建数据还在。
RUN mkdir -p /data && chown -R node:node /data /app
USER node

EXPOSE 8791
VOLUME ["/data"]

# 容器内探回环地址，走的是「本机免鉴权」那条通道，所以健康检查不需要凭证。
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD node -e "const p=process.env.PORT||8791;fetch('http://127.0.0.1:'+p+'/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "--disable-warning=ExperimentalWarning", "apps/server/src/index.ts"]
