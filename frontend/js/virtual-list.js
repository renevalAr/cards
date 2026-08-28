class VirtualList {
  constructor(container, { loadMore, renderItem, threshold = 200 }) {
    this.container = container;
    this.loadMore = loadMore;
    this.renderItem = renderItem;
    this.threshold = threshold;
    this.items = [];
    this.cursor = null;
    this.loading = false;
    this.hasMore = true;
    this.observer = null;
    this.sentinel = null;

    this._setupSentinel();
  }

  _setupSentinel() {
    this.sentinel = document.createElement("div");
    this.sentinel.className = "scroll-sentinel";
    this.sentinel.style.height = "1px";
    this.container.appendChild(this.sentinel);

    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && this.hasMore && !this.loading) {
          this.loadNext();
        }
      },
      { root: this.container, rootMargin: `${this.threshold}px` }
    );
    this.observer.observe(this.sentinel);
  }

  async loadNext() {
    if (this.loading || !this.hasMore) return;
    this.loading = true;
    this._showLoader();

    try {
      const result = await this.loadMore(this.cursor);
      const newItems = result.items || result;
      this.cursor = result.next_cursor || null;
      this.hasMore = !!result.next_cursor;

      if (newItems.length === 0) {
        this.hasMore = false;
      }

      this.items.push(...newItems);
      this._renderItems(newItems);
    } catch (err) {
      console.error("Failed to load more:", err);
    } finally {
      this.loading = false;
      this._hideLoader();
      if (!this.hasMore) {
        this._showEnd();
      }
    }
  }

  _showLoader() {
    let loader = this.container.querySelector(".list-loader");
    if (!loader) {
      loader = document.createElement("div");
      loader.className = "list-loader";
      loader.textContent = "Загрузка…";
      this.container.appendChild(loader);
    }
    loader.hidden = false;
  }

  _hideLoader() {
    const loader = this.container.querySelector(".list-loader");
    if (loader) loader.hidden = true;
  }

  _showEnd() {
    let end = this.container.querySelector(".list-end");
    if (!end) {
      end = document.createElement("div");
      end.className = "list-end";
      end.textContent = "Все карточки загружены";
      this.container.appendChild(end);
    }
    end.hidden = false;
  }

  _renderItems(items) {
    const frag = document.createDocumentFragment();
    items.forEach((item) => {
      const el = this.renderItem(item);
      if (el) frag.appendChild(el);
    });
    this.container.insertBefore(frag, this.sentinel);
  }

  reset() {
    this.items = [];
    this.cursor = null;
    this.loading = false;
    this.hasMore = true;
    const items = this.container.querySelectorAll(".virtual-item");
    items.forEach((el) => el.remove());
    const end = this.container.querySelector(".list-end");
    if (end) end.hidden = true;
  }

  refresh() {
    this.reset();
    return this.loadNext();
  }

  destroy() {
    if (this.observer) {
      this.observer.disconnect();
    }
  }
}
