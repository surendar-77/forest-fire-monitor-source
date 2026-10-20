/**
 * Minimal Realtime Database REST client (service-account OAuth token, which
 * bypasses the database rules).
 */
export class Rtdb {
  requests = 0;

  constructor(
    private readonly baseUrl: string,
    private readonly token: () => Promise<string>,
  ) {}

  private async call(method: string, path: string, body?: unknown): Promise<unknown> {
    this.requests++;
    const response = await fetch(`${this.baseUrl}/${path}.json`, {
      method,
      headers: { Authorization: `Bearer ${await this.token()}`, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) {
      throw new Error(`RTDB ${method} ${path} -> ${response.status}: ${await response.text()}`);
    }
    return response.json();
  }

  get(path: string): Promise<unknown> {
    return this.call("GET", path);
  }

  async put(path: string, value: unknown): Promise<void> {
    await this.call("PUT", path, value);
  }
}
