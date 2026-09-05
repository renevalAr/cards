const Share = {
  currentDeck: null,

  async viewPublicDeck(slug) {
    try {
      const deck = await Data.getPublicDeck(slug);
      const cards = await Data.getPublicCards(slug);
      this.currentDeck = { ...deck, cards };
      this._renderPublicDeck();
      return this.currentDeck;
    } catch (err) {
      console.error("Failed to load public deck:", err);
      if (typeof showToast === "function") showToast("Не удалось загрузить публичную колоду", "warn");
      return null;
    }
  },

  async enableSharing(deckId) {
    const deck = await Data.enableShare(deckId);
    return deck;
  },

  async disableSharing(deckId) {
    await Data.disableShare(deckId);
  },

  getShareUrl(deck) {
    if (!deck.share_slug) return null;
    return `${window.location.origin}/d/${deck.share_slug}`;
  },

  async copyShareLink(deck) {
    const url = this.getShareUrl(deck);
    if (!url) return false;
    try {
      await navigator.clipboard.writeText(url);
      return true;
    } catch {
      return false;
    }
  },

  _renderPublicDeck() {
    const deck = this.currentDeck;
    if (!deck) return;

    const title = document.getElementById("deck-title");
    const stats = document.getElementById("stats");
    if (title) title.textContent = deck.name;
    if (stats) stats.textContent = `${deck.cards.length} карточек · публичная колода`;

    const rows = document.getElementById("card-rows");
    if (rows) {
      rows.textContent = "";
      const frag = document.createDocumentFragment();
      deck.cards.forEach((card) => {
        const li = document.createElement("li");
        li.textContent = `${card.question} — ${card.answer}`;
        frag.appendChild(li);
      });
      rows.appendChild(frag);
    }
  },
};
