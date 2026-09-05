const EXPORT_VERSION = 2;

function todayStamp() {
  return todayDateKey();
}

function slugifyName(name) {
  return String(name)
    .toLowerCase()
    .replace(/[^\wа-яё-]+/gi, "-")
    .replace(/-{2,}/g, "-")
    .replace(/^-|-$/g, "") || "base";
}

function downloadBlob(filename, text, mime) {
  const blob = new Blob([text], { type: mime || "application/json;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
}

function buildBackupPayload() {
  return {
    v: EXPORT_VERSION,
    kind: "base",
    exportedAt: new Date().toISOString(),
    decks: state.decks.map((d) => ({ id: d.id, name: d.name, twoSided: Boolean(d.twoSided) })),
    cards: state.cards.map((c) => ({ id: c.id, deckId: c.deckId, question: c.question, answer: c.answer, status: c.status })),
    history: state.history,
    sessions: state.sessions,
    today: state.today,
  };
}

function exportBaseJson() {
  const payload = buildBackupPayload();
  const stamp = todayStamp();
  downloadBlob(`карточки-база-${stamp}.json`, JSON.stringify(payload, null, 2));
  showToast(`База выгружена: ${payload.decks.length} колод · ${payload.cards.length} карт.`, "ok");
}

function exportDeckJson(deckId) {
  const deck = state.decks.find((d) => d.id === deckId);
  if (!deck) return;
  const cards = cardsInDeck(deckId);
  const payload = {
    v: EXPORT_VERSION,
    kind: "deck",
    exportedAt: new Date().toISOString(),
    deck: { id: deck.id, name: deck.name, twoSided: Boolean(deck.twoSided) },
    cards: cards.map((c) => ({ question: c.question, answer: c.answer, status: c.status })),
  };
  downloadBlob(`колода-${slugifyName(deck.name)}-${todayStamp()}.json`, JSON.stringify(payload, null, 2));
  showToast(`Колода «${deck.name}» выгружена (${cards.length}).`, "ok");
}

function csvField(value) {
  const s = String(value);
  return /[;"\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

function csvSplitLine(line) {
  const out = [];
  let cur = "";
  let inQ = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQ) {
      if (ch === '"') {
        if (line[i + 1] === '"') { cur += '"'; i++; }
        else inQ = false;
      } else cur += ch;
    } else if (ch === '"') inQ = true;
    else if (ch === ";") { out.push(cur); cur = ""; }
    else cur += ch;
  }
  out.push(cur);
  return out.map((f) => f.trim());
}

function exportBaseCsv() {
  const lines = ["deck;question;answer;status"];
  state.decks.forEach((deck) => {
    cardsInDeck(deck.id).forEach((card) => {
      lines.push([deck.name, card.question, card.answer, card.status].map(csvField).join(";"));
    });
  });
  downloadBlob(`карточки-база-${todayStamp()}.csv`, lines.join("\r\n"), "text/csv;charset=utf-8");
  showToast("CSV выгружен.", "ok");
}

function looksLikeCsv(text, filename) {
  if (/\.csv$/i.test(filename || "")) return true;
  const head = text.slice(0, 400);
  return !head.includes("{") && head.includes(";");
}

function parseImportJson(text) {
  const raw = JSON.parse(text);
  if (!isPlainObject(raw)) throw new Error("bad-root");
  if (raw.kind === "deck") {
    const name = raw.deck && typeof raw.deck.name === "string" ? raw.deck.name.trim().slice(0, MAX_NAME_LENGTH) : "";
     if (!name || !Array.isArray(raw.cards)) throw new Error("bad-deck-file");
    const cards = raw.cards
      .filter((c) => isPlainObject(c))
      .map((c) => ({
        question: typeof c.question === "string" ? c.question.trim() : "",
        answer: typeof c.answer === "string" ? c.answer.trim() : "",
        status: VALID_STATUSES.has(c.status) ? c.status : "new",
      }))
      .filter((c) => c.question && c.answer);
    return { kind: "deck", deckName: name, twoSided: Boolean(raw.deck && raw.deck.twoSided), cards };
  }
  const normalized = normalizeState({
    decks: raw.decks,
    cards: raw.cards,
    selectedDeckId: null,
    today: raw.today,
    history: raw.history,
    sessions: raw.sessions,
  });
  return { kind: "base", state: normalized };
}

function parseImportCsv(text) {
  const rows = text.split(/\r?\n/).filter((l) => l.trim());
  if (!rows.length) throw new Error("empty");
  const first = csvSplitLine(rows[0]).map((h) => h.toLowerCase());
  const hasHeader = first.includes("question") && first.includes("answer");
  const body = hasHeader ? rows.slice(1) : rows;
  const width = csvSplitLine(body[0] || "").length;
  const fourCol = width >= 4;
  const cardsByDeck = new Map();
  body.forEach((line) => {
    const cells = csvSplitLine(line);
    if (!cells.some((c) => c)) return;
    const deckName = fourCol ? cells[0] : "";
    const question = fourCol ? cells[1] : cells[0];
    const answer = fourCol ? cells[2] : cells[1];
    const statusRaw = fourCol ? cells[3] : cells[2];
    if (!question || !answer) return;
    const key = fourCol ? deckName.slice(0, MAX_NAME_LENGTH) : "__SELECTED__";
    if (!cardsByDeck.has(key)) cardsByDeck.set(key, []);
    cardsByDeck.get(key).push({ question, answer, status: VALID_STATUSES.has(statusRaw) ? statusRaw : "new" });
  });
  return { kind: "csv", cardsByDeck };
}

let pendingImport = null;

function openDataDialog() {
  const backdrop = document.getElementById("data-backdrop");
  document.getElementById("data-text").textContent = pendingImport.summary;
  showLayer(backdrop);
  lockScroll(true);
  document.getElementById("data-merge").focus();
}

function closeDataDialog() {
  const backdrop = document.getElementById("data-backdrop");
  hideLayer(backdrop);
  lockScroll(false);
  const trigger = document.getElementById("settings-btn");
  if (!document.getElementById("settings-backdrop").classList.contains("is-open")) {
    if (canFocus(trigger)) trigger.focus();
  }
  pendingImport = null;
}

function summarizeImport(parsed, fileName) {
  if (parsed.kind === "deck") return `Файл «${fileName}»: колода «${parsed.deckName}», карт: ${parsed.cards.length}.`;
  if (parsed.kind === "csv") {
    const decks = [...parsed.cardsByDeck.keys()].filter((k) => k !== "__SELECTED__");
    const total = [...parsed.cardsByDeck.values()].reduce((n, arr) => n + arr.length, 0);
    return `CSV «${fileName}»: строк с карточками ${total}${decks.length ? `, колод: ${decks.length}` : " → в текущую колоду"}.`;
  }
  const st = parsed.state;
  return `База «${fileName}»: колод ${st.decks.length}, карт ${st.cards.length}, журнал ${st.sessions.length}.`;
}

function handleImportText(text, fileName) {
  try {
    const clean = text.replace(/^\uFEFF/, "");
    const parsed = looksLikeCsv(clean, fileName) ? parseImportCsv(clean) : parseImportJson(clean);
    pendingImport = { parsed, fileName };
    if (parsed.kind === "csv") {
      applyImport(parsed, "merge");
      return;
    }
    pendingImport.summary = summarizeImport(parsed, fileName);
    openDataDialog();
  } catch (error) {
    showToast("Не удалось разобрать файл — проверь формат.", "warn");
  }
}

function applyCsvImport(parsed) {
  let added = 0;
  let skipped = 0;
  parsed.cardsByDeck.forEach((cards, key) => {
    let deckId;
    if (key === "__SELECTED__") {
      const deck = selectedDeck();
      if (!deck) { skipped += cards.length; return; }
      deckId = deck.id;
    } else {
      let deck = state.decks.find((d) => d.name.toLowerCase() === key.toLowerCase());
      if (!deck) {
        deck = { id: uid(), name: key };
        state.decks.push(deck);
      }
      deckId = deck.id;
    }
    const existing = new Set(
      cardsInDeck(deckId).map((c) => c.question + "\u0000" + c.answer)
    );
    cards.forEach(({ question, answer, status }) => {
      const sig = question + "\u0000" + answer;
      if (existing.has(sig)) { skipped++; return; }
      existing.add(sig);
      state.cards.push({ id: uid(), deckId, question, answer, status });
      added++;
    });
  });
  saveState();
  render();
  const total = added + skipped;
  showToast(
    `Импорт CSV: добавлено ${added}${skipped ? ` · пропущено ${skipped}` : ""}.`,
    total ? "ok" : "warn"
  );
}

function applyImport(parsed, mode) {
  closeDataDialog();
  if (parsed.kind === "csv") { applyCsvImport(parsed); return; }

  if (mode === "replace") {
    if (parsed.kind === "deck") {
      state.decks = [{ id: uid(), name: parsed.deckName, twoSided: parsed.twoSided }];
      state.cards = parsed.cards.map((c) => ({ id: uid(), deckId: state.decks[0].id, ...c }));
    } else {
      const next = parsed.state;
      state.decks = next.decks;
      state.cards = next.cards;
      state.history = next.history;
      state.sessions = next.sessions.slice(-200);
      state.today = next.today;
      state.selectedDeckId = state.decks[0] ? state.decks[0].id : null;
    }
    resetTodayIfNeeded();
  } else if (parsed.kind === "deck") {
    let deck = state.decks.find((d) => d.name.toLowerCase() === parsed.deckName.toLowerCase());
    if (!deck) {
      deck = { id: uid(), name: parsed.deckName, twoSided: parsed.twoSided };
      state.decks.push(deck);
    } else if (parsed.twoSided) {
      deck.twoSided = true;
    }
    const existing = new Set(cardsInDeck(deck.id).map((c) => c.question + "\u0000" + c.answer));
    parsed.cards.forEach(({ question, answer, status }) => {
      const sig = question + "\u0000" + answer;
      if (existing.has(sig)) return;
      existing.add(sig);
      state.cards.push({ id: uid(), deckId: deck.id, question, answer, status });
    });
  } else {
    const idMap = new Map();
    parsed.state.decks.forEach((incoming) => {
      const twin = state.decks.find((d) => d.name.toLowerCase() === incoming.name.toLowerCase());
      idMap.set(incoming.id, twin ? twin.id : null);
    });
    parsed.state.decks.forEach((incoming) => {
      if (idMap.get(incoming.id) === null) {
        const fresh = { id: uid(), name: incoming.name };
        state.decks.push(fresh);
        idMap.set(incoming.id, fresh.id);
      }
    });
    const sigIndex = new Map();
    state.cards.forEach((c) => sigIndex.set(c.deckId + "\u0000" + c.question + "\u0000" + c.answer, true));
    parsed.state.cards.forEach((card) => {
      const deckId = idMap.get(card.deckId);
      if (!deckId) return;
      const sig = deckId + "\u0000" + card.question + "\u0000" + card.answer;
      if (sigIndex.has(sig)) return;
      sigIndex.set(sig, true);
      state.cards.push({ id: uid(), deckId, question: card.question, answer: card.answer, status: card.status });
    });
    Object.keys(parsed.state.history || {}).forEach((oldDeckId) => {
      const deckId = idMap.get(oldDeckId);
      if (!deckId) return;
      const days = parsed.state.history[oldDeckId];
      if (!state.history[deckId]) state.history[deckId] = {};
      Object.keys(days).forEach((date) => {
        const day = days[date];
        const cur = state.history[deckId][date] || { known: 0, unknown: 0 };
        state.history[deckId][date] = { known: cur.known + day.known, unknown: cur.unknown + day.unknown };
      });
    });
    parsed.state.sessions.forEach((s) => {
      const deckId = idMap.get(s.deckId);
      if (deckId) state.sessions.push({ ...s, deckId });
    });
    state.sessions = state.sessions
      .map((item, index) => ({ item, index }))
      .sort((a, b) => b.item.date.localeCompare(a.item.date) || a.index - b.index)
      .slice(0, MAX_SESSIONS)
      .map(({ item }) => item);
  }
  if (!state.decks.find((d) => d.id === state.selectedDeckId)) {
    state.selectedDeckId = state.decks[0] ? state.decks[0].id : null;
  }
  resetStudy();
  saveState();
  render();
  const modeText = mode === "replace" ? "База заменена." : "Готово: данные слиты.";
  showToast(modeText, "ok");
}

function bindDataEvents() {
  document.getElementById("export-all-btn").addEventListener("click", () => {
    exportBaseJson();
    closeSettingsModal();
  });
  document.getElementById("export-csv-btn").addEventListener("click", () => {
    exportBaseCsv();
    closeSettingsModal();
  });

  const fileInput = document.getElementById("import-file");
  document.getElementById("import-btn").addEventListener("click", () => fileInput.click());
  fileInput.addEventListener("change", () => {
    const file = fileInput.files && fileInput.files[0];
    fileInput.value = "";
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => handleImportText(String(reader.result || ""), file.name);
    reader.readAsText(file, "utf-8");
  });

  const backdrop = document.getElementById("data-backdrop");
  document.getElementById("data-merge").addEventListener("click", () => {
    if (pendingImport) applyImport(pendingImport.parsed, "merge");
  });
  document.getElementById("data-replace").addEventListener("click", () => {
    if (pendingImport) applyImport(pendingImport.parsed, "replace");
  });
  document.getElementById("data-cancel").addEventListener("click", closeDataDialog);
  backdrop.addEventListener("click", (event) => {
    if (event.target.id === "data-backdrop") closeDataDialog();
  });
  backdrop.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.stopPropagation();
      closeDataDialog();
    } else {
      trapTabKey(backdrop, event);
    }
  });
}

bindDataEvents();
