import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

/** 数据库所在目录就是本地状态的家：备份、访问凭证都写在这里。指到挂载卷，容器重建也不丢。 */
export const DB_PATH =
  process.env.DATA_FILE ?? path.resolve(here, "..", "..", "..", "..", "data", "mynotion.db");

export const DATA_DIR = path.dirname(DB_PATH);

export const TOKEN_PATH = process.env.TOKEN_FILE ?? path.join(DATA_DIR, "token");
