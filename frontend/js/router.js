const Router = {
  currentRoute: null,
  currentParams: null,

  init() {
    window.addEventListener("hashchange", () => this._handleRoute());
    this._handleRoute();
  },

  _handleRoute() {
    const hash = window.location.hash || "#menu";
    const [route, ...params] = hash.substring(1).split("/");

    this.currentRoute = route;
    this.currentParams = params;

    switch (route) {
      case "login":
        if (typeof showAuthModal === "function") showAuthModal();
        break;
      case "register":
        if (typeof showAuthModal === "function") showAuthModal();
        if (typeof Auth !== "undefined" && Auth.user) {
          window.location.hash = "#menu";
        }
        break;
      case "deck":
        if (params[0] && typeof menuOpenCards === "function") {
          menuOpenCards(params[0]);
        } else if (typeof openMenu === "function") {
          openMenu();
        }
        break;
      case "d":
        if (params[0] && typeof Share !== "undefined") {
          Share.viewPublicDeck(params[0]);
          if (typeof setTab === "function") setTab("study");
        }
        break;
      case "menu":
        if (typeof openMenu === "function") openMenu();
        break;
      case "stats":
        if (typeof openStats === "function") openStats();
        break;
      case "settings":
        if (typeof openSettingsModal === "function") openSettingsModal();
        break;
      default:
        if (typeof openMenu === "function") openMenu();
    }
  },
};
