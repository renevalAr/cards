let swapCleanup = null;
let scoredStatus = new Map();
let sessionMarked = new Set();
let focusMode = false;
let focusTrigger = null;
let quizActive = false;
let quizAnswered = false;
let quizOrder = [];
let quizIndex = 0;
const quizRight = new Set();
const quizWrong = new Set();
let quizRetry = null;
let quizFullscreen = false;
let flipAnims = [];
let flipRun = null;

const FLIP_BEZIER = [0.45, 0, 0.25, 1];
const FLIP_DUR = 620;

function scoreStudy(deckId, entryKey, status) {
  if (scoredStatus.has(entryKey)) return;
  scoredStatus.set(entryKey, status);
  getTodayStats()[status] += 1;
  recordStudy(deckId, status);
}

function bezProgress(dur, ms) {
  const t = Math.min(1, Math.max(0, ms / dur));
  const [x1, y1, x2, y2] = FLIP_BEZIER;
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const fx = (u) => ((ax * u + bx) * u + cx) * u;
  let lo = 0, hi = 1, u = t;
  for (let i = 0; i < 24; i += 1) {
    u = (lo + hi) / 2;
    if (fx(u) < t) lo = u;
    else hi = u;
  }
  return ((ay * u + by) * u + cy) * u;
}

function currentAngle() {
  if (flipRun && flipRun.dir !== 0) {
    const e = performance.now() - flipRun.t0;
    const p = bezProgress(flipRun.dur, e);
    return flipRun.from + (flipRun.to - flipRun.from) * p;
  }
  return state.flipped ? 180 : 0;
}

function flipHost() {
  const card = document.getElementById("flashcard");
  return card ? card.parentElement : null;
}

function clearLift() {
  const wrapEl = flipHost();
  if (wrapEl) wrapEl.style.transform = "";
}

function killFlipAnims(commit) {
  if (!flipAnims.length) {
    if (commit) flipRun = null;
    return;
  }
  if (commit) {
    const wrapEl = flipHost();
    if (wrapEl) wrapEl.style.transform = state.flipped ? "translateY(-6px)" : "";
    flipRun = null;
  }
  flipAnims.forEach((a) => { try { a.cancel(); } catch (e) {} });
  flipAnims = [];
}

function startFlipAnimation(fromFlipped) {
  const wrapEl = flipHost();
  const inner = document.querySelector("#flashcard .flashcard-inner");
  if (!wrapEl || !inner) return;
  killFlipAnims(false);

  const thFrom = (() => {
    if (flipRun && flipRun.dir !== 0) return currentAngle();
    return fromFlipped ? 180 : 0;
  })();
  const thTo = fromFlipped ? 0 : 180;
  const ov = 4 * Math.sign(thTo - thFrom);
  const span = Math.max(8, Math.abs(thTo - thFrom));
  const dur = Math.max(90, FLIP_DUR * (span / 180));
  const startedAt = performance.now();

  const liftMatch = /translateY\((-?[\d.]+)px\)/.exec(wrapEl.style.transform || "");
  const liftFrom = liftMatch ? parseFloat(liftMatch[1]) : (fromFlipped ? -6 : 0);
  const liftTo = fromFlipped ? 0 : -6;

  const flipEase = `cubic-bezier(${FLIP_BEZIER.join(",")})`;
  const innerFrames = [
    { transform: `rotateY(${thFrom}deg)`, easing: flipEase },
    { transform: `rotateY(${thTo + ov}deg)`, offset: 0.82, easing: "ease-out" },
    { transform: `rotateY(${thTo}deg)` },
  ];
  const shadowSteps = Math.max(6, Math.round(dur / 34));
  const shadowFrames = [];
  for (let i = 0; i <= shadowSteps; i += 1) {
    const u = i / shadowSteps;
    const p = bezProgress(dur, u * dur);
    let ang = thFrom + (thTo - thFrom) * p;
    if (u > 0.55) ang += ov * Math.sin(Math.PI * Math.min(1, (u - 0.55) / 0.45));
    const k = Math.max(0.03, Math.abs(Math.cos(Math.PI * (ang / 180))));
    shadowFrames.push({ transform: `translate(6px, 7px) scaleX(${k.toFixed(3)})` });
  }

  const linOpts = { duration: dur, easing: "linear", fill: "forwards", pseudoElement: "::before" };

  const aInner = inner.animate(innerFrames, { duration: dur, fill: "forwards" });
  const aShadow = wrapEl.animate(shadowFrames, linOpts);
  const aLift = wrapEl.animate(
    [{ transform: `translateY(${liftFrom}px)` }, { transform: `translateY(${liftTo}px)` }],
    { duration: dur, easing: flipEase, fill: "forwards" }
  );

  flipRun = { dir: Math.sign(thTo - thFrom), t0: startedAt, dur, from: thFrom, to: thTo };
  flipAnims = [aInner, aShadow, aLift];

  const finish = () => {
    wrapEl.style.transform = `translateY(${liftTo}px)`;
    try { aInner.cancel(); } catch (e) {}
    try { aShadow.cancel(); } catch (e) {}
    try { aLift.cancel(); } catch (e) {}
    flipAnims = [];
    if (flipRun && flipRun.t0 === startedAt) flipRun = null;
  };
  aInner.onfinish = finish;
  aShadow.onfinish = finish;
  aLift.onfinish = finish;
}

function shuffle(items) {
  const copy = items.slice();
  for (let i = copy.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

function reduceMotion() {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

function pickRuVoice() {
  const voices = window.speechSynthesis ? speechSynthesis.getVoices() : [];
  if (!voices.length) return null;
  const ru = voices.filter((v) => /^ru/i.test(v.lang));
  if (!ru.length) return null;
  const score = (v) =>
    (/google/i.test(v.name) ? 4 : 0) +
    (/natural|online|neural/i.test(v.name) ? 3 : 0) +
    (/microsoft/i.test(v.name) ? 2 : 0) +
    (v.localService ? 1 : 0);
  return ru.slice().sort((a, b) => score(b) - score(a))[0];
}

function speakText(text) {
  if (!window.speechSynthesis || !text) return false;
  speechSynthesis.cancel();
  const utterance = new SpeechSynthesisUtterance(text);
  const voice = pickRuVoice();
  if (voice) utterance.voice = voice;
  utterance.lang = voice ? voice.lang : "ru-RU";
  utterance.rate = 0.92;
  utterance.pitch = 1.05;
  speechSynthesis.speak(utterance);
  return true;
}

function speakFace(side) {
  const cards = currentStudyCards();
  const card = cards[state.studyIndex];
  if (!card) return false;
  const entry = state.studyOrder[state.studyIndex] || "";
  const rev = String(entry).endsWith("#rev");
  let text;
  if (side === "front") text = rev ? card.answer : card.question;
  else text = rev ? card.question : card.answer;
  return speakText(String(text).trim());
}

function stopSpeech() {
  if (window.speechSynthesis) speechSynthesis.cancel();
}

function entryId(entry) {
  return String(entry).split("#")[0];
}

function entryRev(entry) {
  return String(entry).endsWith("#rev");
}

function buildStudyEntries(deckId) {
  const deck = state.decks.find((d) => d.id === deckId);
  const ids = cardsInDeck(deckId).map((card) => card.id);
  if (deck && deck.twoSided) {
    return ids.flatMap((id) => [id, id + "#rev"]);
  }
  return ids;
}

function beginRound(ids) {
  state.studyOrder = shuffle(ids);
  state.studyIndex = 0;
  state.flipped = false;
  stopSpeech();
  scoredStatus = new Map();
  sessionMarked = new Set();
}

function startStudyShuffle() {
  beginRound(buildStudyEntries(state.selectedDeckId));
}

function resetStudy() {
  if (quizFullscreen) exitQuizFocus();
  killFlipAnims(false);
  clearLift();
  state.studyOrder = [];
  state.studyIndex = 0;
  state.flipped = false;
  state.studyMode = "flip";
  scoredStatus = new Map();
  sessionMarked = new Set();
  quizActive = false;
  quizAnswered = false;
  quizOrder = [];
  quizIndex = 0;
  quizRight.clear();
  quizWrong.clear();
  quizRetry = null;
}

function setStudyMode(mode) {
  const next = mode === "quiz" ? "quiz" : "flip";
  if (state.studyMode === next && !quizActive) return;
  if (quizFullscreen) exitQuizFocus();
  state.studyMode = next;
  quizActive = false;
  syncStudyView();
}

function syncTwoSidedBtn() {
  const deck = selectedDeck();
  const btn = document.getElementById("two-sided-btn");
  if (!btn) return;
  const on = Boolean(deck && deck.twoSided);
  btn.classList.toggle("is-active", on);
  btn.setAttribute("aria-pressed", String(on));
}

function toggleTwoSided() {
  const deck = selectedDeck();
  if (!deck) return;
  deck.twoSided = !deck.twoSided;
  saveState();
  syncTwoSidedBtn();
  if (state.tab === "study") {
    if (quizActive) {
      resetStudy();
      syncStudyView();
      startQuiz(0);
      return;
    }
    startStudyShuffle();
    showStudyCard();
  }
}

function enterQuizFocus() {
  if (!quizActive || quizFullscreen || focusMode) return;
  quizFullscreen = true;
  document.getElementById("focus-wrap").appendChild(document.getElementById("quiz-area"));
  document.getElementById("focus-meta").hidden = true;
  document.getElementById("focus-controls").classList.add("hidden");
  const backdrop = document.getElementById("focus-backdrop");
  showLayer(backdrop);
  lockScroll(true);
}

function exitQuizFocus() {
  if (!quizFullscreen) return;
  quizFullscreen = false;
  const backdrop = document.getElementById("focus-backdrop");
  hideLayer(backdrop);
  lockScroll(false);
  document.getElementById("focus-meta").hidden = false;
  document.getElementById("focus-controls").classList.remove("hidden");
  document.getElementById("study-board").appendChild(document.getElementById("quiz-area"));
}

function syncStudyView() {
  const board = document.getElementById("study-board");
  if (board.classList.contains("hidden")) return;
  const quiz = state.studyMode === "quiz";
  document.getElementById("study-mode-flip").classList.toggle("is-active", !quiz);
  document.getElementById("study-mode-quiz").classList.toggle("is-active", quiz);
  document.getElementById("flip-area").classList.toggle("hidden", quiz);
  document.getElementById("quiz-start").classList.toggle("hidden", !quiz || quizActive);
  document.getElementById("quiz-area").classList.toggle("hidden", !quiz || !quizActive);
  if (quiz && quizActive) renderQuizQuestion();
}

function startQuiz(len) {
  const all = shuffle(buildStudyEntries(state.selectedDeckId));
  const ids = len > 0 ? all.slice(0, Math.min(len, all.length)) : all;
  if (!ids.length) return;
  beginQuiz(ids);
}

function beginQuiz(ids) {
  const deckIds = new Set(cardsInDeck(state.selectedDeckId).map((card) => card.id));
  const valid = ids.filter((id) => deckIds.has(entryId(id)));
  const finalIds = valid.length ? valid : shuffle(buildStudyEntries(state.selectedDeckId));
  quizOrder = finalIds.slice();
  quizIndex = 0;
  quizRight.clear();
  quizWrong.clear();
  quizRetry = null;
  quizAnswered = false;
  quizActive = quizOrder.length > 0;
  state.studyMode = "quiz";
  syncStudyView();
}

function enterFocusMode() {
  const cards = currentStudyCards();
  if (!cards.length || focusMode || quizFullscreen) return;
  focusTrigger = document.activeElement;
  focusMode = true;
  document.getElementById("focus-wrap").appendChild(document.getElementById("flashcard"));
  const backdrop = document.getElementById("focus-backdrop");
  showLayer(backdrop);
  lockScroll(true);
  showStudyCard();
  document.getElementById("flashcard").focus();
}

function exitFocusMode() {
  if (!focusMode) return;
  focusMode = false;
  const backdrop = document.getElementById("focus-backdrop");
  hideLayer(backdrop);
  lockScroll(false);
  const home = document.getElementById("study-board").querySelector(".flashcard-wrap");
  if (home) home.appendChild(document.getElementById("flashcard"));
  showStudyCard();
  if (focusTrigger && canFocus(focusTrigger)) focusTrigger.focus();
  focusTrigger = null;
}

function currentStudyCards() {
  const map = new Map(cardsInDeck(state.selectedDeckId).map((card) => [card.id, card]));
  return state.studyOrder.map((entry) => map.get(entryId(entry))).filter(Boolean);
}

function setTab(tab) {
  state.tab = tab;
  if (tab === "study") startStudyShuffle();
  render();
}

function syncPressState(card) {
  document.getElementById("mark-known-btn").setAttribute("aria-pressed", String(card.status === "known"));
  document.getElementById("mark-unknown-btn").setAttribute("aria-pressed", String(card.status === "unknown"));
  if (focusMode) {
    document.getElementById("focus-known").setAttribute("aria-pressed", String(card.status === "known"));
    document.getElementById("focus-unknown").setAttribute("aria-pressed", String(card.status === "unknown"));
  }
}

function showStudyCard() {
  const cards = currentStudyCards();
  if (!cards.length) return;
  if (state.studyIndex >= cards.length) state.studyIndex = 0;
  if (state.studyIndex < 0) state.studyIndex = cards.length - 1;

  const card = cards[state.studyIndex];
  const rev = entryRev(state.studyOrder[state.studyIndex]);
  document.getElementById("flashcard-question").textContent = rev ? card.answer : card.question;
  document.getElementById("flashcard-answer").textContent = rev ? card.question : card.answer;
  const faceImg = document.getElementById("face-img-front");
  if (faceImg) {
    faceImg.classList.add("hidden");
    faceImg.removeAttribute("src");
    if (window.imgGet) {
      const token = card.id;
      imgGet(card.id).then((dataUrl) => {
        const cur = currentStudyCards()[state.studyIndex];
        if (dataUrl && cur && cur.id === token) {
          faceImg.src = dataUrl;
          faceImg.classList.remove("hidden");
        }
      }).catch(() => {});
    }
  }
  document.getElementById("flashcard").classList.toggle("is-flipped", state.flipped);
  const metaText = `Перемешано · карточка ${state.studyIndex + 1} из ${cards.length}${rev ? " · наоборот" : ""}`;
  document.getElementById("study-meta").textContent = metaText;

  syncPressState(card);

  if (focusMode) {
    document.getElementById("focus-meta").textContent = metaText;
  }
}

function flipCard(event) {
  if (event && event.target && event.target.closest && event.target.closest(".face-speak")) return;
  const cards = currentStudyCards();
  const card = cards[state.studyIndex];
  if (!card) return;
  document.getElementById("flashcard").classList.add("was-flipped");
  state.flipped = !state.flipped;
  const entryKey = state.studyOrder[state.studyIndex];
  if (state.flipped && !scoredStatus.has(entryKey)) {
    sessionMarked.add(entryKey);
    card.status = "unknown";
    scoreStudy(state.selectedDeckId, entryKey, "unknown");
    saveState();
    renderStats();
    updateCardRowStatus(card.id);
    syncPressState(card);
  }
  const el = document.getElementById("flashcard");
  el.classList.toggle("is-flipped", state.flipped);
  el.style.transform = "";
  if (reduceMotion()) return;
  startFlipAnimation(!state.flipped);
}

function isRoundComplete() {
  return state.studyOrder.length > 0 && sessionMarked.size >= state.studyOrder.length;
}

function moveStudy(step) {
  const cards = currentStudyCards();
  if (!cards.length) return;
  if (step > 0 && state.studyIndex === cards.length - 1 && isRoundComplete()) {
    showSummary();
    return;
  }
  state.studyIndex = (state.studyIndex + step + cards.length) % cards.length;
  state.flipped = false;
  stopSpeech();

  const el = document.getElementById("flashcard");
  if (swapCleanup) swapCleanup();
  killFlipAnims(false);
  clearLift();
  el.classList.remove("is-flipped", "is-swap", "was-flipped");
  void el.offsetWidth;
  el.classList.add("is-swap");
  showStudyCard();

  if (reduceMotion()) {
    el.classList.remove("is-swap");
    return;
  }
  const SWAP_DURATION = 500;
  const handler = () => el.classList.remove("is-swap");
  const timer = setTimeout(handler, SWAP_DURATION);
  el.addEventListener("animationend", handler, { once: true });
  swapCleanup = () => {
    clearTimeout(timer);
    el.removeEventListener("animationend", handler);
  };
}

function markStatus(status) {
  const cards = currentStudyCards();
  const card = cards[state.studyIndex];
  if (!card) return;
  card.status = status;
  const entryKey = state.studyOrder[state.studyIndex];
  sessionMarked.add(entryKey);
  scoreStudy(state.selectedDeckId, entryKey, status);
  saveState();
  renderStats();
  updateCardRowStatus(card.id);
  if (isRoundComplete()) {
    showSummary();
    return;
  }
  moveStudy(1);
}

function updateQuizMeta() {
  const total = Math.max(1, quizOrder.length);
  document.getElementById("quiz-meta").textContent =
    `Квиз · вопрос ${quizIndex + 1} из ${quizOrder.length} · верно ${quizRight.size}`;
  const done = ((quizIndex + (quizAnswered ? 1 : 0)) / total) * 100;
  document.getElementById("quiz-fill").style.width = done + "%";
}

function buildOptions(correct, all, rev) {
  const askText = (card) => (rev ? card.question : card.answer);
  const pool = shuffle(
    [...new Set(all.filter((card) => card.id !== correct.id).map(askText))].filter(
      (answer) => answer !== askText(correct)
    )
  );
  const options = [{ text: askText(correct), ok: true }];
  pool.slice(0, 3).forEach((text) => options.push({ text, ok: false }));
  return shuffle(options);
}

function renderQuizQuestion() {
  const deckCards = cardsInDeck(state.selectedDeckId);
  const byId = new Map(deckCards.map((card) => [card.id, card]));
  const entry = quizOrder[quizIndex];
  const rev = entryRev(entry);
  const card = byId.get(entryId(entry));
  if (!card) return;
  document.getElementById("quiz-question").textContent = rev ? card.answer : card.question;
  const box = document.getElementById("quiz-options");
  box.textContent = "";
  const frag = document.createDocumentFragment();
  buildOptions(card, deckCards, rev).forEach((option, optIdx) => {
    const button = makeEl("button", "btn quiz-option", option.text);
    button.type = "button";
    button.dataset.ok = option.ok ? "1" : "0";
    button.dataset.key = String(optIdx + 1);
    frag.appendChild(button);
  });
  box.appendChild(frag);
  quizAnswered = false;
  document.getElementById("quiz-next").classList.add("hidden");
  updateQuizMeta();
}

function answerQuiz(button) {
  if (quizAnswered || !quizActive) return;
  quizAnswered = true;
  const ok = button.dataset.ok === "1";
  const entry = quizOrder[quizIndex];
  const cardId = entryId(entry);
  const card = state.cards.find((item) => item.id === cardId);
  Array.from(document.querySelectorAll("#quiz-options .quiz-option")).forEach((option) => {
    if (option.dataset.ok === "1") {
      option.classList.add("is-right");
      if (option === button && !reduceMotion()) {
        option.insertAdjacentHTML(
          "beforeend",
          '<svg class="check-draw" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12.5 L9.5 18 L20 6.5" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>'
        );
      }
    } else if (option === button) option.classList.add("is-wrong");
    else option.classList.add("is-dim");
  });
  if (card) {
    card.status = ok ? "known" : "unknown";
    (ok ? quizRight : quizWrong).add(entry);
    getTodayStats()[ok ? "known" : "unknown"] += 1;
    recordStudy(state.selectedDeckId, ok ? "known" : "unknown");
    saveState();
    renderStats();
    updateCardRowStatus(cardId);
  }
  if (ok && !reduceMotion()) {
    const fill = document.getElementById("quiz-fill");
    const track = fill.parentElement;
    track.classList.remove("sheen");
    void track.offsetWidth;
    track.classList.add("sheen");
  }
  const next = document.getElementById("quiz-next");
  next.textContent = quizIndex === quizOrder.length - 1 ? "К итогу" : "Дальше";
  next.classList.remove("hidden");
  updateQuizMeta();
}

function nextQuiz() {
  if (!quizActive || !quizAnswered) return;
  if (quizIndex >= quizOrder.length - 1) {
    finishQuiz();
    return;
  }
  quizIndex += 1;
  renderQuizQuestion();
}

function finishQuiz() {
  const total = quizOrder.length;
  const known = quizRight.size;
  const unknown = quizWrong.size;
  quizActive = false;
  quizAnswered = false;
  recordSession(state.selectedDeckId, known, unknown);
  saveState();
  quizRetry = unknown > 0 ? [...quizWrong] : null;
  syncStudyView();
  openSummaryOverlay(total, known, unknown, unknown > 0 ? "quiz" : "quiz-all");
}

function launchConfetti() {
  if (reduceMotion()) return;
  const backdrop = document.getElementById("summary-backdrop");
  const layer = document.createElement("div");
  layer.className = "confetti-layer";
  backdrop.appendChild(layer);
  const styles = getComputedStyle(document.documentElement);
  const colors = ["--accent", "--accent-2", "--accent-3", "--known", "--tab"].map((name) => styles.getPropertyValue(name).trim() || "#e85d04");
  const W = backdrop.clientWidth;
  const pieces = 70;
  for (let i = 0; i < pieces; i += 1) {
    const piece = document.createElement("i");
    piece.className = "confetti-piece";
    piece.style.background = colors[i % colors.length];
    piece.style.left = Math.random() * W + "px";
    layer.appendChild(piece);
    const drift = (Math.random() - 0.5) * 260;
    const fall = backdrop.clientHeight + 40;
    const dur = 1100 + Math.random() * 900;
    piece.animate(
      [
        { transform: `translate(0,0) rotate(0deg)`, opacity: 1 },
        { transform: `translate(${drift}px, ${fall}px) rotate(${(Math.random() * 2 - 1) * 540}deg)`, opacity: 0.9 },
      ],
      { duration: dur, delay: Math.random() * 350, easing: "cubic-bezier(0.2,0.6,0.4,1)", fill: "forwards" }
    );
  }
  setTimeout(() => layer.remove(), 2600);
}

function openSummaryOverlay(total, known, unknown, mode) {
  const backdrop = document.getElementById("summary-backdrop");
  backdrop.style.zIndex = focusMode || quizFullscreen ? "66" : "";
  const percent = total ? Math.round((known / total) * 100) : 0;
  if (total > 0 && percent === 100 && (mode === "quiz-all" || mode === "quiz" || mode === "all")) {
    launchConfetti();
  }
  document.getElementById("summary-line").textContent =
    `Всего ${total} · знаю ${known} · не знаю ${unknown}`;
  document.getElementById("summary-fill").style.width = percent + "%";

  const repeat = document.getElementById("summary-repeat");
  repeat.hidden = false;
  if (mode === "quiz") {
    repeat.textContent = "Повторить неизученное";
    repeat.dataset.mode = "quiz";
  } else if (mode === "quiz-all") {
    repeat.textContent = "Пройти ещё раз";
    repeat.dataset.mode = "quiz-all";
  } else if (mode === "unknown") {
    repeat.textContent = "Повторить неизученное";
    repeat.dataset.mode = "unknown";
  } else {
    repeat.textContent = "Пройти ещё раз";
    repeat.dataset.mode = "all";
  }

  showLayer(backdrop);
  lockScroll(true);
  repeat.focus();
}

function showSummary() {
  const cards = currentStudyCards();
  const byIndex = new Map(cards.map((card) => [card.id, card]));
  const doneEntries = state.studyOrder.filter((entry) => sessionMarked.has(entry));
  let known = 0;
  let unknown = 0;
  doneEntries.forEach((entry) => {
    const card = byIndex.get(entryId(entry));
    if (!card) return;
    if (card.status === "known") known += 1;
    else unknown += 1;
  });

  recordSession(state.selectedDeckId, known, unknown);
  saveState();

  openSummaryOverlay(doneEntries.length, known, unknown, unknown > 0 ? "unknown" : "all");
}

function closeSummary() {
  document.getElementById("summary-backdrop").classList.remove("is-open");
  lockScroll(false);
}

function repeatStudy() {
  const repeat = document.getElementById("summary-repeat");
  const mode = repeat.dataset.mode;
  if (mode === "quiz" || mode === "quiz-all") {
    const ids = mode === "quiz" ? quizRetry || [] : quizOrder.slice();
    closeSummary();
    beginQuiz(ids.length ? ids : shuffle(cardsInDeck(state.selectedDeckId).map((card) => card.id)));
    return;
  }
  const unknownOnly = mode === "unknown";
  const entries = buildStudyEntries(state.selectedDeckId);
  const ids = unknownOnly
    ? entries.filter((entry) => {
        const card = state.cards.find((item) => item.id === entryId(entry));
        return card && card.status === "unknown";
      })
    : entries;
  beginRound(ids.length ? ids : entries);
  closeSummary();
  showStudyCard();
}



