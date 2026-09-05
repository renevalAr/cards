const PALETTE_META = [
  ["ember", "Охра", "#e85d04"],
  ["sea", "Синий", "#156d8a"],
  ["moss", "Мох", "#4a7a32"],
  ["berry", "Ягода", "#9b2d5c"],
  ["violet", "Фиолет", "#6b3fa0"],
  ["gold", "Золото", "#c3922d"],
  ["crimson", "Алый", "#c0392b"],
  ["teal", "Бирюза", "#0f7a6c"],
  ["slate", "Графит", "#4d5d73"],
  ["indigo", "Индиго", "#3949ab"],
];

const VALID_PALETTES = PALETTE_META.map((item) => item[0]);

function renderThemeDots() {
  document.querySelectorAll(".theme-dots").forEach((box) => {
    box.textContent = "";
    const frag = document.createDocumentFragment();
    PALETTE_META.forEach(([id, title, color]) => {
      const dot = document.createElement("button");
      dot.type = "button";
      dot.className = "theme-dot";
      dot.dataset.palette = id;
      dot.title = title;
      dot.setAttribute("aria-label", title);
      dot.style.backgroundColor = color;
      frag.appendChild(dot);
    });
    box.appendChild(frag);
  });
}

function makeEl(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function badgeFor(card) {
  if (card.status === "known") return makeEl("span", "badge known", "знаю");
  if (card.status === "unknown") return makeEl("span", "badge unknown", "не знаю");
  return makeEl("span", "badge", "новая");
}

function cardMatchesFilter(card) {
  const filter = state.cardFilter;
  return filter === "all" || card.status === filter;
}

function filterLabel(filter) {
  if (filter === "known") return "знаю";
  if (filter === "unknown") return "не знаю";
  return "новая";
}

function searchMatches(card, q) {
  return !q || card.question.toLowerCase().includes(q) || card.answer.toLowerCase().includes(q);
}

function appendHighlighted(parent, text, q) {
  if (!q) {
    parent.append(text);
    return;
  }
  const lower = text.toLowerCase();
  let from = 0;
  for (;;) {
    const idx = lower.indexOf(q, from);
    if (idx === -1) break;
    if (idx > from) parent.append(text.slice(from, idx));
    parent.append(makeEl("mark", "search-hit", text.slice(idx, idx + q.length)));
    from = idx + q.length;
  }
  if (from < text.length) parent.append(text.slice(from));
}

function clearCardSearch() {
  state.searchQuery = "";
  document.getElementById("card-search").value = "";
  document.getElementById("card-search-clear").classList.remove("is-visible");
  renderCardRows();
}

function renderDeckList() {
  const list = document.getElementById("deck-list");
  list.textContent = "";
  const counts = new Map();
  for (const card of state.cards) {
    counts.set(card.deckId, (counts.get(card.deckId) || 0) + 1);
  }
  const frag = document.createDocumentFragment();
  state.decks.forEach((deck) => {
    const button = makeEl(
      "button",
      "deck-item" + (deck.id === state.selectedDeckId ? " is-active" : "")
    );
    button.type = "button";
    button.textContent = deck.name;
    button.append(makeEl("small", "", `${counts.get(deck.id) || 0} карт.`));
    button.addEventListener("click", () => {
      state.selectedDeckId = deck.id;
      state.tab = "edit";
      resetStudy();
      resetCardForm();
      clearCardSearch();
      saveState();
      render();
    });
    frag.appendChild(button);
  });
  list.appendChild(frag);
}

function renderCardFilters() {
  document.querySelectorAll("#card-filters .filter-btn").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.filter === state.cardFilter);
  });
}

let dragCardId = null;

function clearDropIndicators() {
  document.querySelectorAll("#card-rows li").forEach((li) => li.classList.remove("drop-above", "drop-below"));
}

function moveCardWithinDeck(cardId, anchorId, before) {
  const from = state.cards.findIndex((card) => card.id === cardId);
  if (from === -1) return;
  const [moved] = state.cards.splice(from, 1);
  const deckCards = state.cards.filter((card) => card.deckId === state.selectedDeckId);
  let anchorIdx = state.cards.findIndex((card) => card.id === anchorId);
  if (anchorIdx === -1) {
    const last = deckCards[deckCards.length - 1];
    anchorIdx = last ? state.cards.findIndex((card) => card.id === last.id) : state.cards.length;
    before = false;
  }
  state.cards.splice(before ? anchorIdx : anchorIdx + 1, 0, moved);
  saveState();
  renderCardRows();
  if (typeof Auth !== 'undefined' && Auth.getUser()) {
    const ids = cardsInDeck(state.selectedDeckId).map(c => c.id);
    fetch('/api/cards/reorder', {
      method: 'PUT',
      headers: {'Content-Type': 'application/json'},
      credentials: 'include',
      body: JSON.stringify({card_ids: ids})
    }).catch(function(err) {
      console.warn("Card reorder sync failed:", err);
      if (typeof showToast === "function") showToast("Ошибка синхронизации порядка карточек");
    });
  }
}

let rowsBound = false;

function bindCardRowsDelegation() {
  const rows = document.getElementById("card-rows");
  if (rowsBound || !rows) return;
  rowsBound = true;

  const liOf = (target) => target.closest && target.closest("li[data-card-id]");

  rows.addEventListener("click", (event) => {
    const button = event.target.closest(".row-actions button");
    if (!button) return;
    const li = liOf(button);
    if (!li) return;
    if (button.classList.contains("btn-danger")) deleteCard(li.dataset.cardId);
    else startEditCard(li.dataset.cardId);
  });

  rows.addEventListener("dragstart", (event) => {
    const li = liOf(event.target);
    if (!li) return;
    dragCardId = li.dataset.cardId;
    li.classList.add("dragging");
    if (event.dataTransfer) {
      event.dataTransfer.setData("text/plain", dragCardId);
      event.dataTransfer.effectAllowed = "move";
    }
  });
  rows.addEventListener("dragend", () => {
    clearDropIndicators();
    document.querySelectorAll("#card-rows li.dragging").forEach((li) => li.classList.remove("dragging"));
    dragCardId = null;
  });
  rows.addEventListener("dragover", (event) => {
    const li = liOf(event.target);
    if (!li || !dragCardId || dragCardId === li.dataset.cardId) return;
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = "move";
    const r = li.getBoundingClientRect();
    const before = event.clientY < r.top + r.height / 2;
    li.classList.toggle("drop-above", before);
    li.classList.toggle("drop-below", !before);
  });
  rows.addEventListener("dragleave", (event) => {
    const li = liOf(event.target);
    if (li) li.classList.remove("drop-above", "drop-below");
  });
  rows.addEventListener("drop", (event) => {
    const li = liOf(event.target);
    if (!li) return;
    event.preventDefault();
    const r = li.getBoundingClientRect();
    const before = event.clientY < r.top + r.height / 2;
    clearDropIndicators();
    if (dragCardId && dragCardId !== li.dataset.cardId) moveCardWithinDeck(dragCardId, li.dataset.cardId, before);
    dragCardId = null;
  });
}

function renderCardRows() {
  const rows = document.getElementById("card-rows");
  rows.textContent = "";
  const all = cardsInDeck(state.selectedDeckId);
  const q = state.searchQuery.trim().toLowerCase();
  const cards = all.filter((card) => cardMatchesFilter(card) && searchMatches(card, q));

  if (!cards.length) {
    let message;
    if (!all.length) message = "Карточек пока нет — заполни форму выше.";
    else if (q) message = `По запросу «${state.searchQuery.trim()}» ничего не найдено.`;
    else message = `Нет карточек со статусом «${filterLabel(state.cardFilter)}».`;
    rows.append(makeEl("li", "empty-row", message));
    return;
  }

  const frag = document.createDocumentFragment();
  cards.forEach((card, index) => {
    const li = makeEl("li");
    li.dataset.cardId = card.id;
    li.draggable = true;
    if (index < 18) li.style.animationDelay = index * 30 + "ms";

    const body = makeEl("div");
    const qp = makeEl("p");
    appendHighlighted(qp, card.question, q);
    const ap = makeEl("p", "answer");
    appendHighlighted(ap, card.answer, q);
    body.append(qp, ap, badgeFor(card));
    li.appendChild(body);

if (window.imgGet) {
      imgGet(card.id).then((dataUrl) => {
        if (dataUrl && li.isConnected) {
          const thumb = new Image();
          thumb.className = "row-thumb";
          thumb.alt = "";
          thumb.src = dataUrl;
          li.querySelector("div").appendChild(thumb);
        }
      }).catch(function (err) {
        console.warn("Card image load failed:", err);
      });
    }

    const actions = makeEl("div", "row-actions");
    const edit = makeEl("button", "btn", "Изменить");
    edit.type = "button";
    const del = makeEl("button", "btn btn-danger", "Удалить");
    del.type = "button";
    actions.append(edit, del);
    li.appendChild(actions);

    frag.appendChild(li);
  });
  rows.appendChild(frag);
  rows.classList.toggle("no-anim", cards.length > 60);
  bindCardRowsDelegation();
}

function updateCardRowStatus(cardId) {
  const card = state.cards.find((item) => item.id === cardId);
  if (!card) return;
  if (!cardMatchesFilter(card)) {
    renderCardRows();
    return;
  }
  const li = document
    .getElementById("card-rows")
    .querySelector(`li[data-card-id="${CSS.escape(cardId)}"]`);
  if (!li) return;
  const fresh = badgeFor(card);
  const old = li.querySelector(".badge");
  if (old) {
    old.replaceWith(fresh);
  } else {
    li.querySelector("div").append(fresh);
  }
}

function renderStats() {
  const cards = cardsInDeck(state.selectedDeckId);
  const known = cards.filter((card) => card.status === "known").length;
  const unknown = cards.filter((card) => card.status === "unknown").length;
  document.getElementById("stats").textContent =
    `Всего ${cards.length} · знаю ${known} · не знаю ${unknown}`;
}

function resetCardForm() {
  document.getElementById("card-id").value = "";
  document.getElementById("card-question").value = "";
  document.getElementById("card-answer").value = "";
  document.getElementById("save-card-btn").textContent = "Добавить карточку";
  document.getElementById("cancel-edit-btn").classList.add("hidden");
  if (window.resetImageDraft) resetImageDraft();
}

function refreshIndicators() {
  const list = document.getElementById("deck-list");
  if (list) {
    let marker = list.querySelector(".deck-marker");
    if (!marker) {
      marker = makeEl("span", "deck-marker");
      list.appendChild(marker);
    }
    const active = list.querySelector(".deck-item.is-active");
    if (active) {
      marker.classList.add("is-on");
      marker.style.top = active.offsetTop + "px";
      marker.style.height = active.offsetHeight + "px";
    } else {
      marker.classList.remove("is-on");
    }
  }
  const tabs = document.querySelector(".tabs");
  if (tabs) {
    let ind = tabs.querySelector(".tab-indicator");
    if (!ind) {
      ind = makeEl("span", "tab-indicator");
      tabs.appendChild(ind);
    }
    const at = tabs.querySelector(".tab.is-active");
    if (at) {
      ind.style.left = at.offsetLeft + 8 + "px";
      ind.style.width = Math.max(24, at.offsetWidth - 16) + "px";
    }
  }
}

let prevDeckId = null;

function render() {
  const deck = selectedDeck();
  document.title = deck ? `${deck.name} — Карточки` : "Карточки";
  document.getElementById("empty-state").classList.toggle("hidden", Boolean(deck));
  document.getElementById("workspace").classList.toggle("hidden", !deck);
  renderDeckList();
  if (!deck) {
    prevDeckId = null;
    return;
  }

  const workspaceEl = document.getElementById("workspace");
  if (prevDeckId && deck.id !== prevDeckId && !reduceMotion()) {
    workspaceEl.classList.remove("crossfade");
    void workspaceEl.offsetWidth;
    workspaceEl.classList.add("crossfade");
  }
  prevDeckId = deck.id;

  document.getElementById("deck-title").textContent = deck.name;
  renderStats();
  renderCardFilters();
  renderCardRows();

  const editTab = state.tab === "edit";
  document.getElementById("tab-edit").classList.toggle("is-active", editTab);
  document.getElementById("tab-study").classList.toggle("is-active", !editTab);
  document.getElementById("tab-edit").setAttribute("aria-selected", String(editTab));
  document.getElementById("tab-study").setAttribute("aria-selected", String(!editTab));
  document.getElementById("panel-edit").classList.toggle("hidden", !editTab);
  document.getElementById("panel-study").classList.toggle("hidden", editTab);

  const cards = cardsInDeck(deck.id);
  if (!cards.length && state.searchQuery) {
    state.searchQuery = "";
    document.getElementById("card-search").value = "";
    document.getElementById("card-search-clear").classList.remove("is-visible");
  }
  document.getElementById("card-filters").classList.toggle("hidden", cards.length === 0);
  document.getElementById("card-search-row").classList.toggle("hidden", cards.length === 0);
  document.getElementById("study-empty").classList.toggle("hidden", cards.length > 0);
  document.getElementById("study-board").classList.toggle("hidden", cards.length === 0);
  if (cards.length > 0 && !editTab) {
    if (!state.studyOrder.length) startStudyShuffle();
    showStudyCard();
    syncStudyView();
  }
  syncTwoSidedBtn();
  refreshIndicators();
}

const AUTO_QUERY = "(prefers-color-scheme: dark)";

function systemDark() {
  return window.matchMedia(AUTO_QUERY).matches;
}

function modePref() {
  const attr = document.documentElement.dataset.modePref;
  if (attr === "auto" || attr === "light" || attr === "dark") return attr;
  try {
    const v = localStorage.getItem(MODE_KEY);
    return v === "auto" || v === "light" || v === "dark" ? v : "light";
  } catch {
    return "light";
  }
}

function effectiveMode(pref) {
  return pref === "auto" ? (systemDark() ? "dark" : "light") : pref;
}

function bindAutoTheme() {
  const mq = window.matchMedia(AUTO_QUERY);
  const handler = () => {
    if (modePref() !== "auto") return;
    applyAppearance(
      { mode: "auto" },
      { clientX: window.innerWidth / 2, clientY: window.innerHeight / 2 }
    );
  };
  if (mq.addEventListener) mq.addEventListener("change", handler);
  else if (mq.addListener) mq.addListener(handler);
}

function syncAppearanceButtons() {
  const pref = modePref();
  document.querySelectorAll("#mode-switch [data-mode], #menu-mode-switch [data-mode]").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.mode === pref);
  });
  document.querySelectorAll(".theme-dot").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.palette === palettePref());
  });
}

function palettePref() {
  return document.documentElement.dataset.palette || "ember";
}

function fontSizePref() {
  const attr = document.documentElement.dataset.fontsize;
  if (attr === "s" || attr === "m" || attr === "l") return attr;
  const v = localStorage.getItem(FONT_KEY);
  return v === "s" || v === "l" ? v : "m";
}

function applyFontSize(size) {
  if (size !== "s" && size !== "m" && size !== "l") return;
  document.documentElement.dataset.fontsize = size;
  try {
    localStorage.setItem(FONT_KEY, size);
  } catch (error) {
    console.warn("Не удалось сохранить размер текста", error);
  }
  syncFontButtons();
}

function syncFontButtons() {
  const pref = fontSizePref();
  document.querySelectorAll("#fontsize-switch [data-size]").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.size === pref);
  });
}

async function applyAppearance({ mode, palette }, event) {
  const root = document.documentElement;
  const validModes = ["light", "dark", "auto"];
  const nextMode = validModes.includes(mode) ? mode : modePref();
  const nextPalette = VALID_PALETTES.includes(palette) ? palette : palettePref();
  if (nextMode === modePref() && nextPalette === palettePref() && root.dataset.mode === effectiveMode(nextMode)) return;

  const apply = () => {
    root.dataset.modePref = nextMode;
    root.dataset.mode = effectiveMode(nextMode);
    root.dataset.palette = nextPalette;
    try {
      localStorage.setItem(MODE_KEY, nextMode);
      localStorage.setItem(PALETTE_KEY, nextPalette);
    } catch (error) {
      console.warn("Не удалось сохранить тему", error);
    }
    syncAppearanceButtons();
  };

  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduce || !event || !document.startViewTransition) {
    apply();
    return;
  }

  const source = (event.target && event.target.closest && event.target.closest(".theme-dot, .mode-switch .btn, .btn")) || event.currentTarget || event.target;
  let x = Number.isFinite(event.clientX) ? event.clientX : window.innerWidth / 2;
  let y = Number.isFinite(event.clientY) ? event.clientY : window.innerHeight / 2;
  if (source && source.getBoundingClientRect) {
    const r = source.getBoundingClientRect();
    if (r.width || r.height) {
      x = r.left + r.width / 2;
      y = r.top + r.height / 2;
    }
  }
  x = Math.max(0, Math.min(x, window.innerWidth));
  y = Math.max(0, Math.min(y, window.innerHeight));

  const bloom = document.getElementById("theme-bloom");
  if (bloom) {
    const px = ((x / Math.max(1, window.innerWidth)) * 100).toFixed(2) + "%";
    const py = ((y / Math.max(1, window.innerHeight)) * 100).toFixed(2) + "%";
    document.documentElement.style.setProperty("--bloom-x", px);
    document.documentElement.style.setProperty("--bloom-y", py);
    bloom.style.setProperty("--bloom-x", px);
    bloom.style.setProperty("--bloom-y", py);
    bloom.classList.remove("is-blooming");
    void bloom.offsetWidth;
    bloom.classList.add("is-blooming");
  }

  const transition = document.startViewTransition(apply);
  transition.finished.catch(() => {});
}



