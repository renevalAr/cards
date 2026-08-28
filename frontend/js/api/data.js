const Data = {
  async loadDecks() {
    return Decks.list();
  },

  async loadDeck(id) {
    return Decks.get(id);
  },

  async createDeck(data) {
    return Decks.create(data);
  },

  async updateDeck(id, data) {
    return Decks.update(id, data);
  },

  async deleteDeck(id) {
    return Decks.delete(id);
  },

  async loadCards(deckId, { cursor = "", search = "", limit = 30 } = {}) {
    return Decks.getCards(deckId, { cursor, search, limit });
  },

  async addCard(deckId, data) {
    return Decks.addCard(deckId, data);
  },

  async updateCard(id, data) {
    return API.patch(`/cards/${id}`, data);
  },

  async deleteCard(id) {
    return API.delete(`/cards/${id}`);
  },

  async uploadImage(cardId, file) {
    const formData = new FormData();
    formData.append("file", file);
    return fetch(`${API.baseURL}/cards/${cardId}/image`, {
      method: "POST",
      body: formData,
      credentials: "include",
    }).then((res) => {
      if (!res.ok) throw new Error("Upload failed");
      return res.json();
    });
  },

  async enableShare(deckId) {
    return API.post(`/decks/${deckId}/share`);
  },

  async disableShare(deckId) {
    return API.delete(`/decks/${deckId}/share`);
  },

  async getPublicDeck(slug) {
    return API.get(`/decks/share/${slug}`);
  },

  async getPublicCards(slug) {
    return API.get(`/decks/share/${slug}/cards`);
  },

  async startStudySession(deckId) {
    return API.post("/study/session", { deck_id: deckId });
  },

  async updateStudySession(sessionId, known, unknown) {
    return API.patch(`/study/session/${sessionId}`, { known, unknown });
  },

  async getStudyStats() {
    return API.get("/study/stats");
  },

  async migrateData(payload) {
    return API.post("/migrate", payload);
  },

  exportLocalData() {
    try {
      const raw = localStorage.getItem("flashcards-app-v1");
      if (!raw) return null;
      const data = JSON.parse(raw);
      return {
        version: "migration-v1",
        exported_at: new Date().toISOString(),
        decks: (data.decks || []).map((deck) => ({
          name: deck.name,
          description: deck.description || null,
          two_sided: deck.two_sided || false,
          cards: (data.cards || [])
            .filter((c) => c.deckId === deck.id)
            .map((c) => ({
              question: c.question,
              answer: c.answer,
              status: c.status || "new",
            })),
        })),
      };
    } catch {
      return null;
    }
  },
};
