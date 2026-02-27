import bcrypt from "bcryptjs";

const SALT_ROUNDS = 10;

export async function hashPassword(password: string, saltBase64?: string): Promise<{ hashHex: string; saltBase64: string }> {
  const salt = saltBase64 ? saltBase64 : await bcrypt.genSalt(SALT_ROUNDS);
  const hash = await bcrypt.hash(password, salt);
  return { hashHex: hash, saltBase64: salt };
}

export async function verifyPassword(password: string, saltBase64: string, hashHex: string): Promise<boolean> {
  return bcrypt.compare(password, hashHex);
}
