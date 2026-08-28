const STORAGE_KEY = "flashcards-app-v1";
const CORRUPT_KEY = "flashcards-app-v1-corrupt";
const MODE_KEY = "flashcards-mode";
const PALETTE_KEY = "flashcards-palette";
const ONBOARD_KEY = "flashcards-onboarded";
const FONT_KEY = "flashcards-fontsize";
const VALID_STATUSES = new Set(["new", "known", "unknown"]);
const MAX_NAME_LENGTH = 80;
const MAX_SESSIONS = 200;
const SCHEMA_VERSION = 1;

function migrateSchema(raw) {
  if (!isPlainObject(raw)) return raw;
  const v = Number.isFinite(raw.v) ? raw.v : 1;
  if (v > SCHEMA_VERSION) {
    console.warn("Данные из новой версии приложения — загружаю как есть.");
    return raw;
  }
  switch (v) {
    case 1:
    default:
      return raw;
  }
}

let state = {
  decks: [],
  cards: [],
  selectedDeckId: null,
  cardFilter: "all",
  searchQuery: "",
  tab: "edit",
  studyMode: "flip",
  studyOrder: [],
  studyIndex: 0,
  flipped: false,
  today: { date: "", known: 0, unknown: 0 },
  history: {},
  sessions: [],
};

let uidCounter = 0;

function dateKey(date) {
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${date.getFullYear()}-${month}-${day}`;
}

function todayDateKey() {
  return dateKey(new Date());
}

function resetTodayIfNeeded() {
  const key = todayDateKey();
  if (state.today.date !== key) {
    state.today = { date: key, known: 0, unknown: 0 };
  }
}

function getTodayStats() {
  resetTodayIfNeeded();
  return state.today;
}

function uid() {
  if (crypto.randomUUID) return crypto.randomUUID();
  uidCounter += 1;
  return `${Date.now().toString(36)}-${uidCounter.toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function normalizeHistory(saved) {
  const history = {};
  if (!isPlainObject(saved)) return history;
  for (const deckId of Object.keys(saved)) {
    const days = saved[deckId];
    if (!isPlainObject(days)) continue;
    const cleaned = {};
    for (const date of Object.keys(days)) {
      const day = days[date];
      if (!isPlainObject(day)) continue;
      cleaned[date] = {
        known: Number.isFinite(day.known) ? Math.max(0, Math.floor(day.known)) : 0,
        unknown: Number.isFinite(day.unknown) ? Math.max(0, Math.floor(day.unknown)) : 0,
      };
    }
    if (Object.keys(cleaned).length) history[deckId] = cleaned;
  }
  return history;
}

function normalizeSessions(saved) {
  if (!Array.isArray(saved)) return [];
  const sessions = [];
  for (const item of saved) {
    if (!isPlainObject(item)) continue;
    const deckId = typeof item.deckId === "string" && item.deckId ? item.deckId : null;
    const date = typeof item.date === "string" && item.date ? item.date.slice(0, 10) : null;
    if (!deckId || !date) continue;
    sessions.push({
      deckId,
      date,
      known: Number.isFinite(item.known) ? Math.max(0, Math.floor(item.known)) : 0,
      unknown: Number.isFinite(item.unknown) ? Math.max(0, Math.floor(item.unknown)) : 0,
    });
  }
  return sessions;
}

function normalizeState(saved) {
  if (!isPlainObject(saved)) {
    return {
      decks: [],
      cards: [],
      selectedDeckId: null,
      today: { date: todayDateKey(), known: 0, unknown: 0 },
      history: {},
      sessions: [],
    };
  }

  const deckIds = new Set();
  const decks = [];
  if (Array.isArray(saved.decks)) {
    for (const item of saved.decks) {
      if (!isPlainObject(item)) continue;
      const id = typeof item.id === "string" && item.id ? item.id : uid();
      if (deckIds.has(id)) continue;
      const name = typeof item.name === "string" ? item.name.trim().slice(0, MAX_NAME_LENGTH) : "";
      if (!name) continue;
      deckIds.add(id);
      decks.push({ id, name, twoSided: Boolean(item.twoSided) });
    }
  }

  const cards = [];
  if (Array.isArray(saved.cards)) {
    const seen = new Set();
    for (const item of saved.cards) {
      if (!isPlainObject(item)) continue;
      const id = typeof item.id === "string" && item.id ? item.id : uid();
      if (seen.has(id)) continue;
      if (typeof item.deckId !== "string" || !deckIds.has(item.deckId)) continue;
      const question = typeof item.question === "string" ? item.question : "";
      const answer = typeof item.answer === "string" ? item.answer : "";
      if (!question || !answer) continue;
      const status = VALID_STATUSES.has(item.status) ? item.status : "new";
      seen.add(id);
      cards.push({ id, deckId: item.deckId, question, answer, status });
    }
  }

  const selectedDeckId = deckIds.has(saved.selectedDeckId) ? saved.selectedDeckId : null;

  let today = { date: todayDateKey(), known: 0, unknown: 0 };
  if (isPlainObject(saved.today)) {
    const t = saved.today;
    today = {
      date: typeof t.date === "string" && t.date ? t.date : todayDateKey(),
      known: Number.isFinite(t.known) ? Math.max(0, Math.floor(t.known)) : 0,
      unknown: Number.isFinite(t.unknown) ? Math.max(0, Math.floor(t.unknown)) : 0,
    };
  }

  return { decks, cards, selectedDeckId, today, history: normalizeHistory(saved.history), sessions: normalizeSessions(saved.sessions) };
}

let storageAlertTimer = null;

function showToast(message, kind) {
  const el = document.getElementById("storage-alert");
  if (!el) return;
  el.textContent = message;
  el.classList.toggle("is-ok", kind === "ok");
  el.classList.toggle("is-warn", kind === "warn");
  el.hidden = false;
  clearTimeout(storageAlertTimer);
  storageAlertTimer = setTimeout(() => {
    el.hidden = true;
  }, kind === "warn" ? 8000 : 4500);
}

function showStorageAlert() {
  showToast("Не удалось сохранить данные. Хранилище переполнено или недоступно.", "warn");
}

function loadState() {
  let raw;
  try {
    raw = localStorage.getItem(STORAGE_KEY);
  } catch (error) {
    console.warn("Не удалось прочитать хранилище", error);
    showStorageAlert();
  }
  if (!raw) return;
  try {
    const saved = migrateSchema(JSON.parse(raw));
    const normalized = normalizeState(saved);
    state.decks = normalized.decks;
    state.cards = normalized.cards;
    state.selectedDeckId = normalized.selectedDeckId;
    state.today = normalized.today;
    state.history = normalized.history;
    state.sessions = normalized.sessions;
    resetTodayIfNeeded();
  } catch (error) {
    console.warn("Не удалось разобрать сохранённые данные", error);
    try {
      localStorage.setItem(CORRUPT_KEY, raw);
    } catch (backupError) {
      console.warn("Не удалось сохранить бэкап повреждённых данных", backupError);
    }
    showToast("Сохранённые данные повреждены. Копия сохранена — напиши разработчику, чтобы восстановить.", "warn");
  }
}

function isQuotaError(error) {
  return (
    error instanceof DOMException &&
    (error.name === "QuotaExceededError" ||
      error.name === "NS_ERROR_DOM_QUOTA_REACHED" ||
      error.code === 22 ||
      error.code === 1014)
  );
}

function saveState() {
  const payload = () => ({
    v: SCHEMA_VERSION,
    decks: state.decks,
    cards: state.cards,
    selectedDeckId: state.selectedDeckId,
    today: state.today,
    history: state.history,
    sessions: state.sessions,
  });
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(payload()));
  } catch (error) {
    if (isQuotaError(error) && state.sessions.length > 50) {
      try {
        state.sessions = state.sessions.slice(-50);
        localStorage.setItem(STORAGE_KEY, JSON.stringify(payload()));
        showToast("Хранилище переполнено — старые сессии удалены, прогресс сохранён.", "warn");
        return;
      } catch (retryError) {
        console.warn("Не удалось сохранить данные после очистки", retryError);
      }
    }
    console.warn("Не удалось сохранить данные", error);
    if (isQuotaError(error)) {
      showToast("Хранилище переполнено — удалите неиспользуемые колоды или экспортируйте базу.", "warn");
    } else {
      showStorageAlert();
    }
  }
}

function selectedDeck() {
  return state.decks.find((deck) => deck.id === state.selectedDeckId) || null;
}

function cardsInDeck(deckId) {
  return state.cards.filter((card) => card.deckId === deckId);
}

function recordStudy(deckId, status) {
  if (status !== "known" && status !== "unknown") return;
  const key = todayDateKey();
  if (!state.history[deckId]) state.history[deckId] = {};
  const day = state.history[deckId][key] || { known: 0, unknown: 0 };
  day[status] += 1;
  state.history[deckId][key] = day;
}

function recordSession(deckId, known, unknown) {
  state.sessions.push({
    deckId,
    date: todayDateKey(),
    known: Math.max(0, Math.floor(known)),
    unknown: Math.max(0, Math.floor(unknown)),
  });
  if (state.sessions.length > MAX_SESSIONS) state.sessions = state.sessions.slice(-MAX_SESSIONS);
}

function getDeckHistory(deckId) {
  return state.history[deckId] || {};
}

function getAllTimeStats() {
  let known = 0;
  let unknown = 0;
  for (const deckId of Object.keys(state.history)) {
    for (const date of Object.keys(state.history[deckId])) {
      known += state.history[deckId][date].known;
      unknown += state.history[deckId][date].unknown;
    }
  }
  return { known, unknown };
}

function computeStreak() {
  const activity = {};
  for (const deckId of Object.keys(state.history)) {
    for (const date of Object.keys(state.history[deckId])) {
      const day = state.history[deckId][date];
      activity[date] = (activity[date] || 0) + day.known + day.unknown;
    }
  }
  const now = new Date();
  let cursor = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  if (!activity[dateKey(cursor)]) cursor.setDate(cursor.getDate() - 1);
  let streak = 0;
  while (activity[dateKey(cursor)]) {
    streak += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return streak;
}