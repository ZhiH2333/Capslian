/**
 * Refresh token 生成与校验：随机 token 存 D1（hash），用于换取新 access token。
 */

export function uuid(): string {
  return crypto.randomUUID();
}

/** 生成不可预测的 refresh token 字符串。 */
export function generateRefreshToken(): string {
  return uuid() + uuid().replace(/-/g, "");
}

/** 将字符串做 SHA-256 哈希并返回十六进制，用于 D1 存储。 */
export async function sha256Hex(text: string): Promise<string> {
  const enc = new TextEncoder();
  const buf = await crypto.subtle.digest("SHA-256", enc.encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Refresh token 有效期（秒），30 天。 */
export const REFRESH_TOKEN_EXPIRY_SECONDS = 30 * 24 * 60 * 60;
