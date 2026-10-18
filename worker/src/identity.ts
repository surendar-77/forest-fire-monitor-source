/** Firebase Auth user lookups and custom claims via the Identity Toolkit REST API. */

export interface AuthUser {
  uid: string;
  email: string;
  claims: Record<string, unknown>;
}

async function call(
  projectId: string,
  token: string,
  method: string,
  body: unknown,
): Promise<Record<string, unknown>> {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts:${method}`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
  );
  if (!response.ok) {
    throw new Error(`Identity Toolkit ${method} -> ${response.status}: ${await response.text()}`);
  }
  return response.json();
}

export async function lookupUser(
  projectId: string,
  token: string,
  by: { uid?: string; email?: string },
): Promise<AuthUser | null> {
  const result = await call(projectId, token, "lookup", by.uid ? { localId: [by.uid] } : { email: [by.email] });
  const user = (result.users as Record<string, unknown>[] | undefined)?.[0];
  if (!user) return null;

  let claims: Record<string, unknown> = {};
  try {
    claims = user.customAttributes ? JSON.parse(String(user.customAttributes)) : {};
  } catch {
    claims = {};
  }

  return { uid: String(user.localId), email: String(user.email ?? ""), claims };
}

export async function setClaims(
  projectId: string,
  token: string,
  uid: string,
  claims: Record<string, unknown>,
): Promise<void> {
  await call(projectId, token, "update", { localId: uid, customAttributes: JSON.stringify(claims) });
}
