const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const fetch = require("node-fetch");

const OPENAI_CHAT_URL = "https://api.openai.com/v1/chat/completions";

/** Bound at deploy time; value from Secret Manager (not committed). */
const openAIApiKeySecret = defineSecret("OPENAI_API_KEY");

/**
 * Proxies OpenAI chat/completions so the API key stays on the server.
 *
 * Deploy: `firebase functions:secrets:set OPENAI_API_KEY` (paste key when prompted), then
 * `firebase deploy --only functions:openaiChatCompletion`.
 * Local emulator: add `OPENAI_API_KEY=...` to `functions/.secret.local` (gitignored).
 *
 * Client: when `APIKeys.openAI` is empty, the iOS app calls this callable instead of OpenAI directly.
 */
exports.openaiChatCompletion = onCall(
  {
    secrets: [openAIApiKeySecret],
    maxInstances: 20,
    timeoutSeconds: 120,
    memory: "512MiB",
    allowInvalidAppCheckToken: true,
    allowUnauthenticated: true,
  },
  async (request) => {
    const apiKey = openAIApiKeySecret.value();
    if (!apiKey || typeof apiKey !== "string") {
      console.error("openaiChatCompletion: OPENAI_API_KEY missing");
      throw new HttpsError(
        "failed-precondition",
        "OpenAI is not configured on the server. Set OPENAI_API_KEY for this function."
      );
    }

    const data = request.data || {};
    const kind = typeof data.kind === "string" ? data.kind : "text";

    if (kind === "text") {
      const prompt = data.prompt;
      const model = typeof data.model === "string" ? data.model : "gpt-4-turbo-preview";
      const maxTokens = clampInt(data.maxTokens, 1, 8192, 500);
      const temperature = clampNumber(data.temperature, 0, 2, 0.7);
      if (!prompt || typeof prompt !== "string") {
        throw new HttpsError("invalid-argument", "Missing or invalid prompt");
      }
      const body = {
        model,
        messages: [{ role: "user", content: prompt }],
        max_tokens: maxTokens,
        temperature,
      };
      const text = await forwardToOpenAI(apiKey, body);
      return { text };
    }

    if (kind === "vision") {
      const prompt = data.prompt;
      const model = typeof data.model === "string" ? data.model : "gpt-4o";
      const maxTokens = clampInt(data.maxTokens, 1, 4096, 500);
      const temperature = clampNumber(data.temperature, 0, 2, 0.3);
      const imageURLs = data.imageURLs;
      if (!prompt || typeof prompt !== "string") {
        throw new HttpsError("invalid-argument", "Missing or invalid prompt");
      }
      if (!Array.isArray(imageURLs) || imageURLs.length === 0) {
        throw new HttpsError("invalid-argument", "Missing imageURLs");
      }
      const content = [{ type: "text", text: prompt }];
      for (const url of imageURLs) {
        if (typeof url === "string" && url.length > 0 && content.length < 20) {
          content.push({ type: "image_url", image_url: { url } });
        }
      }
      if (content.length < 2) {
        throw new HttpsError("invalid-argument", "No valid image URLs");
      }
      const body = {
        model,
        messages: [{ role: "user", content }],
        max_tokens: maxTokens,
        temperature,
      };
      const text = await forwardToOpenAI(apiKey, body);
      return { text };
    }

    if (kind === "messages") {
      const messages = data.messages;
      const model = typeof data.model === "string" ? data.model : "gpt-4o";
      const maxTokens = clampInt(data.maxTokens, 1, 8192, 1000);
      const temperature = clampNumber(data.temperature, 0, 2, 0.3);
      if (!Array.isArray(messages) || messages.length === 0) {
        throw new HttpsError("invalid-argument", "Missing messages");
      }
      const body = {
        model,
        messages,
        max_tokens: maxTokens,
        temperature,
      };
      const text = await forwardToOpenAI(apiKey, body);
      return { text };
    }

    throw new HttpsError("invalid-argument", `Unknown kind: ${kind}`);
  }
);

function clampInt(value, min, max, fallback) {
  const n = Number.parseInt(String(value), 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}

function clampNumber(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}

async function forwardToOpenAI(apiKey, body) {
  const res = await fetch(OPENAI_CHAT_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const rawText = await res.text();
  if (!res.ok) {
    let msg = `OpenAI HTTP ${res.status}`;
    try {
      const j = JSON.parse(rawText);
      if (j.error && j.error.message) {
        msg = j.error.message;
      }
    } catch (_) {
      // keep generic
    }
    console.error("openaiChatCompletion OpenAI error:", res.status, rawText.slice(0, 500));
    throw new HttpsError("internal", msg);
  }
  let json;
  try {
    json = JSON.parse(rawText);
  } catch (e) {
    throw new HttpsError("internal", "Invalid JSON from OpenAI");
  }
  const text =
    json.choices &&
    json.choices[0] &&
    json.choices[0].message &&
    json.choices[0].message.content;
  if (typeof text !== "string") {
    throw new HttpsError("internal", "Unexpected OpenAI response");
  }
  return text;
}
