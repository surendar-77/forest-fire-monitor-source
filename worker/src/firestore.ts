/**
 * Minimal Firestore REST client: just what the backend needs, with plain JS
 * values in and out. Every method is one subrequest (Workers Free allows 50
 * per invocation).
 */

export type Plain =
  | null
  | boolean
  | number
  | string
  | Date
  | Plain[]
  | { [key: string]: Plain };

type FsValue = Record<string, unknown>;

export interface Doc {
  id: string;
  path: string;
  data: Record<string, Plain>;
}

export function toValue(value: Plain | undefined): FsValue {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  if (typeof value === "string") return { stringValue: value };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(toValue) } };
  return { mapValue: { fields: toFields(value) } };
}

export function toFields(data: Record<string, Plain | undefined>): Record<string, FsValue> {
  const fields: Record<string, FsValue> = {};
  for (const [key, value] of Object.entries(data)) {
    if (value !== undefined) fields[key] = toValue(value);
  }
  return fields;
}

export function fromValue(value: FsValue): Plain {
  if ("nullValue" in value) return null;
  if ("booleanValue" in value) return value.booleanValue as boolean;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("stringValue" in value) return value.stringValue as string;
  if ("timestampValue" in value) return new Date(value.timestampValue as string);
  if ("referenceValue" in value) return value.referenceValue as string;
  if ("arrayValue" in value) {
    const values = (value.arrayValue as { values?: FsValue[] }).values ?? [];
    return values.map(fromValue);
  }
  if ("mapValue" in value) {
    return fromFields((value.mapValue as { fields?: Record<string, FsValue> }).fields ?? {});
  }
  return null;
}

export function fromFields(fields: Record<string, FsValue>): Record<string, Plain> {
  const data: Record<string, Plain> = {};
  for (const [key, value] of Object.entries(fields)) data[key] = fromValue(value);
  return data;
}

export interface Filter {
  field: string;
  op: "EQUAL" | "LESS_THAN" | "LESS_THAN_OR_EQUAL" | "GREATER_THAN" | "GREATER_THAN_OR_EQUAL" | "IN";
  value: Plain;
}

export type Write =
  | { set: string; data: Record<string, Plain | undefined>; merge?: boolean }
  | { delete: string };

export class Firestore {
  private readonly root: string;
  requests = 0;

  constructor(
    private readonly projectId: string,
    private readonly token: () => Promise<string>,
  ) {
    this.root = `projects/${projectId}/databases/(default)/documents`;
  }

  private async call(method: string, url: string, body?: unknown): Promise<unknown> {
    this.requests++;
    const response = await fetch(url, {
      method,
      headers: {
        Authorization: `Bearer ${await this.token()}`,
        "Content-Type": "application/json",
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    if (response.status === 404 && method === "GET") return null;
    if (!response.ok) {
      throw new Error(`Firestore ${method} ${url} -> ${response.status}: ${await response.text()}`);
    }
    return response.json();
  }

  private url(suffix: string): string {
    return `https://firestore.googleapis.com/v1/${this.root}${suffix}`;
  }

  private toDoc(raw: { name: string; fields?: Record<string, FsValue> }): Doc {
    const path = raw.name.slice(raw.name.indexOf("/documents/") + "/documents/".length);
    return { id: path.split("/").pop()!, path, data: fromFields(raw.fields ?? {}) };
  }

  async get(path: string): Promise<Doc | null> {
    const raw = (await this.call("GET", this.url(`/${path}`))) as
      | { name: string; fields?: Record<string, FsValue> }
      | null;
    return raw ? this.toDoc(raw) : null;
  }

  /** Runs a query on a collection under `parent` ("" for the root). */
  async query(
    collection: string,
    options: {
      parent?: string;
      where?: Filter[];
      orderBy?: { field: string; direction?: "ASCENDING" | "DESCENDING" };
      limit?: number;
    } = {},
  ): Promise<Doc[]> {
    const filters = (options.where ?? []).map((f) => ({
      fieldFilter: {
        field: { fieldPath: f.field },
        op: f.op,
        value: toValue(f.value),
      },
    }));

    const structuredQuery: Record<string, unknown> = { from: [{ collectionId: collection }] };
    if (filters.length === 1) structuredQuery.where = filters[0];
    if (filters.length > 1) {
      structuredQuery.where = { compositeFilter: { op: "AND", filters } };
    }
    if (options.orderBy) {
      structuredQuery.orderBy = [
        {
          field: { fieldPath: options.orderBy.field },
          direction: options.orderBy.direction ?? "ASCENDING",
        },
      ];
    }
    if (options.limit) structuredQuery.limit = options.limit;

    const parent = options.parent ? `/${options.parent}` : "";
    const rows = (await this.call("POST", this.url(`${parent}:runQuery`), {
      structuredQuery,
    })) as { document?: { name: string; fields?: Record<string, FsValue> } }[];

    return rows.filter((row) => row.document).map((row) => this.toDoc(row.document!));
  }

  /** Applies up to 500 writes atomically in one request. */
  async commit(writes: Write[]): Promise<void> {
    if (writes.length === 0) return;

    await this.call(
      "POST",
      `https://firestore.googleapis.com/v1/projects/${this.projectId}/databases/(default)/documents:commit`,
      {
        writes: writes.map((write) => {
          if ("delete" in write) return { delete: `${this.root}/${write.delete}` };

          const fields = toFields(write.data);
          return {
            update: { name: `${this.root}/${write.set}`, fields },
            ...(write.merge ? { updateMask: { fieldPaths: Object.keys(fields).map(quotePath) } } : {}),
          };
        }),
      },
    );
  }

  set(path: string, data: Record<string, Plain | undefined>, merge = false): Promise<void> {
    return this.commit([{ set: path, data, merge }]);
  }

  delete(path: string): Promise<void> {
    return this.commit([{ delete: path }]);
  }
}

/** Field paths with characters other than letters, digits and _ need backticks. */
function quotePath(field: string): string {
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(field) ? field : `\`${field}\``;
}

export function newDocId(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  return Array.from(bytes, (b) => chars[b % chars.length]).join("");
}
