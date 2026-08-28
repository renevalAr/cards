let menuPopTrigger = null;
let tourStep = -1;
let tourSteps = [];

function pluralDays(count) {
  const last = count % 10;
  const hundred = count % 100;
  if (last === 1 && hundred !== 11) return "день";
  if (last >= 2 && last <= 4 && (hundred < 12 || hundred > 14)) return "дня";
  return "дней";
}

function renderMenu() {
  const today = getTodayStats();
  document.getElementById("menu-today-stats").textContent =
    `изучено ${today.known + today.unknown} · знаю ${today.known} · не знаю ${today.unknown}`;
  const streak = computeStreak();
  const streakEl = document.getElementById("menu-streak");
  if (streak >= 2) {
    streakEl.hidden = false;
    streakEl.innerHTML =
      '<svg class="flame" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2 C 15 7, 19 9.5, 19 14 A 7 7 0 0 1 5 14 C 5 10, 9 8, 12 2 Z" fill="var(--accent-3)"/></svg>Серия · ' +
      streak + " " + pluralDays(streak) + " подряд";
  } else {
    streakEl.hidden = true;
  }
}

function openMenu() {
  const backdrop = document.getElementById("menu-backdrop");
  renderMenu();
  syncAppearanceButtons();
  showLayer(backdrop);
  lockScroll(true);
  backdrop.querySelector(".menu-cover").focus();
  if (!localStorage.getItem(ONBOARD_KEY)) showTour();
}

function closeMenu() {
  const backdrop = document.getElementById("menu-backdrop");
  hideLayer(backdrop);
  lockScroll(false);
  hideTour();
}

function closeAllMenus() {
  closeMenuPop();
  closeDeckPicker();
  closeMenu();
}

function openMenuPop() {
  menuPopTrigger = document.activeElement;
  const pop = document.getElementById("menu-pop-backdrop");
  showLayer(pop);
}

function closeMenuPop() {
  const pop = document.getElementById("menu-pop-backdrop");
  hideLayer(pop);
  if (menuPopTrigger && canFocus(menuPopTrigger)) {
    menuPopTrigger.focus();
  }
  menuPopTrigger = null;
}

function renderDeckPicker() {
  const list = document.getElementById("deck-pick-list");
  list.textContent = "";
  const decks = state.decks;

  if (!decks.length) {
    list.append(makeEl("p", "deck-pick-empty", "Колод пока нет — создай первую."));
    return;
  }

  const frag = document.createDocumentFragment();
  decks.forEach((deck, index) => {
    const cards = cardsInDeck(deck.id);
    const known = cards.filter((card) => card.status === "known").length;
    const unknown = cards.filter((card) => card.status === "unknown").length;
    const percent = cards.length ? Math.round((known / cards.length) * 100) : 0;

    const row = makeEl("div", "deck-pick-item" + (deck.id === state.selectedDeckId ? " is-active" : ""));
    row.style.animationDelay = Math.min(index, 12) * 25 + "ms";
    const main = makeEl("button", "deck-pick-main");
    main.type = "button";
    main.append(makeEl("span", "deck-pick-name", deck.name));
    main.append(
      makeEl(
        "span",
        "deck-pick-counts",
        `${cards.length} карт. · знаю ${known} · не знаю ${unknown}`
      )
    );
    const bar = makeEl("span", "deck-pick-bar");
    const fill = makeEl("i");
    fill.style.width = percent + "%";
    bar.appendChild(fill);
    main.appendChild(bar);
    main.addEventListener("click", () => menuOpenCards(deck.id));
    row.appendChild(main);

    const more = makeEl("button", "btn deck-pick-more");
    more.type = "button";
    more.setAttribute("aria-label", `Действия колоды «${deck.name}»`);
    more.innerHTML =
      '<svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="4" cy="10" r="2"/><circle cx="10" cy="10" r="2"/><circle cx="16" cy="10" r="2"/></svg>';
    more.addEventListener("click", () => openDeckActions(deck.id));
    row.appendChild(more);

    frag.appendChild(row);
  });
  list.appendChild(frag);
}

function openDeckPicker() {
  renderDeckPicker();
  const pop = document.getElementById("deck-pick-backdrop");
  document.getElementById("deck-pick-kicker").textContent = "колоды";
  document.getElementById("deck-pick-title").textContent = "Колоды";
  showLayer(pop);
  pop.querySelector(".modal").focus();
}

function closeDeckPicker() {
  hideLayer(document.getElementById("deck-pick-backdrop"));
  if (document.getElementById("menu-backdrop").classList.contains("is-open")) {
    const cover = document.querySelector(".menu-cover");
    if (canFocus(cover)) cover.focus();
  }
}

function openDeckActions(deckId) {
  const deck = state.decks.find((item) => item.id === deckId);
  if (!deck) return;
  const list = document.getElementById("menu-pop-actions");
  list.textContent = "";
  const frag = document.createDocumentFragment();

  const add = (label, primary, fn, danger) => {
    const button = makeEl(
      "button",
      "btn" + (primary ? " btn-primary" : "") + (danger ? " btn-danger" : ""),
      label
    );
    button.type = "button";
    button.addEventListener("click", () => {
      closeMenuPop();
      fn();
    });
    frag.appendChild(button);
  };

  add("Учить колоду", true, () => menuStudy(deck.id));
  add("Карточки", false, () => menuOpenCards(deck.id));
  if (window.exportDeckJson) {
    add("Экспортировать колоду", false, () => exportDeckJson(deck.id));
  }
  add("Двусторонние карты: " + (deck.twoSided ? "вкл" : "выкл"), false, () => {
    deck.twoSided = !deck.twoSided;
    saveState();
    if (state.selectedDeckId === deck.id) {
      resetStudy();
      render();
    }
    openDeckActions(deck.id);
  });
  add("Переименовать", false, () => {
    state.selectedDeckId = deck.id;
    closeAllMenus();
    renameDeck();
  });
  add("Начать заново", false, () => {
    state.selectedDeckId = deck.id;
    closeAllMenus();
    resetDeckProgress();
  });
  add("Удалить", false, () => {
    state.selectedDeckId = deck.id;
    closeAllMenus();
    deleteDeck();
  }, true);

  document.getElementById("menu-pop-kicker").textContent = "колода";
  document.getElementById("menu-pop-title").textContent = deck.name;
  list.appendChild(frag);
  openMenuPop();
  list.querySelector("button").focus();
}

function menuStudy(deckId) {
  state.selectedDeckId = deckId;
  state.tab = "study";
  resetStudy();
  startStudyShuffle();
  saveState();
  closeAllMenus();
  render();
}

function menuOpenCards(deckId) {
  state.selectedDeckId = deckId;
  state.tab = "edit";
  resetStudy();
  resetCardForm();
  clearCardSearch();
  saveState();
  closeAllMenus();
  render();
}

function bigStudy() {
  const deck = selectedDeck() || state.decks[0];
  if (!deck) {
    closeMenu();
    createDeck();
    return;
  }
  if (!cardsInDeck(deck.id).length) {
    menuOpenCards(deck.id);
    return;
  }
  menuStudy(deck.id);
}

function openFirstDeck() {
  if (!state.decks.length) {
    closeMenu();
    createDeck();
    return;
  }
  openDeckPicker();
}

function showTour() {
  if (tourStep !== -1) return;
  tourSteps = [
    {
      target: "#menu-today",
      side: "below",
      text: "Счётчик показывает, сколько карточек ты изучил сегодня.",
    },
    {
      target: "#menu-study-btn",
      side: "above",
      text: "«Учить» перемешивает карточки выбранной колоды и запускает повторение.",
    },
    {
      target: "#menu-cards-btn",
      side: "above",
      text: "Здесь живут твои колоды: нажми, чтобы полистать и выбрать нужную.",
    },
    {
      target: "#menu-theme-dots",
      side: "above",
      text: "Цвет и тему можно менять прямо в меню — примерь, что нравится.",
    },
  ];
  tourStep = 0;
  const tip = document.getElementById("tour-tip");
  tip.hidden = false;
  document.getElementById("tour-next").textContent = "Дальше";
  renderTourStep();
}

function renderTourStep() {
  const tip = document.getElementById("tour-tip");
  document.querySelectorAll(".tour-highlight").forEach((el) => el.classList.remove("tour-highlight"));
  const step = tourSteps[tourStep];
  const target = document.querySelector(step.target);
  document.getElementById("tour-text").textContent = step.text;
  document.getElementById("tour-next").textContent =
    tourStep === tourSteps.length - 1 ? "Готово" : "Дальше";
  if (target) target.classList.add("tour-highlight");
  positionTourTip(target, step.side);
  tip.dataset.side = step.side;
}

function positionTourTip(target, side) {
  const tip = document.getElementById("tour-tip");
  const tipWidth = tip.offsetWidth;
  const tipHeight = tip.offsetHeight;
  const rect = target.getBoundingClientRect();
  let left = rect.left + rect.width / 2 - tipWidth / 2;
  const clampedLeft = Math.min(Math.max(left, 12), window.innerWidth - tipWidth - 12);
  tip.style.setProperty("--arrow-x", Math.round(rect.left + rect.width / 2 - clampedLeft) + "px");
  left = clampedLeft;
  let top = side === "above" ? rect.top - tipHeight - 12 : rect.bottom + 12;
  top = Math.min(Math.max(top, 12), window.innerHeight - tipHeight - 12);
  tip.style.left = left + "px";
  tip.style.top = top + "px";
}

function nextTourStep() {
  tourStep += 1;
  if (tourStep >= tourSteps.length) {
    finishTour();
    return;
  }
  renderTourStep();
}

function finishTour() {
  hideTour();
}

function hideTour() {
  if (tourStep === -1) return;
  const tip = document.getElementById("tour-tip");
  tip.hidden = true;
  document.querySelectorAll(".tour-highlight").forEach((el) => el.classList.remove("tour-highlight"));
  tourStep = -1;
  tourSteps = [];
  try {
    localStorage.setItem(ONBOARD_KEY, "1");
  } catch (error) {}
}

function bindMenuEvents() {
  const backdrop = document.getElementById("menu-backdrop");
  const pop = document.getElementById("menu-pop-backdrop");
  const pick = document.getElementById("deck-pick-backdrop");

  document.getElementById("menu-close").addEventListener("click", closeMenu);
  document.getElementById("menu-back-btn").addEventListener("click", openMenu);
  document.getElementById("empty-menu-btn").addEventListener("click", openMenu);
  document.getElementById("menu-study-btn").addEventListener("click", bigStudy);
  document.getElementById("menu-cards-btn").addEventListener("click", openFirstDeck);
  document.getElementById("menu-stats-btn").addEventListener("click", () => openStats());
  document.getElementById("menu-settings-btn").addEventListener("click", openSettingsModal);

  backdrop.addEventListener("click", (event) => {
    if (event.target.id === "menu-backdrop") closeMenu();
  });
  backdrop.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      closeMenu();
    } else {
      trapTabKey(backdrop, event);
    }
  });

  document.getElementById("deck-pick-new").addEventListener("click", () => {
    closeAllMenus();
    createDeck();
  });
  document.getElementById("deck-pick-cancel").addEventListener("click", closeDeckPicker);
  pick.addEventListener("click", (event) => {
    if (event.target.id === "deck-pick-backdrop") closeDeckPicker();
  });
  pick.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.stopPropagation();
      closeDeckPicker();
    } else {
      trapTabKey(pick, event);
    }
  });

  document.getElementById("menu-pop-cancel").addEventListener("click", closeMenuPop);
  pop.addEventListener("click", (event) => {
    if (event.target.id === "menu-pop-backdrop") closeMenuPop();
  });
  pop.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.stopPropagation();
      closeMenuPop();
    } else {
      trapTabKey(pop, event);
    }
  });

  document.getElementById("menu-mode-switch").addEventListener("click", (event) => {
    const button = event.target.closest("[data-mode]");
    if (!button) return;
    applyAppearance({ mode: button.dataset.mode }, event);
  });
  document.getElementById("menu-theme-dots").addEventListener("click", (event) => {
    const button = event.target.closest(".theme-dot");
    if (!button) return;
    applyAppearance({ palette: button.dataset.palette }, event);
  });

  document.getElementById("tour-next").addEventListener("click", nextTourStep);
  document.getElementById("tour-skip").addEventListener("click", finishTour);
}

bindMenuEvents();

