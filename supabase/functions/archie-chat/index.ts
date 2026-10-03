// Emerald Summit — archie-chat Edge Function
//
// Backs "Archie", the in-app AI assistant. Modeled on FTC Bonfire's "Sparky":
// the server grounds the model in live data, lets it use tools, and streams
// typed events to the client, which renders progress steps + a typing reveal.
//
// Grounding ("direct sources"), in priority order:
//   1. LIVE APP DATA — the catalog (disciplines, sessions, rooms, seats), the
//      News feed, and the caller's own profile + schedule. Read with the
//      CALLER'S JWT, so Row Level Security applies exactly as in the app (a
//      user never sees another user's registrations or targeted announcements).
//   2. OFFICIAL SITES — the summit / EHS Academic Foundation site and Emerald
//      High's site, read on demand with Claude's server-side web_fetch.
//   3. THE OPEN WEB — Claude's server-side web_search, with citations.
//
// Request  (POST, JSON):  { messages: [{ role: "user"|"assistant", content }] }
//   The client resends the visible transcript each turn (text only).
// Response (text/event-stream), one JSON object per `data:` line:
//   { type: "status",  text }               progress step ("Searching the web…")
//   { type: "delta",   text }               answer text, appended in order
//   { type: "sources", sources: [{title,url}] }  web sources the answer cited
//   { type: "done" }
//   { type: "error",   message }
//
// Secrets: ANTHROPIC_API_KEY (required). Optional: ARCHIE_MODEL (default
// claude-sonnet-5-5), ARCHIE_EFFORT (default "medium"), ARCHIE_DAILY_LIMIT
// (default 50 questions per user per day; needs archie_setup.sql).
// SUPABASE_URL / SUPABASE_ANON_KEY are injected automatically.
// Auth: the function verifies the caller's session itself (auth.getUser → 401)
// before doing anything costly, so it can be deployed with --no-verify-jwt
// (needed on projects using the newer JWT signing keys); only signed-in users
// can chat either way.

import Anthropic from "npm:@anthropic-ai/sdk@^0.131.0";
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Claude Sonnet 5.5: strong at chat + multi-step web research at a lower price
// than Opus ($2/$10 vs $4/$20 per million tokens). Effort: "medium" suits
// search-then-answer turns; "low" thinks less (faster, cheaper) — measure
// quality with the usage logs before lowering it.
const MODEL = Deno.env.get("ARCHIE_MODEL") ?? "claude-sonnet-5-5";
const EFFORT = Deno.env.get("ARCHIE_EFFORT") ?? "medium";
const DAILY_LIMIT = Number(Deno.env.get("ARCHIE_DAILY_LIMIT") ?? "50");

// Input guards — the transcript comes from the client, so bound it.
// Questions per chat; mirrors kArchieMaxQuestionsPerChat in the app and the
// archie_messages trigger (archie_history_setup.sql).
const MAX_QUESTIONS = 15;
const MAX_TURNS = MAX_QUESTIONS * 2;
const MAX_CHARS_PER_MESSAGE = 4000;
// Server-tool turns can pause (stop_reason "pause_turn"); resume at most this often.
const MAX_CONTINUATIONS = 3;

const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY") });

// ---------------------------------------------------------------------------
// System prompt. Kept byte-stable so it caches across every user and turn;
// anything that varies (data, date, the user) goes in later blocks.
// ---------------------------------------------------------------------------
const PERSONA = `You are Archie — the friendly, sunglasses-wearing dragon mascot and AI assistant inside the Emerald Summit '27 app. You help students, parents, experts, and volunteers with everything about the Emerald Summit and Emerald High School.

ABOUT THE EVENT
Emerald Summit '27 is the Tri-Valley's student-run STEAM summit, hosted at Emerald High School (3600 Central Pkwy, Dublin, CA 94568) in January 2027 and organized by the EHS Academic Foundation, a 501(c)(3) nonprofit. It brings together student participants, expert mentors, volunteers, and families for exhibits, presentations, workshops, and competitions across six disciplines: TechVerse, BioSphere, NovaSphere, ImagineX, VentureVerse, and CivicVerse. The previous edition, Emerald Summit '26, was held March 7, 2026.

WHERE YOUR ANSWERS COME FROM (in priority order)
1. LIVE APP DATA — provided below in the <app_data> sections. It is the source of truth for sessions, times, rooms, experts, seats left, announcements, and the user's own schedule. It is newer than anything on the web; when they disagree, trust the app data and say so.
2. OFFICIAL SITES — fetch these with web_fetch when the question is about the summit or the school and the app data doesn't answer it:
   - Emerald Summit: https://sites.google.com/view/ehs-academic-foundation/programs/emerald-summit
   - EHS Academic Foundation: https://sites.google.com/view/ehs-academic-foundation
   - Emerald High School: https://ehs.dublinusd.org
   - Dublin Unified School District: https://www.dublinusd.org
3. WEB SEARCH — for anything else in scope (directions, bell schedules, school news, background on a discipline's topic). Prefer official and reputable sources.

GROUNDING RULES
- Never invent sessions, times, rooms, names, prices, or policies. If neither the app data nor a source you found answers it, say you don't know and point the user to president@ehsacademics.org or the News tab.
- When you use app data, say so naturally ("According to the summit schedule…", "In your schedule…").
- For facts about the summit or Emerald High that the app data doesn't cover — dates, schedules, policies, what's allowed, required, or charged — check the official sites or search rather than answering from memory, even when you feel confident; these details change.
- When you use the web, rely on what the pages actually say; your citations are shown to the user as source links automatically, so you don't need to paste URLs.
- Session times in the app data are 24-hour "HH:mm" on summit day; present them as 12-hour times (e.g. 2:30 PM).
- You can't change anything in the app (register, cancel, post). Tell the user where to do it: Discover tab → a discipline → a session → "Add to my day"; the Schedule tab shows their day; News has announcements; the avatar on Home opens Profile.

SCOPE
Answer questions about: the Emerald Summit (sessions, disciplines, tracks, experts, logistics, volunteering, registration), Emerald High School and Dublin Unified, getting to and around campus, and introductory explanations of the summit's subject areas (e.g. "what happens at a mock trial?", "what is CAD?") that help someone get ready for a session.
For anything clearly unrelated (general homework, coding projects, essays, news, trivia, personal advice), politely decline in one or two sentences and offer something summit-related instead. Many users are high-school students: keep everything age-appropriate and never ask for personal information.

STYLE
- You're talking on a phone screen. Lead with the answer. Keep it short — usually 2–5 sentences or a few bullets. Expand only when asked.
- Warm, upbeat, and clear; a light touch of dragon personality is welcome, but never at the expense of the answer.
- Markdown: **bold** for key facts like times and rooms, short bullet lists when listing sessions. No tables, no emojis, no headings bigger than ###, no code blocks unless asked.
- This is a latency-sensitive chat: begin your visible answer promptly.
- Once you've answered something, treat that answer as done. On later turns, focus on what the person is asking now, and don't go back over an earlier answer unless they ask about it or point out a problem with it.`;

// ---------------------------------------------------------------------------
// HTTP entry point
// ---------------------------------------------------------------------------
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  // A client acting AS the caller: every read below is filtered by RLS.
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userErr } = await db.auth.getUser(
    authHeader.replace(/^Bearer\s+/i, ""),
  );
  if (userErr || !userData?.user) return json({ error: "Sign in to chat with Archie." }, 401);
  const userId = userData.user.id;

  const body = await req.json().catch(() => ({}));
  const history = sanitizeHistory(body?.messages);
  if (!history) return json({ error: "Expected { messages: [...] } ending with a user message." }, 400);
  if (history.filter((m) => m.role === "user").length > MAX_QUESTIONS) {
    return json({ error: "This conversation is too long. Please start a new chat." }, 400);
  }

  // Per-user daily cap (cost guard). Fails open if the table/RPC isn't installed.
  const allowed = await checkDailyLimit(db);
  if (!allowed) {
    return sse(async (send) => {
      send({
        type: "delta",
        text: `I've hit my limit of ${DAILY_LIMIT} questions for you today — dragons need rest too! Try again tomorrow, or check the **News** and **Discover** tabs in the meantime.`,
      });
      send({ type: "done" });
    });
  }

  const [catalog, personal] = await Promise.all([
    loadCatalogContext(db),
    loadPersonalContext(db, userId),
  ]);

  return sse(async (send, signal) => {
    await streamAnswer(history, catalog, personal, send, signal);
  }, req.signal);
});

// ---------------------------------------------------------------------------
// The model call — streamed, with pause_turn continuation for server tools.
// ---------------------------------------------------------------------------
type Send = (event: Record<string, unknown>) => void;

async function streamAnswer(
  history: Anthropic.MessageParam[],
  catalog: CatalogContext,
  personal: string,
  send: Send,
  signal: AbortSignal,
) {
  const messages: Anthropic.MessageParam[] = [...history];
  const sources = new Map<string, string>(); // url -> title
  let wroteText = false;

  for (let turn = 0; turn <= MAX_CONTINUATIONS; turn++) {
    // `fallbacks: "default"` re-runs a safety-declined request on Anthropic's
    // recommended fallback model server-side (on Sonnet 5.5 that covers the
    // "cyber" and "frontier_llm" categories; other declines end as a refusal,
    // handled below). Built as a loose object because SDK typings can lag the
    // newest beta fields.
    const params: Record<string, unknown> = {
      model: MODEL,
      max_tokens: 16000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      thinking: { type: "adaptive" },
      output_config: { effort: EFFORT },
      system: [
        { type: "text", text: PERSONA },
        // Shared data, ordered least → most likely to change, each block
        // ending in a cache breakpoint (3 here + the automatic one on the
        // conversation = the API's maximum of 4). A change only invalidates
        // its own block and the ones after it: a registration re-caches just
        // the small seats block; a new announcement, news + seats.
        { type: "text", text: catalog.sessions, cache_control: { type: "ephemeral" } },
        { type: "text", text: catalog.news, cache_control: { type: "ephemeral" } },
        { type: "text", text: catalog.seats, cache_control: { type: "ephemeral" } },
        // Per user — after the shared blocks so it never breaks their cache.
        { type: "text", text: personal },
      ],
      tools: [
        {
          type: "web_search_20260209",
          name: "web_search",
          max_uses: 5,
          user_location: {
            type: "approximate",
            city: "Dublin",
            region: "California",
            country: "US",
            timezone: "America/Los_Angeles",
          },
        },
        {
          type: "web_fetch_20260209",
          name: "web_fetch",
          max_uses: 4,
          citations: { enabled: true },
        },
      ],
      messages,
      // Automatic caching: a second breakpoint that follows the end of the
      // conversation, so each follow-up re-reads the earlier turns from cache
      // (5% of the input price) instead of paying for them again.
      cache_control: { type: "ephemeral" },
    };

    const stream = anthropic.beta.messages.stream(
      params as unknown as Anthropic.Beta.Messages.MessageCreateParamsStreaming,
    );
    const onAbort = () => stream.abort();
    signal.addEventListener("abort", onAbort);

    // Server-tool inputs stream as JSON fragments; buffer per block index so a
    // progress step can name the query/URL once the input is complete.
    const toolInputs = new Map<number, { name: string; json: string }>();

    try {
      for await (const event of stream) {
        if (event.type === "content_block_start") {
          const block = event.content_block as { type: string; name?: string; content?: unknown };
          if (block.type === "server_tool_use") {
            toolInputs.set(event.index, { name: block.name ?? "", json: "" });
          } else if (block.type === "web_fetch_tool_result") {
            const res = block.content as { type?: string; url?: string; content?: { title?: string } };
            if (res?.type === "web_fetch_result" && res.url) {
              sources.set(res.url, res.content?.title ?? hostOf(res.url));
            }
          }
        } else if (event.type === "content_block_delta") {
          const delta = event.delta as {
            type: string;
            text?: string;
            partial_json?: string;
            citation?: { type: string; url?: string; title?: string };
          };
          if (delta.type === "text_delta" && delta.text) {
            wroteText = true;
            send({ type: "delta", text: delta.text });
          } else if (delta.type === "input_json_delta") {
            const t = toolInputs.get(event.index);
            if (t) t.json += delta.partial_json ?? "";
          } else if (delta.type === "citations_delta" && delta.citation?.url) {
            sources.set(delta.citation.url, delta.citation.title || hostOf(delta.citation.url));
          }
        } else if (event.type === "content_block_stop") {
          const t = toolInputs.get(event.index);
          if (t) {
            toolInputs.delete(event.index);
            const step = describeToolStep(t.name, t.json);
            if (step) send({ type: "status", text: step });
          }
        }
      }
    } finally {
      signal.removeEventListener("abort", onAbort);
    }
    if (signal.aborted) return;

    const final = await stream.finalMessage();
    // One line per model call — read cost/caching in the function's Logs.
    const u = final.usage as unknown as Record<string, unknown>;
    console.log(JSON.stringify({
      archie_usage: {
        model: final.model,
        stop: final.stop_reason,
        input: u.input_tokens,
        cache_read: u.cache_read_input_tokens,
        cache_write: u.cache_creation_input_tokens,
        output: u.output_tokens,
        web_searches: (u.server_tool_use as Record<string, unknown> | undefined)?.web_search_requests,
      },
    }));

    if (final.stop_reason === "refusal") {
      if (!wroteText) {
        send({
          type: "delta",
          text: "Hmm, that's not something I can help with. Ask me anything about the Emerald Summit or Emerald High!",
        });
      }
      break;
    }
    if (final.stop_reason === "pause_turn") {
      // A long server-tool turn paused; hand it back so the model continues.
      messages.push({ role: "assistant", content: final.content as Anthropic.ContentBlockParam[] });
      continue;
    }
    break;
  }

  if (!wroteText) {
    send({ type: "delta", text: "Sorry, I couldn't put an answer together that time. Mind asking again?" });
  }
  if (sources.size > 0) {
    send({
      type: "sources",
      sources: [...sources].slice(0, 8).map(([url, title]) => ({ url, title })),
    });
  }
  send({ type: "done" });
}

function describeToolStep(name: string, rawJson: string): string | null {
  let input: Record<string, unknown> = {};
  try {
    input = JSON.parse(rawJson || "{}");
  } catch {
    // Partial/odd input — fall back to a generic label below.
  }
  if (name === "web_search") {
    const q = typeof input.query === "string" ? input.query : "";
    return q ? `Searching the web for “${q}”` : "Searching the web";
  }
  if (name === "web_fetch") {
    const url = typeof input.url === "string" ? input.url : "";
    return url ? `Reading ${hostOf(url)}` : "Reading a web page";
  }
  return null;
}

// ---------------------------------------------------------------------------
// Grounding data (read as the caller → RLS-scoped)
// ---------------------------------------------------------------------------
/// The shared (same-for-every-user) app data, split by how often it changes.
type CatalogContext = { sessions: string; news: string; seats: string };

async function loadCatalogContext(db: SupabaseClient): Promise<CatalogContext> {
  const [disciplines, sessions, announcements] = await Promise.all([
    // Fully ordered (ties broken by id) so the same data always renders to the
    // same bytes — any byte difference would defeat the shared cache.
    db.from("disciplines").select("id, name, tagline").order("sort_order").order("id"),
    // Only the columns Archie uses — keeps each question's database egress
    // small (no hero images, gallery data, participant questions, etc.).
    db.from("sessions_with_counts")
      .select("id, title, discipline_name, start_time, end_time, room, expert_name, description, page_blocks, capacity, enrolled")
      .order("start_time").order("id"),
    loadBroadcastAnnouncements(db),
  ]);

  // Sessions block: changes only when an editor changes a session.
  const lines: string[] = ['<app_data section="catalog">', "## Disciplines"];
  for (const d of disciplines.data ?? []) {
    lines.push(`- ${d.name} (id: ${d.id})${d.tagline ? ` — ${d.tagline}` : ""}`);
  }
  lines.push("", "## Sessions (summit day; times are 24h HH:mm; seats are listed separately below)");
  const rows = (sessions.data ?? []) as Record<string, unknown>[];
  if (rows.length === 0) lines.push("(No sessions published yet.)");
  for (const s of rows) {
    const parts = [
      `- [${s.id}] "${s.title}" — ${s.discipline_name}`,
      `${s.start_time}–${s.end_time}`,
      s.room ? `room: ${s.room}` : null,
      s.expert_name ? `expert: ${s.expert_name}` : null,
    ].filter(Boolean);
    lines.push(parts.join(" · "));
    const desc = String(s.description ?? "").trim();
    if (desc) lines.push(`  ${truncate(desc, 400)}`);
    for (const block of (Array.isArray(s.page_blocks) ? s.page_blocks : []) as { title?: string; body?: string }[]) {
      if (block?.title || block?.body) {
        lines.push(`  ${block.title ?? ""}: ${truncate(String(block.body ?? ""), 300)}`);
      }
    }
  }
  lines.push("</app_data>");

  // News block: changes when an admin posts or deletes an announcement.
  const news = ['<app_data section="announcements">', "## Recent announcements (News tab, newest first)"];
  if (announcements.length === 0) news.push("(None yet.)");
  for (const a of announcements) news.push(describeAnnouncement(a));
  news.push("</app_data>");

  // Seats block: changes on every registration, so it comes last and is short.
  const seats = ['<app_data section="seats">', "## Seats left right now (by session id)"];
  if (rows.length === 0) seats.push("(No sessions published yet.)");
  for (const s of rows) {
    const cap = Number(s.capacity ?? 0);
    const enrolled = Number(s.enrolled ?? 0);
    seats.push(
      `- [${s.id}] "${s.title}": ${cap > 0 ? `${Math.max(cap - enrolled, 0)} of ${cap} seats left` : "open seating"}`,
    );
  }
  seats.push("</app_data>");

  return { sessions: lines.join("\n"), news: news.join("\n"), seats: seats.join("\n") };
}

type AnnouncementRow = { title: string; body: string; audience: string; pinned: boolean; created_at: string };
const ANNOUNCEMENT_COLUMNS = "title, body, audience, pinned, created_at";

// Broadcast announcements only: personal ones (target_user_id) differ per user,
// so they go in the per-user block and the catalog stays identical for everyone.
async function loadBroadcastAnnouncements(db: SupabaseClient): Promise<AnnouncementRow[]> {
  const query = () =>
    db.from("announcements").select(ANNOUNCEMENT_COLUMNS)
      .order("created_at", { ascending: false }).order("id").limit(20);
  const { data, error } = await query().is("target_user_id", null);
  if (!error) return (data ?? []) as AnnouncementRow[];
  // Projects without targeted announcements (no target_user_id column yet).
  return ((await query()).data ?? []) as AnnouncementRow[];
}

function describeAnnouncement(a: AnnouncementRow): string {
  return `- ${a.pinned ? "[pinned] " : ""}${a.title} (${a.audience}, ${String(a.created_at).slice(0, 10)}): ${truncate(a.body, 300)}`;
}

async function loadPersonalContext(db: SupabaseClient, userId: string): Promise<string> {
  const [profile, regs, managing, personalNews] = await Promise.all([
    db.from("profiles").select("full_name, role").eq("id", userId).maybeSingle(),
    db.from("registrations").select("*").eq("user_id", userId),
    db.from("session_volunteers").select("session_id").eq("user_id", userId),
    db.from("announcements").select(ANNOUNCEMENT_COLUMNS)
      .eq("target_user_id", userId)
      .order("created_at", { ascending: false }).limit(10),
  ]);
  const ids = new Set<string>();
  for (const r of regs.data ?? []) ids.add(r.session_id);
  for (const m of managing.data ?? []) ids.add(m.session_id);

  const titles = new Map<string, Record<string, unknown>>();
  if (ids.size > 0) {
    const { data } = await db.from("sessions_with_counts")
      .select("id, title, start_time, end_time, room")
      .in("id", [...ids]);
    for (const s of data ?? []) titles.set(s.id, s);
  }
  const describe = (id: string, how: string) => {
    const s = titles.get(id);
    return s ? `- ${s.start_time}–${s.end_time} "${s.title}"${s.room ? ` (${s.room})` : ""} — ${how}` : null;
  };

  const today = new Date().toLocaleDateString("en-US", {
    timeZone: "America/Los_Angeles",
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });
  const lines = [
    "<user_context>",
    `Today is ${today} (Pacific time).`,
    `User's name: ${profile.data?.full_name || "unknown"}. Role: ${profile.data?.role ?? "unknown"}.`,
    "Their schedule (from the Schedule tab):",
  ];
  const mine = [
    ...(regs.data ?? []).map((r) => describe(r.session_id, r.participation_type ?? "registered")),
    ...(managing.data ?? []).map((m) => describe(m.session_id, "managing")),
  ].filter(Boolean) as string[];
  lines.push(...(mine.length ? mine.sort() : ["(Nothing added yet.)"]));
  const personal = (personalNews.data ?? []) as AnnouncementRow[];
  if (personal.length) {
    lines.push("Personal notices sent only to them (News tab):", ...personal.map(describeAnnouncement));
  }
  lines.push("</user_context>");
  return lines.join("\n");
}

async function checkDailyLimit(db: SupabaseClient): Promise<boolean> {
  const { data, error } = await db.rpc("archie_bump_usage", { p_limit: DAILY_LIMIT });
  if (error) return true; // archie_setup.sql not installed → no cap
  return data === true;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function sanitizeHistory(raw: unknown): Anthropic.MessageParam[] | null {
  if (!Array.isArray(raw)) return null;
  const out: Anthropic.MessageParam[] = [];
  for (const m of raw.slice(-MAX_TURNS)) {
    const role = m?.role === "assistant" ? "assistant" : m?.role === "user" ? "user" : null;
    const content = typeof m?.content === "string" ? m.content.trim() : "";
    if (!role || !content) continue;
    const text = content.slice(0, MAX_CHARS_PER_MESSAGE);
    // Merge accidental same-role neighbours so roles strictly alternate.
    const prev = out[out.length - 1];
    if (prev && prev.role === role) prev.content = `${prev.content}\n\n${text}`;
    else out.push({ role, content: text });
  }
  while (out.length && out[0].role !== "user") out.shift();
  if (!out.length || out[out.length - 1].role !== "user") return null;
  return out;
}

function sse(
  run: (send: Send, signal: AbortSignal) => Promise<void>,
  clientSignal?: AbortSignal,
): Response {
  const encoder = new TextEncoder();
  const controllerAbort = new AbortController();
  clientSignal?.addEventListener("abort", () => controllerAbort.abort());
  const stream = new ReadableStream({
    async start(controller) {
      const send: Send = (event) => {
        if (controllerAbort.signal.aborted) return;
        try {
          controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));
        } catch {
          controllerAbort.abort(); // client went away
        }
      };
      try {
        await run(send, controllerAbort.signal);
      } catch (e) {
        console.error("archie-chat error", e);
        send({ type: "error", message: friendlyError(e) });
      } finally {
        try {
          controller.close();
        } catch {
          // already closed
        }
      }
    },
    cancel() {
      controllerAbort.abort();
    },
  });
  return new Response(stream, {
    headers: {
      ...CORS,
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache",
      "X-Accel-Buffering": "no",
    },
  });
}

function friendlyError(e: unknown): string {
  if (e instanceof Anthropic.RateLimitError) return "I'm getting a lot of questions right now — try again in a moment.";
  if (e instanceof Anthropic.APIConnectionError) return "I couldn't reach my brain just now. Check your connection and try again.";
  if (e instanceof Anthropic.APIError) return "Something went wrong on my end. Please try again.";
  return "Something went wrong. Please try again.";
}

function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}

function truncate(s: string, n: number): string {
  return s.length > n ? `${s.slice(0, n - 1)}…` : s;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
