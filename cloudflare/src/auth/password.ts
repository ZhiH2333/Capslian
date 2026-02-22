/**
 * 使用 PBKDF2-SHA256 哈希与校验密码；盐值为随机 base64。
 */
const PBKDF2_ITERATIONS = 100000;
const KEY_LEN = 32;
const SALT_LEN = 16;

function bufferToHex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function hexToBuffer(hex: string): Uint8Array {
  const arr = new Uint8Array(hex.length / 2);
  for (let i = 0; i < arr.length; i++) arr[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return arr;
}

export async function hashPassword(password: string, saltBase64?: string): Promise<{ hashHex: string; saltBase64: string }> {
  const salt = saltBase64
    ? Uint8Array.from(atob(saltBase64), (c) => c.charCodeAt(0))
    : crypto.getRandomValues(new Uint8Array(SALT_LEN));
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt, iterations: PBKDF2_ITERATIONS, hash: "SHA-256" },
    key,
    KEY_LEN * 8
  );
  const hashHex = bufferToHex(bits);
  const saltBase64Out = btoa(String.fromCharCode(...salt));
  return { hashHex, saltBase64Out: saltBase64Out };
}

export async function verifyPassword(password: string, saltBase64: string, hashHex: string): Promise<boolean> {
  const { hashHex: computed } = await hashPassword(password, saltBase64);
  return computed === hashHex;
}
