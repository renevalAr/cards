function lastDays(count) {
  const days = [];
  const now = new Date();
  for (let i = count - 1; i >= 0; i -= 1) {
    days.push(dateKey(new Date(now.getFullYear(), now.getMonth(), now.getDate() - i)));
  }
  return days;
}

function countUp(el, target) {
  if (reduceMotion() || !Number.isFinite(target) || target <= 0 || target > 9999) {
    el.textContent = target;
    return;
  }
  const t0 = performance.now();
  const duration = 550;
  const tick = (now) => {
    const p = Math.min(1, (now - t0) / duration);
    const eased = 1 - Math.pow(1 - p, 3);
    el.textContent = Math.round(target * eased);
    if (p < 1) requestAnimationFrame(tick);
    else el.textContent = target;
  };
  requestAnimationFrame(tick);
}

function openStats() {
  closeMenuPop();
  closeDeckPicker();
  closeSummary();
  const backdrop = document.getElementById("stats-backdrop");
  showLayer(backdrop);
  lockScroll(true);
  renderStatsWindow();
  document.querySelector(".stats-window").focus();
}

function closeStats() {
  const backdrop = document.getElementById("stats-backdrop");
  const menuOpen = document.getElementById("menu-backdrop").classList.contains("is-open");
  hideLayer(backdrop);
  if (!menuOpen) lockScroll(false);
  closeDeckStats();
  if (menuOpen) {
    const cover = document.querySelector(".menu-cover");
    if (canFocus(cover)) cover.focus();
  }
}

function renderDayBars(days, week) {
  const wrap = makeEl("span", "stats-days");
  const max = Math.max(
    1,
    ...week.map((date) => {
      const day = days[date];
      return day ? day.known + day.unknown : 0;
    })
  );
  week.forEach((date, index) => {
    const day = days[date];
    const count = day ? day.known + day.unknown : 0;
    const col = makeEl("span", "stats-day");
    col.dataset.count = count;
    col.setAttribute("aria-label", `${date} — ${count}`);
    const bar = makeEl("i");
    const targetH = count ? Math.max(3, Math.round((count / max) * 26)) + "px" : "2px";
    bar.style.height = "2px";
    if (!count) bar.classList.add("is-empty");
    const applyHeight = () => { bar.style.height = targetH; };
    if (reduceMotion()) applyHeight();
    else setTimeout(applyHeight, 120 + index * 45);
    col.appendChild(bar);
    col.append(makeEl("span", "", date.slice(8, 10)));
    wrap.appendChild(col);
  });
  return wrap;
}

function renderStatsWindow() {
  const decks = state.decks;
  const today = getTodayStats();
  const allTime = getAllTimeStats();
  const hasStudy = decks.some((deck) => cardsInDeck(deck.id).length);

  countUp(document.getElementById("stats-total"), state.cards.length);
  countUp(document.getElementById("stats-today"), today.known + today.unknown);
  countUp(document.getElementById("stats-alltime"), allTime.known + allTime.unknown);

  const list = document.getElementById("stats-list");
  const empty = document.getElementById("stats-empty");
  list.textContent = "";

  if (!hasStudy) {
    list.classList.add("hidden");
    empty.classList.remove("hidden");
    document.getElementById("stats-go-study").textContent = decks.length ? "Учить" : "Создать колоду";
    return;
  }
  empty.classList.add("hidden");
  list.classList.remove("hidden");

  const week = lastDays(7);
  const frag = document.createDocumentFragment();
  decks.forEach((deck) => {
    const cards = cardsInDeck(deck.id);
    if (!cards.length) return;
    const known = cards.filter((card) => card.status === "known").length;
    const unknown = cards.filter((card) => card.status === "unknown").length;
    const percent = cards.length ? Math.round((known / cards.length) * 100) : 0;
    const days = getDeckHistory(deck.id);

    const item = makeEl("button", "stats-item");
    item.type = "button";
    item.dataset.deckId = deck.id;
    item.append(makeEl("span", "stats-item-name", deck.name));
    item.append(
      makeEl(
        "span",
        "stats-item-counts",
        `${cards.length} карт. · знаю ${known} · не знаю ${unknown}`
      )
    );
    const bar = makeEl("span", "stats-bar");
    const fill = makeEl("i");
    fill.style.width = percent + "%";
    bar.appendChild(fill);
    item.appendChild(bar);
    item.appendChild(renderDayBars(days, week));
    item.addEventListener("click", () => openDeckStats(deck.id));
    frag.appendChild(item);
  });
  list.appendChild(frag);
}

function openDeckStats(deckId) {
  const deck = state.decks.find((item) => item.id === deckId);
  if (!deck) return;
  document.getElementById("stats-deck-title").textContent = deck.name;
  const sessions = state.sessions
    .map((item, index) => ({ item, index }))
    .filter(({ item }) => item.deckId === deckId)
    .sort((a, b) => b.item.date.localeCompare(a.item.date) || b.index - a.index)
    .map(({ item }) => item);

  const box = document.getElementById("stats-sessions");
  box.textContent = "";
  if (!sessions.length) {
    box.append(makeEl("p", "stats-empty-sessions", "Завершённых повторений пока нет."));
  } else {
    const frag = document.createDocumentFragment();
    sessions.forEach((session) => {
      const total = session.known + session.unknown;
      const percent = total ? Math.round((session.known / total) * 100) : 0;
      const item = makeEl("div", "session-item");
      const head = makeEl("div", "session-item-head");
      head.append(makeEl("span", "", session.date));
      head.append(
        makeEl("span", "", `${total} карт. · знаю ${session.known} · не знаю ${session.unknown}`)
      );
      const bar = makeEl("span", "session-bar");
      const fill = makeEl("i");
      fill.style.width = percent + "%";
      bar.appendChild(fill);
      item.appendChild(head);
      item.appendChild(bar);
      frag.appendChild(item);
    });
    box.appendChild(frag);
  }

  document.getElementById("stats-main").classList.add("hidden");
  document.getElementById("stats-deck").classList.remove("hidden");
  document.getElementById("stats-back").focus();
}

function closeDeckStats() {
  document.getElementById("stats-main").classList.remove("hidden");
  document.getElementById("stats-deck").classList.add("hidden");
}

function bindStatsEvents() {
  const backdrop = document.getElementById("stats-backdrop");

  document.getElementById("stats-close").addEventListener("click", closeStats);
  document.getElementById("stats-go-study").addEventListener("click", () => {
    closeStats();
    bigStudy();
  });
  document.getElementById("stats-back").addEventListener("click", closeDeckStats);

  backdrop.addEventListener("click", (event) => {
    if (event.target.id === "stats-backdrop") closeStats();
  });
  backdrop.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.stopPropagation();
      closeStats();
    } else {
      trapTabKey(backdrop, event);
    }
  });
}

bindStatsEvents();
