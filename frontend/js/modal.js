let modalResolver = null;
let modalTrigger = null;
let settingsTrigger = null;
let savedScrollY = 0;

function getFocusable(backdrop) {
  return Array.from(
    backdrop.querySelectorAll(
      'button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [href], [tabindex]:not([tabindex="-1"])'
    )
  ).filter((el) => el.getClientRects().length > 0);
}

function lockScroll(lock) {
  if (lock) {
    savedScrollY = window.scrollY || document.documentElement.scrollTop;
    document.body.style.top = `-${savedScrollY}px`;
  }
  document.body.classList.toggle("modal-open", lock);
  document.documentElement.classList.toggle("modal-open", lock);
  if (!lock) {
    document.body.style.top = "";
    window.scrollTo(0, savedScrollY);
  }
}

function showLayer(backdrop) {
  backdrop.hidden = false;
  backdrop.classList.add("is-open");
  void backdrop.offsetWidth;
}

function hideLayer(backdrop) {
  backdrop.classList.remove("is-open");
  backdrop.hidden = true;
}

function trapTabKey(backdrop, event) {
  if (event.key !== "Tab") return;
  const focusables = getFocusable(backdrop);
  if (!focusables.length) return;
  const first = focusables[0];
  const last = focusables[focusables.length - 1];
  const inside = backdrop.contains(document.activeElement);
  if (event.shiftKey) {
    if (!inside || document.activeElement === first) {
      event.preventDefault();
      last.focus();
    }
  } else if (!inside || document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
}

function openModal({ title, kicker, text, confirmOnly, value, confirmText }) {
  const backdrop = document.getElementById("modal-backdrop");
  if (backdrop.classList.contains("is-open")) closeModal(null);

  modalTrigger = document.activeElement;
  document.getElementById("modal-title").textContent = title;
  document.getElementById("modal-kicker").textContent = kicker || "колода";
  document.getElementById("modal-text").textContent = text || "";

  const field = document.getElementById("modal-field");
  field.classList.toggle("hidden", Boolean(confirmOnly));

  const ok = document.getElementById("modal-ok");
  ok.className = confirmOnly ? "btn btn-danger" : "btn btn-primary";
  ok.textContent = confirmOnly ? confirmText || "Удалить" : "Готово";

  const input = document.getElementById("modal-input");
  input.value = value || "";

  showLayer(backdrop);
  lockScroll(true);
  if (confirmOnly) {
    document.getElementById("modal-cancel").focus();
  } else {
    input.focus();
    input.select();
  }

  return new Promise((resolve) => {
    modalResolver = resolve;
  });
}

function canFocus(el) {
  return (
    el.isConnected &&
    el.getClientRects().length > 0 &&
    getComputedStyle(el).visibility !== "hidden" &&
    getComputedStyle(el).display !== "none"
  );
}

function closeModal(result) {
  const backdrop = document.getElementById("modal-backdrop");
  hideLayer(backdrop);
  lockScroll(false);
  if (modalResolver) modalResolver(result);
  modalResolver = null;
  if (modalTrigger && canFocus(modalTrigger)) modalTrigger.focus();
  modalTrigger = null;
}

function openSettingsModal() {
  const backdrop = document.getElementById("settings-backdrop");
  settingsTrigger = document.activeElement;
  showLayer(backdrop);
  lockScroll(true);
  backdrop.querySelector(".modal").focus();
  syncAppearanceButtons();
  syncFontButtons();
}

function closeSettingsModal() {
  const backdrop = document.getElementById("settings-backdrop");
  hideLayer(backdrop);
  if (!document.getElementById("menu-backdrop").classList.contains("is-open")) lockScroll(false);
  if (settingsTrigger && canFocus(settingsTrigger)) settingsTrigger.focus();
  settingsTrigger = null;
}

function closeTopModal() {
  const layers = [
    ["modal-backdrop", () => closeModal(null)],
    ["settings-backdrop", closeSettingsModal],
    ["data-backdrop", () => window.closeDataDialog && closeDataDialog()],
    ["bulk-backdrop", () => window.closeBulkInput && closeBulkInput()],
    ["library-backdrop", () => window.closeLibrary && closeLibrary()],
    ["summary-backdrop", closeSummary],
    ["stats-backdrop", closeStats],
    ["deck-pick-backdrop", closeDeckPicker],
    ["menu-pop-backdrop", closeMenuPop],
    ["menu-backdrop", closeMenu],
  ];
  for (const [id, closer] of layers) {
    const el = document.getElementById(id);
    if (el && el.classList.contains("is-open")) {
      closer();
      return;
    }
  }
}

function bindModalEvents() {
  const backdrop = document.getElementById("modal-backdrop");
  const settingsBackdrop = document.getElementById("settings-backdrop");

  document.getElementById("modal-cancel").addEventListener("click", () => closeModal(null));
  backdrop.addEventListener("click", (event) => {
    if (event.target.id === "modal-backdrop") closeModal(null);
  });
  backdrop.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.stopPropagation();
      closeModal(null);
    } else {
      trapTabKey(backdrop, event);
    }
  });

  document.getElementById("modal-ok").addEventListener("click", () => {
    const confirmOnly = document.getElementById("modal-field").classList.contains("hidden");
    if (confirmOnly) {
      closeModal(true);
      return;
    }
    const name = document.getElementById("modal-input").value.trim();
    closeModal(name || null);
  });

  document.getElementById("modal-input").addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      document.getElementById("modal-ok").click();
    } else if (event.key === "Escape") {
      closeModal(null);
    } else {
      trapTabKey(backdrop, event);
    }
  });

  document.getElementById("settings-btn").addEventListener("click", openSettingsModal);
  document.getElementById("settings-close").addEventListener("click", closeSettingsModal);
  settingsBackdrop.addEventListener("click", (event) => {
    if (event.target.id === "settings-backdrop") closeSettingsModal();
  });
  settingsBackdrop.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.stopPropagation();
      closeSettingsModal();
    } else {
      trapTabKey(settingsBackdrop, event);
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeTopModal();
  });
}
