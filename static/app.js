// Rateverything — minimal single-page frontend talking to the Haskell JSON API.
"use strict";

const app = document.getElementById("app");
const nav = document.getElementById("nav");

// --- session ------------------------------------------------------------------

const session = {
  get token() { return localStorage.getItem("token"); },
  get user() { const u = localStorage.getItem("user"); return u ? JSON.parse(u) : null; },
  save(s) { localStorage.setItem("token", s.token); localStorage.setItem("user", JSON.stringify(s.user)); },
  clear() { localStorage.removeItem("token"); localStorage.removeItem("user"); },
};

async function api(path, { method = "GET", json, form } = {}) {
  const headers = {};
  if (session.token) headers.Authorization = "Bearer " + session.token;
  let body;
  if (json !== undefined) { headers["Content-Type"] = "application/json"; body = JSON.stringify(json); }
  if (form) body = form;
  const res = await fetch("/api" + path, { method, headers, body });
  if (res.status === 401 && session.token && !path.startsWith("/auth")) { session.clear(); renderNav(); }
  if (!res.ok) throw new Error((await res.text()) || res.statusText);
  return res.status === 204 ? null : res.json();
}

// --- helpers --------------------------------------------------------------------

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

function stars(rating) {
  if (!rating) return "";
  const full = Math.floor(rating / 2);
  return "★".repeat(full) + (rating % 2 ? "½" : "");
}

function cover(url, title, square) {
  const cls = "cover" + (square ? " square" : "");
  if (!url) return `<div class="${cls} cover-fallback">${esc(title)}</div>`;
  return `<img class="${cls}" src="${esc(url)}" alt="${esc(title)}" loading="lazy" onerror="coverFailed(this)">`;
}

// Providers sometimes have no artwork (e.g. Cover Art Archive answers 404).
window.coverFailed = (img) => {
  const div = document.createElement("div");
  div.className = img.className + " cover-fallback";
  div.textContent = img.alt;
  img.replaceWith(div);
};

const isSquare = (source) => source === "musicbrainz";

function card({ title, subtitle, year, imageUrl, source }, onClick) {
  const el = document.createElement("div");
  el.className = "card";
  el.innerHTML = `${cover(imageUrl, title, isSquare(source))}
    <div class="card-title">${esc(title)}</div>
    <div class="card-sub">${esc([subtitle, year].filter(Boolean).join(" · "))}</div>`;
  el.addEventListener("click", onClick);
  return el;
}

function showError(target, err) { target.textContent = err.message || String(err); }

// --- navigation -----------------------------------------------------------------

function renderNav() {
  const u = session.user;
  nav.innerHTML = u
    ? `<a href="#/nova-categoria">+ Nova categoria</a>
       <a href="#/u/${esc(u.username)}">Diário de ${esc(u.username)}</a>
       <button class="link" id="logout">Sair</button>`
    : `<a href="#/entrar">Entrar / Criar conta</a>`;
  const logout = document.getElementById("logout");
  if (logout) logout.onclick = async () => {
    try { await api("/auth/logout", { method: "POST" }); } catch (_) { /* session may already be gone */ }
    session.clear(); renderNav(); location.hash = "#/";
  };
}

const routes = [
  [/^#?\/?$/, () => categoryPage(null)],
  [/^#\/c\/([^/]+)$/, (slug) => categoryPage(decodeURIComponent(slug))],
  [/^#\/c\/([^/]+)\/novo$/, (slug) => newItemPage(decodeURIComponent(slug))],
  [/^#\/item\/(\d+)$/, (id) => itemPage(Number(id))],
  [/^#\/u\/([^/]+)$/, (name) => diaryPage(decodeURIComponent(name))],
  [/^#\/nova-categoria$/, () => newCategoryPage()],
  [/^#\/entrar$/, () => loginPage()],
];

async function route() {
  const hash = location.hash || "#/";
  for (const [re, handler] of routes) {
    const m = hash.match(re);
    if (m) {
      app.innerHTML = `<p class="muted">Carregando…</p>`;
      try { await handler(...m.slice(1)); } catch (e) { app.innerHTML = `<p class="error">${esc(e.message)}</p>`; }
      return;
    }
  }
  app.innerHTML = `<h1>Página não encontrada</h1>`;
}

// --- pages ----------------------------------------------------------------------

async function categoryPage(slug) {
  const categories = await api("/categories");
  const current = categories.find((c) => c.slug === slug) || categories[0];
  const user = session.user;
  const canAdd = user && (current.ownerId === null || current.ownerId === user.id);

  app.innerHTML = `
    <div class="tabs">${categories.map((c) =>
      `<a class="tab ${c.ownerId !== null ? "custom" : ""} ${c.id === current.id ? "active" : ""}" href="#/c/${esc(c.slug)}">${esc(c.name)}</a>`).join("")}
    </div>
    <div class="row" style="justify-content: space-between; margin-bottom: 12px">
      <div><h1>${esc(current.name)}</h1>${current.description ? `<div class="muted">${esc(current.description)}</div>` : ""}</div>
      ${canAdd ? `<a class="button secondary" href="#/c/${esc(current.slug)}/novo">+ Adicionar item</a>` : ""}
    </div>
    <form class="search" id="search">
      <input type="text" name="q" placeholder="Buscar em ${esc(current.name)}…" autofocus>
      <button>Buscar</button>
    </form>
    <div class="error" id="error"></div>
    <h2 id="list-title">Adicionados recentemente</h2>
    <div class="grid" id="results"></div>`;

  const results = document.getElementById("results");
  const error = document.getElementById("error");

  const showItems = (items) => {
    results.innerHTML = items.length ? "" : `<p class="muted">Nada por aqui ainda.</p>`;
    for (const it of items) results.appendChild(card(it, () => (location.hash = `#/item/${it.id}`)));
  };
  showItems(await api(`/categories/${encodeURIComponent(current.slug)}/items`));

  document.getElementById("search").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const q = new FormData(ev.target).get("q").trim();
    if (!q) return;
    error.textContent = "";
    document.getElementById("list-title").textContent = `Resultados para “${q}”`;
    results.innerHTML = `<p class="muted">Buscando…</p>`;
    try {
      const hits = await api(`/categories/${encodeURIComponent(current.slug)}/search?q=${encodeURIComponent(q)}`);
      results.innerHTML = hits.length ? "" : `<p class="muted">Nenhum resultado.</p>`;
      for (const hit of hits) results.appendChild(card(hit.item, () => openHit(current, hit, error)));
    } catch (e) { results.innerHTML = ""; showError(error, e); }
  });
}

async function openHit(category, hit, error) {
  if (hit.itemId) { location.hash = `#/item/${hit.itemId}`; return; }
  if (!session.user) { location.hash = "#/entrar"; return; }
  try {
    const item = await api(`/categories/${encodeURIComponent(category.slug)}/import`, { method: "POST", json: hit.item });
    location.hash = `#/item/${item.id}`;
  } catch (e) { showError(error, e); }
}

async function itemPage(id) {
  const d = await api(`/items/${id}`);
  const { item, category } = d;
  const user = session.user;
  const avg = d.averageRating ? (d.averageRating / 2).toFixed(1) : null;

  app.innerHTML = `
    <div class="detail">
      <div>${cover(item.imageUrl, item.title, isSquare(item.source))}</div>
      <div>
        <a class="muted" href="#/c/${esc(category.slug)}">${esc(category.name)}</a>
        <h1>${esc(item.title)} ${item.year ? `<span class="muted">${item.year}</span>` : ""}</h1>
        ${item.subtitle ? `<div class="muted">${esc(item.subtitle)}</div>` : ""}
        ${item.description ? `<p>${esc(item.description)}</p>` : ""}
        <p>${avg ? `<span class="stars">★</span> <strong>${avg}</strong> <span class="muted">/ 5 · ${d.ratingCount} nota(s)</span>` : `<span class="muted">Sem notas ainda</span>`}</p>
        ${user ? reviewForm() : `<p><a href="#/entrar" class="button">Entre para avaliar</a></p>`}
        <h2>Reviews</h2>
        <div class="panel" id="reviews">${d.reviews.length ? d.reviews.map(reviewHtml).join("") : `<span class="muted">Ninguém comentou ainda.</span>`}</div>
      </div>
    </div>`;

  if (user) bindReviewForm(id);
  app.querySelectorAll("[data-delete]").forEach((btn) => btn.addEventListener("click", async () => {
    if (!confirm("Apagar essa review?")) return;
    await api(`/reviews/${btn.dataset.delete}`, { method: "DELETE" });
    itemPage(id);
  }));
}

function reviewHtml(r) {
  const mine = session.user && session.user.id === r.userId;
  return `<div class="review">
    <div class="row">
      <a href="#/u/${esc(r.username)}"><strong>${esc(r.username)}</strong></a>
      <span class="stars">${stars(r.rating)}</span>
      ${r.liked ? `<span class="heart">♥</span>` : ""}
      <span class="muted">${esc(r.consumedOn || r.createdAt.slice(0, 10))}</span>
      ${mine ? `<button class="link" data-delete="${r.id}">apagar</button>` : ""}
    </div>
    ${r.body ? `<div>${esc(r.body)}</div>` : ""}
  </div>`;
}

function reviewForm() {
  const today = new Date().toISOString().slice(0, 10);
  return `<form class="panel form" id="review-form" style="max-width: none">
    <div class="row"><div class="star-input" id="star-input"></div><button type="button" class="link" id="clear-stars">limpar</button>
      <label class="inline" style="margin-left:auto"><input type="checkbox" name="liked"> <span class="heart">♥</span> curti</label></div>
    <label>Quando? <input type="date" name="consumedOn" value="${today}"></label>
    <label>Review (opcional) <textarea name="body" placeholder="O que você achou?"></textarea></label>
    <div class="error" id="review-error"></div>
    <div><button>Registrar no diário</button></div>
  </form>`;
}

function bindReviewForm(itemId) {
  let rating = null;
  const starEl = document.getElementById("star-input");
  const paint = (value) => {
    starEl.innerHTML = [1, 2, 3, 4, 5].map((i) => {
      const fill = value >= i * 2 ? "full" : value === i * 2 - 1 ? "half" : "";
      return `<span data-i="${i}">★${fill ? `<span class="${fill}">★</span>` : ""}</span>`;
    }).join("");
  };
  paint(0);
  starEl.addEventListener("mousemove", (ev) => {
    const s = ev.target.closest("[data-i]"); if (!s) return;
    const half = ev.offsetX < s.getBoundingClientRect().width / 2;
    paint(Number(s.dataset.i) * 2 - (half ? 1 : 0));
  });
  starEl.addEventListener("mouseleave", () => paint(rating || 0));
  starEl.addEventListener("click", (ev) => {
    const s = ev.target.closest("[data-i]"); if (!s) return;
    const half = ev.offsetX < s.getBoundingClientRect().width / 2;
    rating = Number(s.dataset.i) * 2 - (half ? 1 : 0);
    paint(rating);
  });
  document.getElementById("clear-stars").onclick = () => { rating = null; paint(0); };

  document.getElementById("review-form").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const f = new FormData(ev.target);
    const body = f.get("body").trim();
    if (!rating && !body && !f.get("liked")) { document.getElementById("review-error").textContent = "Dê uma nota, curta ou escreva algo."; return; }
    try {
      await api(`/items/${itemId}/reviews`, { method: "POST", json: {
        rating, body: body || null, liked: !!f.get("liked"), consumedOn: f.get("consumedOn") || null } });
      itemPage(itemId);
    } catch (e) { showError(document.getElementById("review-error"), e); }
  });
}

async function diaryPage(name) {
  const entries = await api(`/users/${encodeURIComponent(name)}/diary`);
  app.innerHTML = `<h1>Diário de ${esc(name)}</h1>
    <div class="panel">${entries.length ? entries.map(({ review: r, item }) => `
      <div class="diary-row">
        <span class="muted">${esc(r.consumedOn || r.createdAt.slice(0, 10))}</span>
        <a href="#/item/${item.id}">${cover(item.imageUrl, "", isSquare(item.source))}</a>
        <div><a href="#/item/${item.id}"><strong>${esc(item.title)}</strong></a> <span class="muted">${item.year || ""}</span>
          ${r.body ? `<div class="muted">${esc(r.body.length > 140 ? r.body.slice(0, 140) + "…" : r.body)}</div>` : ""}</div>
        <div><span class="stars">${stars(r.rating)}</span> ${r.liked ? `<span class="heart">♥</span>` : ""}</div>
      </div>`).join("") : `<span class="muted">Nenhum registro ainda.</span>`}
    </div>`;
}

function newCategoryPage() {
  if (!session.user) { location.hash = "#/entrar"; return; }
  app.innerHTML = `<h1>Nova categoria</h1>
    <p class="muted">Crie uma categoria para avaliar qualquer coisa: vinhos, restaurantes, trilhas, cafés…</p>
    <form class="form" id="cat-form">
      <label>Nome <input type="text" name="name" maxlength="60" required></label>
      <label>Descrição <input type="text" name="description"></label>
      <div class="error" id="cat-error"></div>
      <div><button>Criar</button></div>
    </form>`;
  document.getElementById("cat-form").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const f = new FormData(ev.target);
    try {
      const c = await api("/categories", { method: "POST", json: { name: f.get("name"), description: f.get("description") || null } });
      location.hash = `#/c/${encodeURIComponent(c.slug)}/novo`;
    } catch (e) { showError(document.getElementById("cat-error"), e); }
  });
}

function newItemPage(slug) {
  if (!session.user) { location.hash = "#/entrar"; return; }
  app.innerHTML = `<a class="muted" href="#/c/${esc(slug)}">← voltar</a>
    <h1>Adicionar item</h1>
    <form class="form" id="item-form">
      <label>Nome <input type="text" name="title" maxlength="200" required></label>
      <label>Subtítulo (autor, artista, marca…) <input type="text" name="subtitle"></label>
      <label>Ano <input type="number" name="year" min="0" max="3000"></label>
      <label>Descrição <textarea name="description"></textarea></label>
      <label>Foto (JPEG, PNG, GIF ou WebP, até 5 MB) <input type="file" name="image" accept="image/*"></label>
      <div class="error" id="item-error"></div>
      <div><button>Salvar</button></div>
    </form>`;
  document.getElementById("item-form").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const button = ev.target.querySelector("button");
    button.disabled = true;
    try {
      const item = await api(`/categories/${encodeURIComponent(slug)}/items`, { method: "POST", form: new FormData(ev.target) });
      location.hash = `#/item/${item.id}`;
    } catch (e) { showError(document.getElementById("item-error"), e); button.disabled = false; }
  });
}

function loginPage() {
  app.innerHTML = `<h1>Entrar</h1>
    <form class="form" id="login-form">
      <label>Usuário <input type="text" name="username" autocomplete="username" required></label>
      <label>Senha <input type="password" name="password" autocomplete="current-password" required></label>
      <div class="error" id="login-error"></div>
      <div class="row"><button name="action" value="login">Entrar</button>
        <button class="secondary" name="action" value="register">Criar conta</button></div>
    </form>`;
  document.getElementById("login-form").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const f = new FormData(ev.target);
    const action = ev.submitter?.value === "register" ? "register" : "login";
    try {
      const s = await api(`/auth/${action}`, { method: "POST", json: { username: f.get("username").trim().toLowerCase(), password: f.get("password") } });
      session.save(s); renderNav(); location.hash = "#/";
    } catch (e) { showError(document.getElementById("login-error"), e); }
  });
}

window.addEventListener("hashchange", route);
renderNav();
route();
