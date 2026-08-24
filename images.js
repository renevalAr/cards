const IMG_DB = "flashcards-images";
const IMG_STORE = "images";
const IMG_MAX_SIDE = 480;
const IMG_QUALITY = 0.6;

let imgDbPromise = null;

function imgOpen() {
  if (imgDbPromise) return imgDbPromise;
  imgDbPromise = new Promise((resolve, reject) => {
    const request = indexedDB.open(IMG_DB, 1);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(IMG_STORE)) db.createObjectStore(IMG_STORE);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  return imgDbPromise;
}

function imgTx(mode) {
  return imgOpen().then((db) => db.transaction(IMG_STORE, mode).objectStore(IMG_STORE));
}

function imgReq(store, method, args) {
  return new Promise((resolve, reject) => {
    const request = store[method].apply(store, args);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function imgGet(cardId) {
  return imgTx("readonly").then((store) => imgReq(store, "get", [cardId]));
}

function imgPut(cardId, dataUrl) {
  return imgTx("readwrite").then((store) => imgReq(store, "put", [dataUrl, cardId]));
}

function imgDelete(cardId) {
  return imgTx("readwrite").then((store) => imgReq(store, "delete", [cardId]));
}

function imgGcOrphans(liveIds) {
  const live = new Set(liveIds);
  return imgTx("readonly")
    .then((store) => imgReq(store, "getAllKeys", []))
    .then((keys) => {
      const orphans = keys.filter((key) => !live.has(key));
      if (!orphans.length) return 0;
      return imgTx("readwrite")
        .then((store) => Promise.all(orphans.map((key) => imgReq(store, "delete", [key]))))
        .then(() => orphans.length);
    })
    .catch(() => -1);
}

function loadImageElement(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve(img);
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("bad-image"));
    };
    img.src = url;
  });
}

async function compressImageFile(file) {
  const img = await loadImageElement(file);
  const scale = Math.min(1, IMG_MAX_SIDE / Math.max(img.naturalWidth, img.naturalHeight));
  const w = Math.max(1, Math.round(img.naturalWidth * scale));
  const h = Math.max(1, Math.round(img.naturalHeight * scale));
  const canvas = document.createElement("canvas");
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext("2d");
  ctx.drawImage(img, 0, 0, w, h);
  let dataUrl = canvas.toDataURL("image/webp", IMG_QUALITY);
  if (!dataUrl.startsWith("data:image/webp")) {
    dataUrl = canvas.toDataURL("image/jpeg", IMG_QUALITY);
  }
  return dataUrl;
}
