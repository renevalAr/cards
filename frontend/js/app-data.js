const AppData = {
  syncing: false,
  error: null,

  async syncFromServer() {
    if (this.syncing) return;
    this.syncing = true;
    this.error = null;

    try {
      const decks = await Decks.list();
      state.decks = decks.map((d) => ({
        id: d.id,
        name: d.name,
        twoSided: d.two_sided,
      }));

      state.cards = [];
      for (const deck of decks) {
        const res = await Decks.getCards(deck.id, { limit: 100 });
        const cards = res.items || res;
        state.cards.push(
          ...cards.map((c) => ({
            id: c.id,
            deckId: c.deck_id,
            question: c.question,
            answer: c.answer,
            status: c.status || "new",
          }))
        );
      }

      saveState();
      if (typeof render === "function") render();
    } catch (err) {
      this.error = err.message;
      console.error("Sync failed:", err);
      if (typeof showToast === "function") {
        showToast("Не удалось загрузить данные с сервера", "warn");
      }
    } finally {
      this.syncing = false;
    }
  },

  async createDeck(name, description, twoSided) {
    const deck = await Decks.create({ name, description, two_sided: twoSided });
    state.decks.push({ id: deck.id, name: deck.name, twoSided: deck.two_sided });
    saveState();
    return deck;
  },

  async deleteDeck(deckId) {
    await Decks.delete(deckId);
    state.decks = state.decks.filter((d) => d.id !== deckId);
    state.cards = state.cards.filter((c) => c.deckId !== deckId);
    if (state.selectedDeckId === deckId) {
      state.selectedDeckId = null;
    }
    saveState();
  },

  async addCard(deckId, question, answer) {
    const card = await Decks.addCard(deckId, { question, answer });
    state.cards.push({
      id: card.id,
      deckId: card.deck_id,
      question: card.question,
      answer: card.answer,
      status: card.status || "new",
    });
    saveState();
    return card;
  },

  async deleteCard(cardId) {
    await Data.deleteCard(cardId);
    state.cards = state.cards.filter((c) => c.id !== cardId);
    saveState();
  },

  isSyncing() {
    return this.syncing;
  },

  getError() {
    return this.error;
  },
};
