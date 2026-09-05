let editImageId = null;

function $(id) { return document.getElementById(id); }
function $on(id, event, handler) { var el = $(id); if (el) el.addEventListener(event, handler); }

function startEditCard(cardId) {
  const card = state.cards.find((item) => item.id === cardId);
  if (!card) return;
  document.getElementById("card-id").value = card.id;
  document.getElementById("card-question").value = card.question;
  document.getElementById("card-answer").value = card.answer;
  document.getElementById("save-card-btn").textContent = "Сохранить";
  document.getElementById("cancel-edit-btn").classList.remove("hidden");
  document.getElementById("card-question").focus();
  resetImageDraft();
  editImageId = card.id;
  if (window.imgGet) {
    imgGet(cardId).then((dataUrl) => {
      if (document.getElementById("card-id").value === cardId && dataUrl) showImagePreview(dataUrl);
    }).catch(() => {});
  }
}

const IMG_REMOVE = "__remove__";
let pendingImage = null;

function showImagePreview(dataUrl) {
  document.getElementById("image-thumb").src = dataUrl;
  document.getElementById("image-preview").classList.remove("hidden");
}

function resetImageDraft() {
  pendingImage = null;
  editImageId = null;
  document.getElementById("image-thumb").removeAttribute("src");
  document.getElementById("image-preview").classList.add("hidden");
  document.getElementById("card-image").value = "";
}

async function handleImageFile(file) {
  try {
    const dataUrl = await compressImageFile(file);
    pendingImage = dataUrl;
    showImagePreview(dataUrl);
  } catch (error) {
    showToast("Не удалось прочитать картинку.", "warn");
  }
}

const BULK_SEPARATOR = "=";
let bulkTrigger = null;

function splitBulkPair(line) {
  const index = line.indexOf(BULK_SEPARATOR);
  if (index > 0) {
    const question = line.slice(0, index).trim();
    const answer = line.slice(index + BULK_SEPARATOR.length).trim();
    if (question && answer) return [question, answer];
  }
  return null;
}

function parseBulkLines(text) {
  const pairs = [];
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    const pair = splitBulkPair(trimmed);
    if (pair) pairs.push(pair);
  }
  return pairs;
}

function openBulkInput(trigger) {
  const deck = selectedDeck();
  if (!deck) return;
  bulkTrigger = trigger || document.activeElement;
  document.getElementById("bulk-input").value = "";
  document.getElementById("bulk-feedback").textContent = "";
  document.getElementById("bulk-feedback").classList.remove("warn", "show");
  const backdrop = document.getElementById("bulk-backdrop");
  showLayer(backdrop);
  lockScroll(true);
  document.getElementById("bulk-input").focus();
}

function closeBulkInput() {
  const backdrop = document.getElementById("bulk-backdrop");
  hideLayer(backdrop);
  lockScroll(false);
  if (bulkTrigger && canFocus(bulkTrigger)) bulkTrigger.focus();
  bulkTrigger = null;
}

function applyBulkInput() {
  const deck = selectedDeck();
  if (!deck) return;
  const text = document.getElementById("bulk-input").value;
  const pairs = parseBulkLines(text);
  const feedback = document.getElementById("bulk-feedback");
  if (!pairs.length) {
    feedback.textContent = "Не нашёл ни одной пары — проверь разделители.";
    feedback.classList.add("warn");
    return;
  }
  pairs.forEach(([question, answer]) => {
    state.cards.push({ id: uid(), deckId: deck.id, question, answer, status: "new" });
  });
  saveState();
  render();
  const lines = text.split(/\r?\n/).filter((line) => line.trim()).length;
  const skipped = lines - pairs.length;
  document.getElementById("bulk-input").value = "";
  feedback.classList.remove("warn", "show");
  void feedback.offsetWidth;
  const message = `Добавлено ${pairs.length}${skipped > 0 ? ` · пропущено ${skipped}` : ""}. Можно вставить следующую порцию.`;
  if (reduceMotion()) {
    feedback.textContent = message;
  } else {
    feedback.innerHTML =
      '<svg class="fb-check" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12.5 L9.5 18 L20 6.5" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"/></svg>' + message;
    feedback.classList.add("show");
  }
  document.getElementById("bulk-input").focus();
}

async function createDeck() {
  const name = await openModal({
    title: "Новая колода",
    text: "Короткое имя, которое увидишь в списке слева.",
  });
  if (!name) return;
  const deck = { id: uid(), name };
  state.decks.push(deck);
  state.selectedDeckId = deck.id;
  state.tab = "edit";
  resetStudy();
  saveState();
  render();
  if (typeof Auth !== 'undefined' && Auth.getUser()) {
    AppData.createDeck(deck.name).catch(e => console.warn('Sync failed:', e));
  }
}

async function renameDeck() {
  const deck = selectedDeck();
  if (!deck) return;
  const name = await openModal({
    title: "Переименовать",
    text: "Новое название этой колоды.",
    value: deck.name,
  });
  if (!name) return;
  deck.name = name;
  saveState();
  render();
}

async function deleteDeck() {
  const deck = selectedDeck();
  if (!deck) return;
  const ok = await openModal({
    title: "Удалить колоду?",
    kicker: "осторожно",
    text: `Колода «${deck.name}» и все её карточки исчезнут.`,
    confirmOnly: true,
  });
  if (!ok) return;
  const removedIds = state.cards.filter((card) => card.deckId === deck.id).map((card) => card.id);
  if (window.imgDelete) removedIds.forEach((cid) => imgDelete(cid).catch(() => {}));
  state.cards = state.cards.filter((card) => card.deckId !== deck.id);
  state.decks = state.decks.filter((item) => item.id !== deck.id);
  state.selectedDeckId = state.decks[0] ? state.decks[0].id : null;
  state.tab = "edit";
  resetStudy();
  saveState();
  render();
  if (typeof Auth !== 'undefined' && Auth.getUser()) {
    AppData.deleteDeck(deck.id).catch(e => console.warn('Sync failed:', e));
  }
}

async function resetDeckProgress() {
  const deck = selectedDeck();
  if (!deck) return;
  const ok = await openModal({
    title: "Начать заново?",
    kicker: "прогресс",
    text: `Статусы всех карточек колоды «${deck.name}» будут сброшены на «новые». Изученное не восстановится.`,
    confirmOnly: true,
    confirmText: "Сбросить",
  });
  if (!ok) return;
  state.cards.forEach((card) => {
    if (card.deckId === deck.id) card.status = "new";
  });
  saveState();
  render();
}

async function deleteCard(cardId) {
  const ok = await openModal({
    title: "Удалить карточку?",
    kicker: "осторожно",
    text: "Это действие нельзя отменить.",
    confirmOnly: true,
  });
  if (!ok) return;
  const li = document.querySelector(`li[data-card-id="${CSS.escape(cardId)}"]`);
  if (li && !reduceMotion()) {
    li.style.transition = "transform 0.18s var(--ease), opacity 0.16s var(--ease)";
    li.style.transform = "translateX(-22px)";
    li.style.opacity = "0";
    setTimeout(() => {
      li.classList.add("row-out");
      li.style.height = li.offsetHeight + "px";
      void li.offsetWidth;
      li.style.height = "0px";
      li.style.paddingTop = "0px";
      li.style.paddingBottom = "0px";
      li.style.borderWidth = "0px";
      li.style.marginBottom = "0px";
      setTimeout(() => finishDeleteCard(cardId), 150);
    }, 170);
    return;
  }
  finishDeleteCard(cardId);
}

function finishDeleteCard(cardId) {
  state.cards = state.cards.filter((card) => card.id !== cardId);
  if (document.getElementById("card-id").value === cardId) resetCardForm();
  if (window.imgDelete) imgDelete(cardId).catch(() => {});
  saveState();
  render();
  if (typeof Auth !== 'undefined' && Auth.getUser()) {
    AppData.deleteCard(cardId).catch(e => console.warn('Sync failed:', e));
  }
}

function saveCard(event) {
  event.preventDefault();
  const deck = selectedDeck();
  if (!deck) return;

  const id = document.getElementById("card-id").value;
  const question = document.getElementById("card-question").value.trim();
  const answer = document.getElementById("card-answer").value.trim();
  if (!question || !answer) {
    if (!reduceMotion()) {
      [
        ["card-question", question],
        ["card-answer", answer],
      ].forEach(([fieldId, value]) => {
        if (value) return;
        const fieldEl = document.getElementById(fieldId);
        fieldEl.classList.add("field-error");
        setTimeout(() => fieldEl.classList.remove("field-error"), 650);
      });
    }
    return;
  }

  if (id) {
    const card = state.cards.find(
      (item) => item.id === id && item.deckId === deck.id
    );
    if (card) {
      card.question = question;
      card.answer = answer;
      if (pendingImage === IMG_REMOVE && window.imgDelete) imgDelete(id).catch(() => {});
      else if (pendingImage && window.imgPut) imgPut(id, pendingImage).catch(() => {});
    }
  } else {
    const newId = uid();
    state.cards.push({
      id: newId,
      deckId: deck.id,
      question,
      answer,
      status: "new",
    });
    if (pendingImage && pendingImage !== IMG_REMOVE && window.imgPut) imgPut(newId, pendingImage).catch(() => {});
    if (typeof Auth !== 'undefined' && Auth.getUser()) {
      AppData.addCard(deck.id, question, answer).catch(e => console.warn('Sync failed:', e));
    }
    saveState();
    resetCardForm();
    render();
    const freshLi = document.querySelector(`li[data-card-id="${newId}"]`);
    if (freshLi && !reduceMotion()) {
      freshLi.classList.add("row-new");
      setTimeout(() => freshLi.classList.remove("row-new"), 950);
    }
    return;
  }

  saveState();
  resetCardForm();
  render();
}

function bindEvents() {
  function on(id, evt, fn) { var el = $(id); if (el) el.addEventListener(evt, fn); }
  on("new-deck-btn", "click", createDeck);
  on("empty-new-deck-btn", "click", createDeck);
  on("rename-deck-btn", "click", renameDeck);
  on("delete-deck-btn", "click", deleteDeck);
  on("share-deck-btn", "click", async () => {
    const deck = selectedDeck();
    if (!deck) return;
    if (deck.share_slug) {
      const ok = await Share.copyShareLink(deck);
      if (typeof showToast === "function") showToast(ok ? "Ссылка скопирована" : "Не удалось скопировать", ok ? "ok" : "warn");
    } else {
      const updated = await Share.enableSharing(deck.id);
      if (updated && updated.share_slug) {
        deck.share_slug = updated.share_slug;
        deck.is_public = true;
        saveState();
        const ok = await Share.copyShareLink(deck);
        if (typeof showToast === "function") showToast(ok ? "Колода опубликована, ссылка скопирована" : "Колода опубликована", ok ? "ok" : "warn");
      } else {
        if (typeof showToast === "function") showToast("Не удалось опубликовать", "warn");
      }
    }
  });
  document.getElementById("card-form").addEventListener("submit", saveCard);
  document.getElementById("card-form").addEventListener("keydown", (event) => {
    if ((event.ctrlKey || event.metaKey) && event.key === "Enter") {
      event.preventDefault();
      document.getElementById("save-card-btn").click();
    }
  });
  document.getElementById("cancel-edit-btn").addEventListener("click", resetCardForm);
  document.getElementById("image-btn").addEventListener("click", () => document.getElementById("card-image").click());
  document.getElementById("card-image").addEventListener("change", (event) => {
    const file = event.target.files && event.target.files[0];
    event.target.value = "";
    if (file) handleImageFile(file);
  });
  document.getElementById("image-clear").addEventListener("click", () => {
    pendingImage = editImageId ? IMG_REMOVE : null;
    document.getElementById("image-thumb").removeAttribute("src");
    document.getElementById("image-preview").classList.add("hidden");
  });
  document.getElementById("card-filters").addEventListener("click", (event) => {
    const button = event.target.closest(".filter-btn");
    if (!button) return;
    state.cardFilter = button.dataset.filter || "all";
    render();
  });
  const searchInput = document.getElementById("card-search");
  let searchDebounce = null;
  searchInput.addEventListener("input", () => {
    state.searchQuery = searchInput.value;
    document.getElementById("card-search-clear").classList.toggle("is-visible", !!searchInput.value);
    if (searchDebounce) clearTimeout(searchDebounce);
    searchDebounce = setTimeout(() => {
      searchDebounce = null;
      renderCardRows();
    }, 80);
  });
  searchInput.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.stopPropagation();
      if (searchDebounce) { clearTimeout(searchDebounce); searchDebounce = null; }
      clearCardSearch();
      searchInput.focus();
    }
  });
  document.getElementById("card-search-clear").addEventListener("click", () => {
    clearCardSearch();
    searchInput.focus();
  });
  const bulkBackdrop = document.getElementById("bulk-backdrop");
  document.getElementById("bulk-btn").addEventListener("click", (event) => openBulkInput(event.currentTarget));
  document.getElementById("bulk-ok").addEventListener("click", applyBulkInput);
  document.getElementById("bulk-cancel").addEventListener("click", closeBulkInput);
  document.getElementById("bulk-input").addEventListener("keydown", (event) => {
    if ((event.ctrlKey || event.metaKey) && event.key === "Enter") {
      event.preventDefault();
      applyBulkInput();
    } else if (event.key === "Escape") {
      event.stopPropagation();
      closeBulkInput();
    } else {
      trapTabKey(bulkBackdrop, event);
    }
  });
  bulkBackdrop.addEventListener("click", (event) => {
    if (event.target.id === "bulk-backdrop") closeBulkInput();
  });
  bulkBackdrop.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.stopPropagation();
      closeBulkInput();
    } else {
      trapTabKey(bulkBackdrop, event);
    }
  });
  document.getElementById("tab-edit").addEventListener("click", () => setTab("edit"));
  document.getElementById("tab-study").addEventListener("click", () => setTab("study"));
  document.querySelector(".tabs").addEventListener("keydown", (event) => {
    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
    event.preventDefault();
    event.stopPropagation();
    setTab(event.key === "ArrowRight" ? "study" : "edit");
  });
  document.getElementById("flashcard").addEventListener("click", flipCard);
  document.querySelectorAll(".face-speak").forEach((span) => {
    span.addEventListener("click", (event) => {
      event.stopPropagation();
      speakFace(span.dataset.side);
    });
  });
  if (window.speechSynthesis && speechSynthesis.addEventListener) {
    speechSynthesis.addEventListener("voiceschanged", () => { pickRuVoice(); });
  }
  document.getElementById("prev-card-btn").addEventListener("click", () => moveStudy(-1));
  document.getElementById("next-card-btn").addEventListener("click", () => moveStudy(1));
  document.getElementById("mark-known-btn").addEventListener("click", () => markStatus("known"));
  document.getElementById("mark-unknown-btn").addEventListener("click", () => markStatus("unknown"));
  document.getElementById("study-mode-flip").addEventListener("click", () => setStudyMode("flip"));
  document.getElementById("study-mode-quiz").addEventListener("click", () => setStudyMode("quiz"));
  document.getElementById("two-sided-btn").addEventListener("click", toggleTwoSided);
  document.querySelectorAll("#quiz-start [data-qlen]").forEach((button) => {
    button.addEventListener("click", () => startQuiz(Number(button.dataset.qlen)));
  });
  document.getElementById("quiz-options").addEventListener("click", (event) => {
    const option = event.target.closest(".quiz-option");
    if (option) answerQuiz(option);
  });
  document.getElementById("quiz-next").addEventListener("click", nextQuiz);
  document.getElementById("quiz-focus-btn").addEventListener("click", enterQuizFocus);
  document.addEventListener("keydown", (event) => {
    if (!quizActive || quizAnswered) return;
    if (document.querySelector(".modal-backdrop.is-open") || document.querySelector("#menu-backdrop.is-open")) return;
    if (!["1", "2", "3", "4"].includes(event.key)) return;
    const options = document.querySelectorAll("#quiz-options .quiz-option");
    const idx = Number(event.key) - 1;
    if (idx >= options.length) return;
    event.preventDefault();
    options[idx].click();
  });

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    const fb = document.getElementById("focus-backdrop");
    if (!fb.classList.contains("is-open")) return;
    if (quizFullscreen) exitQuizFocus();
    else exitFocusMode();
  });

  const focusBackdrop = document.getElementById("focus-backdrop");
  document.getElementById("focus-btn").addEventListener("click", enterFocusMode);
  document.getElementById("focus-exit").addEventListener("click", () => {
    if (quizFullscreen) exitQuizFocus();
    else exitFocusMode();
  });
  document.getElementById("focus-prev").addEventListener("click", () => moveStudy(-1));
  document.getElementById("focus-next").addEventListener("click", () => moveStudy(1));
  document.getElementById("focus-known").addEventListener("click", () => markStatus("known"));
  document.getElementById("focus-unknown").addEventListener("click", () => markStatus("unknown"));
  focusBackdrop.addEventListener("click", (event) => {
    if (event.target.id === "focus-backdrop") {
      if (quizFullscreen) exitQuizFocus();
      else exitFocusMode();
    }
  });
  focusBackdrop.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.stopPropagation();
      if (quizFullscreen) exitQuizFocus();
      else exitFocusMode();
    } else {
      trapTabKey(focusBackdrop, event);
    }
  });

  const summaryBackdrop = document.getElementById("summary-backdrop");
  document.getElementById("summary-repeat").addEventListener("click", repeatStudy);
  document.getElementById("summary-menu").addEventListener("click", () => {
    closeSummary();
    if (quizFullscreen) exitQuizFocus();
    if (focusMode) exitFocusMode();
    resetStudy();
    openMenu();
  });
  document.getElementById("summary-stats").addEventListener("click", () => {
    closeSummary();
    if (quizFullscreen) exitQuizFocus();
    if (focusMode) exitFocusMode();
    openStats();
  });
  summaryBackdrop.addEventListener("click", (event) => {
    if (event.target.id === "summary-backdrop") {
      closeSummary();
      if (quizFullscreen) exitQuizFocus();
      if (focusMode) exitFocusMode();
      resetStudy();
      openMenu();
    }
  });
  summaryBackdrop.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.stopPropagation();
      closeSummary();
      if (quizFullscreen) exitQuizFocus();
      if (focusMode) exitFocusMode();
      resetStudy();
      openMenu();
    } else {
      trapTabKey(summaryBackdrop, event);
    }
  });

  document.getElementById("theme-dots").addEventListener("click", (event) => {
    const button = event.target.closest(".theme-dot");
    if (!button) return;
    applyAppearance({ palette: button.dataset.palette }, event);
  });
  document.getElementById("mode-switch").addEventListener("click", (event) => {
    const button = event.target.closest("[data-mode]");
    if (!button) return;
    applyAppearance({ mode: button.dataset.mode }, event);
  });
  document.getElementById("fontsize-switch").addEventListener("click", (event) => {
    const button = event.target.closest("[data-size]");
    if (!button) return;
    applyFontSize(button.dataset.size);
  });

  document.addEventListener("keydown", (event) => {
    if (document.querySelector(".modal-backdrop.is-open")) return;
    if (document.querySelector("#menu-backdrop.is-open")) return;
    const board = document.getElementById("study-board");
    if (state.tab !== "study" || board.classList.contains("hidden")) return;
    if (document.getElementById("flip-area").classList.contains("hidden")) return;
    if (event.key === "ArrowRight") {
      event.preventDefault();
      moveStudy(1);
    } else if (event.key === "ArrowLeft") {
      event.preventDefault();
      moveStudy(-1);
    }
  });

  bindModalEvents();
  bindMotionExtras();
}

function bindMotionExtras() {
  window.addEventListener("resize", () => {
    refreshIndicators();
    tiltRect = null;
    flashcardEl.style.transform = "";
    if (tourStep !== -1 && tourSteps[tourStep]) {
      const step = tourSteps[tourStep];
      const target = document.querySelector(step.target);
      if (target) positionTourTip(target, step.side);
    }
  });

  window.addEventListener("storage", (event) => {
    if (event.key !== STORAGE_KEY && event.key !== null) return;
    loadState();
    resetStudy();
    resetCardForm();
    clearCardSearch();
    syncAppearanceButtons();
    render();
  });

  const mainEl = document.querySelector(".main");
  let parallaxTick = false;
  mainEl.addEventListener("scroll", () => {
    if (reduceMotion() || parallaxTick) return;
    parallaxTick = true;
    requestAnimationFrame(() => {
      const y = mainEl.scrollTop;
      const gutter = getComputedStyle(mainEl).getPropertyValue("--gutter").trim() || "52px";
      mainEl.style.backgroundPosition =
        `${gutter} ${(-y * 0.12).toFixed(1)}px, 0 ${(-y * 0.08).toFixed(1)}px, 0 ${(-y * 0.08).toFixed(1)}px`;
      parallaxTick = false;
    });
  }, { passive: true });

  document.addEventListener("pointerdown", (event) => {
    const button = event.target.closest(".btn, .tab");
    if (!button || reduceMotion()) return;
    const r = button.getBoundingClientRect();
    const d = Math.max(r.width, r.height) * 2;
    const wave = document.createElement("span");
    wave.className = "ripple";
    wave.style.width = wave.style.height = d + "px";
    wave.style.left = event.clientX - r.left - d / 2 + "px";
    wave.style.top = event.clientY - r.top - d / 2 + "px";
    button.appendChild(wave);
    setTimeout(() => wave.remove(), 600);
  });

  const flashcardEl = document.getElementById("flashcard");
  let tiltRect = null;
  const overHost = (t) => !!(t && t.closest && (t.closest(".flashcard-wrap") || t.closest("#focus-wrap")));
  document.addEventListener("pointermove", (event) => {
    if (event.pointerType !== "mouse" || reduceMotion()) return;
    if (!overHost(event.target)) {
      if (tiltRect) {
        tiltRect = null;
        flashcardEl.style.transform = "";
      }
      return;
    }
    if (!tiltRect) {
      flashcardEl.style.transform = "";
      tiltRect = flashcardEl.getBoundingClientRect();
    }
    const dx = ((event.clientX - tiltRect.left) / tiltRect.width - 0.5) * 7;
    const dy = (0.5 - (event.clientY - tiltRect.top) / tiltRect.height) * 5;
    const cx = Math.max(-3.5, Math.min(3.5, dx));
    const cy = Math.max(-2.5, Math.min(2.5, dy));
    flashcardEl.style.transform = `rotateY(${cx.toFixed(2)}deg) rotateX(${cy.toFixed(2)}deg)`;
  });

  let hadMarks = false;
  const rowsEl = document.getElementById("card-rows");
  const observer = new MutationObserver(() => {
    const has = !!rowsEl.querySelector("mark.search-hit");
    if (has && !hadMarks) {
      rowsEl.classList.add("pulse-marks");
      setTimeout(() => rowsEl.classList.remove("pulse-marks"), 1400);
    }
    hadMarks = has;
  });
  observer.observe(rowsEl, { childList: true, subtree: true });
}

loadState();
renderThemeDots();
bindAutoTheme();
bindEvents();
syncAppearanceButtons();
render();
openMenu();

imgGcOrphans(state.cards.map((card) => card.id)).then((removed) => {
  if (removed > 0) console.info(`Освобождено осиротевших картинок: ${removed}`);
});

function verifyStylesFresh() {
  window.__RUNTIME_V = "41";
  const el = document.querySelector(".face-speak");
  if (!el) return;
  window.__stylesStale = getComputedStyle(el).position !== "absolute";
  if (window.__stylesStale) {
    clearTimeout(storageAlertTimer);
    showToast("Часть файлов устарела из-за кэша — нажмите Ctrl+F5 для обновления.", "warn");
    window.__stylesStale = true;
  }
}
verifyStylesFresh();

function showAuthModal() {
  document.getElementById("auth-backdrop").classList.add("is-open");
}

function hideAuthModal() {
  document.getElementById("auth-backdrop").classList.remove("is-open");
}

function showAuthBar() {
  const bar = document.getElementById("auth-bar");
  const email = document.getElementById("auth-user-email");
  const loginBtn = document.getElementById("login-btn");
  const logoutBtn = document.getElementById("auth-logout-btn");
  const menuAuth = document.getElementById("menu-auth-btn");
  if (!bar) return;
  const user = Auth.getUser();
  if (user) {
    if (email) email.textContent = user.email;
    bar.classList.remove("hidden");
    if (loginBtn) loginBtn.classList.add("hidden");
    if (logoutBtn) logoutBtn.classList.remove("hidden");
    if (menuAuth) {
      menuAuth.textContent = "Выйти";
      menuAuth.classList.add("menu-auth-out");
    }
  } else {
    bar.classList.add("hidden");
    if (loginBtn) loginBtn.classList.remove("hidden");
    if (logoutBtn) logoutBtn.classList.add("hidden");
    if (menuAuth) {
      menuAuth.textContent = "Войти";
      menuAuth.classList.remove("menu-auth-out");
    }
  }
}

function bindAuthEvents() {
  const backdrop = document.getElementById("auth-backdrop");
  const tabLogin = document.getElementById("auth-tab-login");
  const tabRegister = document.getElementById("auth-tab-register");
  const formLogin = document.getElementById("auth-login-form");
  const formRegister = document.getElementById("auth-register-form");

  tabLogin.addEventListener("click", () => {
    tabLogin.classList.add("is-active");
    tabRegister.classList.remove("is-active");
    formLogin.classList.remove("hidden");
    formRegister.classList.add("hidden");
  });

  tabRegister.addEventListener("click", () => {
    tabRegister.classList.add("is-active");
    tabLogin.classList.remove("is-active");
    formRegister.classList.remove("hidden");
    formLogin.classList.add("hidden");
  });

  formLogin.addEventListener("submit", async (e) => {
    e.preventDefault();
    const errEl = document.getElementById("auth-login-error");
    errEl.hidden = true;
    try {
      await Auth.login(
        formLogin.email.value,
        formLogin.password.value
      );
      hideAuthModal();
      showAuthBar();
      await AppData.syncFromServer();
      if (typeof render === "function") render();
    } catch (err) {
      errEl.textContent = err.message;
      errEl.hidden = false;
    }
  });

  formRegister.addEventListener("submit", async (e) => {
    e.preventDefault();
    const errEl = document.getElementById("auth-register-error");
    errEl.hidden = true;
    try {
      await Auth.register(
        formRegister.email.value,
        formRegister.password.value
      );
      await Auth.login(
        formRegister.email.value,
        formRegister.password.value
      );
      hideAuthModal();
      showAuthBar();
      await AppData.syncFromServer();
      if (typeof render === "function") render();
    } catch (err) {
      errEl.textContent = err.message;
      errEl.hidden = false;
    }
  });

  document.getElementById("auth-logout-btn").addEventListener("click", async () => {
    await Auth.logout();
    showAuthBar();
  });

  const loginBtn = document.getElementById("login-btn");
  if (loginBtn) {
    loginBtn.addEventListener("click", () => showAuthModal());
  }

  const migrateBtn = document.getElementById("menu-migrate-btn");
  if (migrateBtn) {
    migrateBtn.addEventListener("click", async () => {
      const data = Data.exportLocalData();
      if (!data || data.decks.length === 0) {
        if (typeof showToast === "function") showToast("Нет локальных данных для миграции", "warn");
        return;
      }
      try {
        const res = await Data.migrateData(data);
        await AppData.syncFromServer();
        if (typeof render === "function") render();
        if (typeof showToast === "function") showToast(`Мигрировано ${res.total_decks} колод`, "ok");
      } catch (err) {
        if (typeof showToast === "function") showToast("Ошибка миграции: " + err.message, "warn");
      }
    });
  }

  const loginMenuBtn = document.getElementById("menu-login-btn");
  if (loginMenuBtn) {
    loginMenuBtn.addEventListener("click", () => showAuthModal());
  }

  const workspaceLoginBtn = document.getElementById("workspace-login-btn");
  if (workspaceLoginBtn) {
    workspaceLoginBtn.addEventListener("click", () => showAuthModal());
  }

  const menuAuthBtn = document.getElementById("menu-auth-btn");
  if (menuAuthBtn) {
    menuAuthBtn.addEventListener("click", async () => {
      if (Auth.getUser()) {
        await Auth.logout();
        showAuthBar();
        if (typeof closeAllMenus === "function") closeAllMenus();
        if (typeof showToast === "function") showToast("Вы вышли", "ok");
      } else {
        if (typeof closeAllMenus === "function") closeAllMenus();
        showAuthModal();
      }
    });
  }
}

(async () => {
  try {
    bindAuthEvents();
    showAuthBar();
    const user = await Auth.init();
    if (user) {
      showAuthBar();
      await AppData.syncFromServer();
      if (typeof render === "function") render();
    }
    if (typeof Router !== "undefined") Router.init();
  } catch (err) {
    console.error("App init failed:", err);
    if (typeof Router !== "undefined") Router.init();
  }
})();







