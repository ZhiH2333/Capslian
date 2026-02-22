/**
 * 简单 HS256 JWT 签发与校验（Web Crypto）。
 */
const ALG: HmacKeyAlgorithm = { name: "HMAC", hash: "SHA-256", length: 256 };

function base64UrlEncode(data: ArrayBuffer): string {
  const bytes = new Uint8Array(data);
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(str: string): Uint8Array {
  str = str.replace(/-/g, "+").replace(/_/g, "/");
  const pad = str.length % 4;
  if (pad) str += "====".slice(0, 4 - pad);
  const binary = atob(str);
  const arr = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) arr[i] = binary.charCodeAt(i);
  return arr;
}

async function getSigningKey(secret: string): Promise<CryptoKey> {
  const enc = new TextEncoder();
  return crypto.subtle.importKey("raw", enc.encode(secret), ALG, false, ["sign", "verify"]);
}

export interface JwtPayload {
  sub: string;
  iat?: number;
  exp?: number;
}

export async function signJwt(payload: JwtPayload, secret: string, expiresInSeconds: number = 86400 * 7): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "HS256", typ: "JWT" };
  const payloadWithExp = { ...payload, iat: now, exp: now + expiresInSeconds };
  const headerB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(header)));
  const payloadB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(payloadWithExp)));
  const message = `${headerB64}.${payloadB64}`;
  const key = await getSigningKey(secret);
  const sig = await crypto.subtle.sign(ALG, key, new TextEncoder().encode(message));
  return `${message}.${base64UrlEncode(sig)}`;
}

export async function verifyJwt(token: string, secret: string): Promise<JwtPayload | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [headerB64, payloadB64, sigB64] = parts;
  const message = `${headerB64}.${payloadB64}`;
  const key = await getSigningKey(secret);
  const sig = base64UrlDecode(sigB64);
  const valid = await crypto.subtle.verify(ALG, key, sig, new TextEncoder().encode(message));
  if (!valid) return null;
  try {
    const payloadJson = new TextDecoder().decode(base64UrlDecode(payloadB64));
    const payload = JSON.parse(payloadJson) as JwtPayload & { exp?: number };
    if (payload.exp != null && payload.exp < Math.floor(Date.now() / 1000)) return null;
    return { sub: payload.sub, iat: payload.iat, exp: payload.exp };
  } catch {
    return null;
  }
}
