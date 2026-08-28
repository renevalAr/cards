const API = {
  baseURL: "/api",
  refreshPromise: null,

  async request(method, path, body = null, retry = true) {
    const options = {
      method,
      headers: {},
      credentials: "include",
    };

    if (body) {
      options.headers["Content-Type"] = "application/json";
      options.body = JSON.stringify(body);
    }

    let res;
    try {
      res = await fetch(`${this.baseURL}${path}`, options);
    } catch (err) {
      if (err.name === "TypeError") {
        if (typeof showToast === "function") {
          showToast("Нет соединения с сервером", "warn");
        }
      }
      throw err;
    }

    if (res.status === 401 && retry && path !== "/auth/login" && path !== "/auth/refresh") {
      const refreshed = await this._tryRefresh();
      if (refreshed) {
        return this.request(method, path, body, false);
      }
      if (typeof Auth !== "undefined") {
        Auth.user = null;
      }
      window.location.hash = "#login";
      throw new Error("Session expired");
    }

    if (!res.ok) {
      const error = await res.json().catch(() => ({ detail: "Request failed" }));
      throw new Error(error.detail || `HTTP ${res.status}`);
    }

    if (res.status === 204) return null;
    return res.json();
  },

  async _tryRefresh() {
    if (this.refreshPromise) {
      return this.refreshPromise;
    }
    this.refreshPromise = (async () => {
      try {
        const res = await fetch(`${this.baseURL}/auth/refresh`, {
          method: "POST",
          credentials: "include",
        });
        return res.ok;
      } catch {
        return false;
      } finally {
        this.refreshPromise = null;
      }
    })();
    return this.refreshPromise;
  },

  get(path) { return this.request("GET", path); },
  post(path, body) { return this.request("POST", path, body); },
  patch(path, body) { return this.request("PATCH", path, body); },
  delete(path) { return this.request("DELETE", path); },
};

const Auth = {
  user: null,
  accessToken: null,

  async init() {
    try {
      const user = await API.get("/auth/me");
      this.user = user;
      return user;
    } catch {
      this.user = null;
      return null;
    }
  },

  async register(email, password) {
    return API.post("/auth/register", { email, password });
  },

  async login(email, password) {
    const res = await API.post("/auth/login", { email, password });
    this.accessToken = res.access_token;
    const user = await API.get("/auth/me");
    this.user = user;
    return user;
  },

  async logout() {
    try {
      await API.post("/auth/logout");
    } catch {}
    this.user = null;
    this.accessToken = null;
  },

  isAuthenticated() {
    return this.user !== null;
  },

  getUser() {
    return this.user;
  },
};

const Decks = {
  async list() {
    return API.get("/decks");
  },

  async get(id) {
    return API.get(`/decks/${id}`);
  },

  async create(data) {
    return API.post("/decks", data);
  },

  async update(id, data) {
    return API.patch(`/decks/${id}`, data);
  },

  async delete(id) {
    return API.delete(`/decks/${id}`);
  },

  async getCards(id, { cursor = "", search = "", limit = 30 } = {}) {
    const params = new URLSearchParams({ limit: String(limit) });
    if (cursor) params.set("cursor", cursor);
    if (search) params.set("search", search);
    return API.get(`/decks/${id}/cards?${params}`);
  },

  async addCard(id, data) {
    return API.post(`/decks/${id}/cards`, data);
  },
};
