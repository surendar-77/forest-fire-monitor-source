/**
 * Telegram bot helpers beyond sending alerts: who has messaged the bot (so
 * an admin can pick a fire station's chat in the app instead of looking up
 * chat ids), the bot's name, and test messages.
 */

export interface TelegramChat {
  chatId: string;
  name: string;
  username: string | null;
  type: string;
  lastText: string;
  lastMessageAt: Date;
}

interface Update {
  update_id: number;
  message?: {
    date: number;
    text?: string;
    chat: { id: number; type: string; title?: string; first_name?: string; last_name?: string; username?: string };
  };
}

export interface BotCommand {
  chatId: string;
  /** "start" or "stop". */
  command: string;
  /** Text after the command, e.g. the link code in "/start CODE". */
  argument: string;
}

/**
 * Chats in a getUpdates result (newest message per chat), every /start and
 * /stop command in order, and the next offset.
 */
export function chatsFromUpdates(updates: Update[]): {
  chats: TelegramChat[];
  commands: BotCommand[];
  nextOffset: number | null;
} {
  const byId = new Map<string, TelegramChat>();
  const commands: BotCommand[] = [];
  let last: number | null = null;

  for (const update of updates) {
    last = last == null ? update.update_id : Math.max(last, update.update_id);
    const message = update.message;
    if (!message) continue;
    const chat = message.chat;
    const match = /^\/(start|stop)(?:@\w+)?(?:\s+(\S+))?/.exec(message.text ?? "");
    if (match) commands.push({ chatId: String(chat.id), command: match[1], argument: match[2] ?? "" });
    const name =
      chat.title ?? ([chat.first_name, chat.last_name].filter(Boolean).join(" ") || chat.username || String(chat.id));
    byId.set(String(chat.id), {
      chatId: String(chat.id),
      name,
      username: chat.username ?? null,
      type: chat.type,
      lastText: (message.text ?? "").slice(0, 100),
      lastMessageAt: new Date(message.date * 1000),
    });
  }

  return { chats: [...byId.values()], commands, nextOffset: last == null ? null : last + 1 };
}

async function api(token: string, method: string, body?: unknown): Promise<unknown> {
  const response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: body === undefined ? "GET" : "POST",
    headers: { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = (await response.json()) as { ok: boolean; result?: unknown; description?: string };
  if (!json.ok) throw new Error(`Telegram ${method}: ${json.description ?? response.status}`);
  return json.result;
}

export async function getUpdates(token: string, offset: number | null): Promise<Update[]> {
  const result = await api(token, "getUpdates", {
    offset: offset ?? undefined,
    timeout: 0,
    limit: 50,
    allowed_updates: ["message"],
  });
  return Array.isArray(result) ? (result as Update[]) : [];
}

export async function botUsername(token: string): Promise<string | null> {
  const me = (await api(token, "getMe")) as { username?: string };
  return me.username ?? null;
}

export async function sendText(token: string, chatId: string, text: string): Promise<void> {
  await api(token, "sendMessage", { chat_id: chatId, text, disable_web_page_preview: true });
}
