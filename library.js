let libraryTrigger = null;

const DEMO_KEY = "flashcards-demos";

function addedDemoIds() {
  try {
    const raw = JSON.parse(localStorage.getItem(DEMO_KEY) || "[]");
    return Array.isArray(raw) ? raw.filter((id) => typeof id === "string") : [];
  } catch (error) {
    return [];
  }
}

function markDemoAdded(demoId) {
  try {
    const ids = addedDemoIds();
    if (!ids.includes(demoId)) ids.push(demoId);
    localStorage.setItem(DEMO_KEY, JSON.stringify(ids));
  } catch (error) {
    console.warn("Не удалось сохранить отметку демо-колоды", error);
  }
}

const DEMO_DECKS = [
  {
    id: "demo-english",
    name: "Английский · старт",
    tag: "языки",
    description: "30 самых частотных слов для первого шага.",
    cards: [
      ["hello", "привет"],
      ["goodbye", "до свидания"],
      ["please", "пожалуйста"],
      ["thank you", "спасибо"],
      ["yes", "да"],
      ["no", "нет"],
      ["I", "я"],
      ["you", "ты, вы"],
      ["we", "мы"],
      ["they", "они"],
      ["to be", "быть"],
      ["to have", "иметь"],
      ["to do", "делать"],
      ["to go", "идти, ехать"],
      ["to see", "видеть"],
      ["to know", "знать"],
      ["to want", "хотеть"],
      ["to like", "нравиться"],
      ["big", "большой"],
      ["small", "маленький"],
      ["good", "хороший"],
      ["bad", "плохой"],
      ["new", "новый"],
      ["old", "старый"],
      ["man", "мужчина"],
      ["woman", "женщина"],
      ["child", "ребёнок"],
      ["friend", "друг"],
      ["family", "семья"],
      ["home", "дом"],
    ],
  },
  {
    id: "demo-capitals",
    name: "Столицы мира",
    tag: "география",
    description: "12 столиц — страна или столица, наоборот.",
    cards: [
      ["Россия", "Москва"],
      ["Франция", "Париж"],
      ["Германия", "Берлин"],
      ["Италия", "Рим"],
      ["Испания", "Мадрид"],
      ["Великобритания", "Лондон"],
      ["Япония", "Токио"],
      ["Китай", "Пекин"],
      ["США", "Вашингтон"],
      ["Бразилия", "Бразилиа"],
      ["Австралия", "Канберра"],
      ["Египет", "Каир"],
    ],
  },
  {
    id: "demo-elements",
    name: "Химические элементы",
    tag: "наука",
    description: "Первые 15 элементов таблицы Менделеева.",
    cards: [
      ["H", "Водород"],
      ["He", "Гелий"],
      ["Li", "Литий"],
      ["Be", "Бериллий"],
      ["B", "Бор"],
      ["C", "Углерод"],
      ["N", "Азот"],
      ["O", "Кислород"],
      ["F", "Фтор"],
      ["Ne", "Неон"],
      ["Na", "Натрий"],
      ["Mg", "Магний"],
      ["Al", "Алюминий"],
      ["Si", "Кремний"],
      ["P", "Фосфор"],
    ],
  },
];

function renderLibrary() {
  const list = document.getElementById("library-list");
  list.textContent = "";
  const frag = document.createDocumentFragment();
  const added = new Set(addedDemoIds());
  DEMO_DECKS.forEach((demo) => {
    const item = makeEl("article", "library-item");
    const head = makeEl("div", "library-head");
    head.append(makeEl("h4", "library-name", demo.name));
    head.append(makeEl("span", "badge", demo.tag));
    item.append(head);
    item.append(makeEl("p", "library-desc", demo.description));
    item.append(makeEl("p", "library-count", `${demo.cards.length} карточек`));
    const add = makeEl("button", "btn btn-primary", added.has(demo.id) ? "Добавлено ✓" : "Добавить");
    add.type = "button";
    if (added.has(demo.id)) add.disabled = true;
    else add.addEventListener("click", () => addDemoDeck(demo.id));
    item.appendChild(add);
    frag.appendChild(item);
  });
  list.appendChild(frag);
}

function openLibrary() {
  libraryTrigger = document.activeElement;
  renderLibrary();
  const backdrop = document.getElementById("library-backdrop");
  showLayer(backdrop);
  lockScroll(true);
  backdrop.querySelector(".modal").focus();
}

function closeLibrary() {
  const backdrop = document.getElementById("library-backdrop");
  hideLayer(backdrop);
  lockScroll(false);
  if (libraryTrigger && canFocus(libraryTrigger)) libraryTrigger.focus();
  libraryTrigger = null;
}

function addDemoDeck(demoId) {
  const demo = DEMO_DECKS.find((item) => item.id === demoId);
  if (!demo || addedDemoIds().includes(demoId)) return;
  markDemoAdded(demoId);
  const deckId = uid();
  state.decks.push({ id: deckId, name: demo.name });
  demo.cards.forEach(([question, answer]) => {
    state.cards.push({ id: uid(), deckId, question, answer, status: "new" });
  });
  state.selectedDeckId = deckId;
  state.tab = "edit";
  resetStudy();
  saveState();
  closeLibrary();
  render();
}

const libraryBackdrop = document.getElementById("library-backdrop");
document.getElementById("menu-library-btn").addEventListener("click", openLibrary);
document.getElementById("library-cancel").addEventListener("click", closeLibrary);
libraryBackdrop.addEventListener("click", (event) => {
  if (event.target.id === "library-backdrop") closeLibrary();
});
libraryBackdrop.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    event.stopPropagation();
    closeLibrary();
  } else {
    trapTabKey(libraryBackdrop, event);
  }
});
