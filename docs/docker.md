# Docker 部署

把 MyNotion 跑在容器里，适合两种情况：想让它常驻（开机自启、不占宿主的 Node 版本），或者想把它放到家里那台常开的机器/NAS 上。数据仍然只是一个 SQLite 文件，放在容器里的 `/data` 卷，跟本机安装时没有任何区别。

## 一条命令跑起来

```bash
docker compose up -d --build
```

镜像分三层：前端产物、服务端生产依赖、运行时。运行时镜像里只有服务端源码（Node 24 直接跑 TypeScript）、前端构建结果和 3 个第三方包，浏览器用的 React/BlockNote 不会被打进去。

打开 `http://127.0.0.1:8791` 即可。首次启动会在卷里建 `mynotion.db`，并生成一个 14 位随机访问凭证。

## 第一次怎么进去

容器里区分不出"来自宿主机"和"来自局域网"的连接 —— 从宿主机 `localhost:8791` 进来的请求，在容器看来对端是 Docker 网桥地址，不是回环，所以也要凭证。这是正常现象，不是坏了。

```bash
docker compose exec mynotion node scripts/share.mjs
```

输出：

```
访问凭证：p2zgpnzqzvarf5
本机：    http://127.0.0.1:8791/login?token=p2zgpnzqzvarf5
局域网：  http://10.1.95.13:8791/login?token=p2zgpnzqzvarf5
```

点第二条链接（或把它粘到浏览器）就进去了，浏览器会拿到一个有效期一年的 Cookie，之后不用再输。**凭证存在卷里的 `/data/token`，容器重启不会变**；删掉它才会换新的，那样所有已登录的设备都要重新验证。

想让链接里的地址更好看（域名、固定 IP），把宿主机地址传进去：

```bash
docker compose exec -e SHARE_HOSTS=192.168.1.20,nas.home mynotion node scripts/share.mjs
```

## 数据在哪、怎么备份

| 内容 | 位置 |
| --- | --- |
| 数据库 | 命名卷 `mynotion-data` 里的 `/data/mynotion.db`（+ `-wal`/`-shm`） |
| 访问凭证 | 同一卷的 `/data/token` |
| 备份 | 同一卷，`node scripts/backup.mjs` 生成 `backup-YYYYMMDD.db` |

```bash
docker compose exec mynotion node scripts/backup.mjs
docker run --rm -v mynotion-data:/data -v "$PWD":/out alpine sh -c 'cp /data/backup-*.db /out/'
```

备份默认写在数据库旁边，所以它落在卷里，不会随容器重建消失。迁移 = 把卷里的 `.db` 拷出来放进另一台机器的卷，或者直接把 `DATA_FILE` 指到那个文件。

想改用宿主目录（比命名卷好备份，但权限要自己对齐）：

```yaml
# compose.yaml 里把 volumes 换成
volumes:
  - ./mynotion-data:/data
```

镜像以 `node`（uid 1000）运行，宿主机目录需要 `sudo chown -R 1000:1000 ./mynotion-data`，否则启动时会报 EACCES。

## 只有本机能访问

`compose.yaml` 里的端口映射改成绑定回环：

```yaml
ports:
  - "127.0.0.1:8791:8791"
```

## 构建参数

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `NPM_REGISTRY` | `https://registry.npmjs.org` | 中国大陆构建建议改成 `https://registry.npmmirror.com` |
| `NODE_IMAGE` | `node:24-slim` | 必须是 Debian（glibc）系；alpine 的 musl 没有 rolldown/vite 的二进制包 |

```bash
docker build --build-arg NPM_REGISTRY=https://registry.npmmirror.com -t mynotion .
```

Apple Silicon 或其他架构直接构建即可，依赖里的平台二进制会按目标架构解析；跨架构出镜像用 `docker buildx build --platform linux/amd64`。

## 已知限制

- **容器没有 HTTPS**。凭证和 Cookie 在同一网络内是明文传输的，所以只适合家里/办公室这种可信网络；要暴露到公网请套一层反向代理（Caddy、nginx）或用 Tailscale，代理后面记得把 `X-Forwarded-Proto` 和真实客户端地址带过来。
- 前端产物是构建时打进镜像的：改了 `apps/web` 的代码要重新 `--build`，热更新请继续用 `pnpm dev`。
- `pnpm dev` / `start-mynotion.cmd` 这类一键启动脚本是给本机安装用的，容器里不参与。
