import jwt from "jsonwebtoken";

const JWT_SECRET = process.env.JWT_SECRET || "dev-secret-change-in-production";

export interface JwtPayload {
  sub: string;
  iat?: number;
  exp?: number;
}

export function signJwt(payload: JwtPayload, secret: string, expiresInSeconds: number = 86400 * 7): string {
  return jwt.sign(payload, secret, { expiresIn: expiresInSeconds });
}

export function verifyJwt(token: string, secret: string): JwtPayload | null {
  try {
    const payload = jwt.verify(token, secret) as JwtPayload;
    return payload;
  } catch {
    return null;
  }
}
