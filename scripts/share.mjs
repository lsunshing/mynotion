// 打印访问凭证与可直接点开的链接：局域网设备（手机/平板）只能靠这条链接进来。
import os from "node:os";
import { loadToken } from "../apps/server/src/lib/token.ts";
import { TOKEN_PATH } from "../apps/server/src/lib/paths.ts";

const port = Number(process.env.PORT ?? 8791);
const token = loadToken();

// 容器里探测到的是容器网卡，没有意义；用 SHARE_HOSTS 传宿主机地址或域名。
const hosts = process.env.SHARE_HOSTS?.split(",").map((s) => s.trim()).filter(Boolean) ??
  Object.values(os.networkInterfaces())
    .flat()
    .filter((n) => n && !n.internal && (n.family === "IPv4" || n.family === 4))
    .map((n) => n.address);

console.log(`访问凭证：${token}`);
console.log(`本机：    http://127.0.0.1:${port}/login?token=${token}`);
for (const ip of hosts) console.log(`局域网：  http://${ip}:${port}/login?token=${token}`);
console.log(`\n凭证存在 ${TOKEN_PATH}；删掉它下次启动会换一个新的，已登录的设备都要重新验证。`);
console.log("服务已在运行的话无需重启，上面的链接立刻可用。");
