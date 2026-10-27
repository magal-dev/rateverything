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

// --- icons & category styling ----------------------------------------------------

// Stroke icons (paths adapted from Lucide, ISC license).
const ICONS = {
  film: `<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M7 3v18M17 3v18M3 7.5h4M3 12h18M3 16.5h4M17 7.5h4M17 16.5h4"/>`,
  tv: `<rect width="20" height="15" x="2" y="7" rx="2"/><path d="m17 2-5 5-5-5"/>`,
  disc: `<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="2.5"/><path d="M6 12a6 6 0 0 1 6-6"/>`,
  gamepad: `<path d="M6 11h4M8 9v4M15 12h.01M18 10h.01"/><path d="M17.32 5H6.68a4 4 0 0 0-3.98 3.59C2.6 9.42 2 14.46 2 16a3 3 0 0 0 3 3c1 0 1.5-.5 2-1l1.41-1.41A2 2 0 0 1 9.83 16h4.34a2 2 0 0 1 1.41.59L17 18c.5.5 1 1 2 1a3 3 0 0 0 3-3c0-1.55-.6-6.58-.69-7.26A4 4 0 0 0 17.32 5z"/>`,
  book: `<path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/>`,
  sparkles: `<path d="m12 3-1.9 5.8a2 2 0 0 1-1.3 1.3L3 12l5.8 1.9a2 2 0 0 1 1.3 1.3L12 21l1.9-5.8a2 2 0 0 1 1.3-1.3L21 12l-5.8-1.9a2 2 0 0 1-1.3-1.3Z"/>`,
  plus: `<path d="M5 12h14M12 5v14"/>`,
  user: `<circle cx="12" cy="8" r="5"/><path d="M20 21a8 8 0 0 0-16 0"/>`,
  power: `<path d="M12 2v10"/><path d="M18.4 6.6a9 9 0 1 1-12.77.04"/>`,
  search: `<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>`,
  back: `<path d="m12 19-7-7 7-7M19 12H5"/>`,
  star: `<path d="m12 2 3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21l1.2-6.8-5-4.9 6.9-1z"/>`,
};
const icon = (name) =>
  `<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name]}</svg>`;

const PROVIDER_STYLE = {
  "tmdb-movie": { icon: "film", color: "#ff4d6d" },
  "tmdb-tv": { icon: "tv", color: "#8b5cf6" },
  musicbrainz: { icon: "disc", color: "#14b8a6" },
  rawg: { icon: "gamepad", color: "#3b82f6" },
  openlibrary: { icon: "book", color: "#f59e0b" },
};
const catStyle = (c) => PROVIDER_STYLE[c.provider] || { icon: "sparkles", color: "#ec4899" };
const badge = (c) => { const s = catStyle(c); return `<span class="badge-ico" style="--c:${s.color}">${icon(s.icon)}</span>`; };
const dot = (c) => { const s = catStyle(c); return `<span class="dot" style="--c:${s.color}">${icon(s.icon)}</span>`; };
const catSubtitle = (c) => c.description || (c.ownerId !== null ? "categoria da comunidade" : "");

// --- helpers --------------------------------------------------------------------

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

function stars(rating) {
  if (!rating) return "";
  return "★".repeat(Math.floor(rating / 2)) + (rating % 2 ? "½" : "");
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
const dateOf = (r) => r.consumedOn || r.createdAt.slice(0, 10);
const avatar = (name) => `<span class="avatar">${esc((name || "?")[0])}</span>`;

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
  const h = location.hash || "#/";
  const pill = (href, label, active, extra = false) =>
    `<a class="nav-pill ${active ? "active" : ""} ${extra ? "nav-extra" : ""}" href="${href}">${label}</a>`;
  const browsing = h === "#/" || h.startsWith("#/c/") || h.startsWith("#/item/");
  nav.innerHTML = `
    <div class="nav-links">
      ${pill("#/", "explorar", browsing)}
      ${u ? pill(`#/u/${encodeURIComponent(u.username)}`, "diário", h.startsWith("#/u/"), true) : ""}
      ${u ? pill("#/nova-categoria", "criar", h === "#/nova-categoria", true) : ""}
    </div>
    <div class="nav-actions">
      ${u
        ? `<a class="profile-btn" href="#/u/${encodeURIComponent(u.username)}" title="@${esc(u.username)} — meu diário">${avatar(u.username)}</a>
           <button class="round danger" id="logout" title="Sair">${icon("power")}</button>`
        : `<a class="btn" href="#/entrar">${icon("user")} entrar</a>`}
    </div>`;
  const logout = document.getElementById("logout");
  if (logout) logout.onclick = async () => {
    try { await api("/auth/logout", { method: "POST" }); } catch (_) { /* session may already be gone */ }
    session.clear(); location.hash = "#/"; renderNav();
  };
}

const routes = [
  [/^#?\/?$/, () => homePage()],
  [/^#\/c\/([^/]+)$/, (slug) => categoryPage(decodeURIComponent(slug))],
  [/^#\/c\/([^/]+)\/novo$/, (slug) => newItemPage(decodeURIComponent(slug))],
  [/^#\/item\/(\d+)$/, (id) => itemPage(Number(id))],
  [/^#\/u\/([^/]+)$/, (name) => diaryPage(decodeURIComponent(name))],
  [/^#\/nova-categoria$/, () => newCategoryPage()],
  [/^#\/entrar$/, () => loginPage()],
];

async function route() {
  renderNav();
  const hash = location.hash || "#/";
  for (const [re, handler] of routes) {
    const m = hash.match(re);
    if (m) {
      app.innerHTML = `<span class="loading">carregando…</span>`;
      try { await handler(...m.slice(1)); } catch (e) { app.innerHTML = `<div class="panel error">${esc(e.message)}</div>`; }
      window.scrollTo(0, 0);
      return;
    }
  }
  app.innerHTML = `<div class="panel"><h1>página não encontrada</h1></div>`;
}

// --- pages ----------------------------------------------------------------------

async function homePage() {
  const categories = await api("/categories");
  app.innerHTML = `
    <section class="home">
      <div class="menu">
        ${categories.map((c, i) => `
          <a class="menu-card" style="--i:${i}" href="#/c/${encodeURIComponent(c.slug)}">
            ${badge(c)}
            <span><span class="menu-title">${esc(c.name)}</span><span class="menu-sub">${esc(catSubtitle(c))}</span></span>
          </a>`).join("")}
        <a class="menu-pill" style="--i:${categories.length}" href="#/nova-categoria"><span class="box">${icon("plus")}</span>criar categoria</a>
      </div>
      <div class="hero">${orbit(categories)}</div>
    </section>`;
  startOrbit();
}

// Cartoon objects, one per kind of category, that orbit on the home page.
const INK = `stroke="#16112b" stroke-width="5" stroke-linejoin="round" stroke-linecap="round"`;
const ORBITERS = [
  { provider: "tmdb-movie", label: "Filmes", svg: `
    <rect x="16" y="50" width="88" height="56" rx="8" fill="#ff4d6d" ${INK}/>
    <rect x="16" y="50" width="88" height="14" fill="#fff" ${INK}/>
    <path d="M34 50l-8 14M54 50l-8 14M74 50l-8 14M94 50l-8 14" ${INK}/>
    <g transform="rotate(-16 18 48)"><rect x="16" y="32" width="88" height="16" rx="3" fill="#fff" ${INK}/>
      <path d="M36 32l-8 16M56 32l-8 16M76 32l-8 16M96 32l-8 16" ${INK}/></g>
    <circle cx="19" cy="49" r="5" fill="#16112b"/>` },
  { provider: "tmdb-tv", label: "Séries", svg: `
    <path d="M60 34 40 10M60 34 82 12" ${INK}/><circle cx="40" cy="10" r="5" fill="#ffc93c" ${INK}/><circle cx="82" cy="12" r="5" fill="#ffc93c" ${INK}/>
    <rect x="12" y="34" width="96" height="70" rx="16" fill="#8b5cf6" ${INK}/>
    <rect x="22" y="44" width="62" height="50" rx="10" fill="#9ff0ff" ${INK}/>
    <path d="M30 54q8-6 16 0" stroke="#fff" stroke-width="4" fill="none" stroke-linecap="round"/>
    <circle cx="96" cy="56" r="5" fill="#ffc93c" ${INK}/><circle cx="96" cy="78" r="5" fill="#ff6f91" ${INK}/>
    <path d="M32 104l-6 10M88 104l6 10" ${INK}/>` },
  { provider: "musicbrainz", label: "Álbuns", svg: `
    <circle cx="60" cy="60" r="48" fill="#1d1638" ${INK}/>
    <circle cx="60" cy="60" r="38" fill="none" stroke="#3d3470" stroke-width="2.5"/><circle cx="60" cy="60" r="29" fill="none" stroke="#3d3470" stroke-width="2.5"/>
    <circle cx="60" cy="60" r="17" fill="#14b8a6" ${INK}/><circle cx="60" cy="60" r="3.5" fill="#16112b"/>
    <path d="M32 36a36 36 0 0 1 22-12" stroke="#fff" stroke-width="4" fill="none" stroke-linecap="round" opacity=".7"/>` },
  { provider: "rawg", label: "Jogos", svg: `
    <path d="M32 38h56a24 24 0 0 1 24 24c0 20-6 38-19 38-9 0-13-11-22-11H49c-9 0-13 11-22 11-13 0-19-18-19-38a24 24 0 0 1 24-24z" fill="#3b82f6" ${INK}/>
    <path d="M30 56v20M20 66h20" stroke="#fff" stroke-width="7" stroke-linecap="round"/>
    <circle cx="84" cy="58" r="6" fill="#ffc93c" ${INK}/><circle cx="96" cy="72" r="6" fill="#ff6f91" ${INK}/>
    <path d="M52 50h16" stroke="#16112b" stroke-width="5" stroke-linecap="round"/>` },
  { provider: "openlibrary", label: "Livros", svg: `
    <g transform="rotate(-10 60 60)">
      <rect x="28" y="14" width="68" height="92" rx="6" fill="#fff" ${INK}/>
      <rect x="22" y="12" width="68" height="92" rx="6" fill="#f59e0b" ${INK}/>
      <rect x="22" y="12" width="14" height="92" rx="4" fill="#d97706" ${INK}/>
      <path d="M48 36h30M48 48h22" stroke="#fff" stroke-width="5" stroke-linecap="round"/>
    </g>` },
  { provider: null, label: "Crie sua categoria", svg: `
    <rect x="20" y="50" width="80" height="58" rx="6" fill="#ec4899" ${INK}/>
    <rect x="14" y="34" width="92" height="20" rx="6" fill="#f472b6" ${INK}/>
    <path d="M60 34v74" stroke="#ffc93c" stroke-width="10"/>
    <path d="M60 32c-10-18-30-14-24-4 4 6 16 6 24 4zM60 32c10-18 30-14 24-4-4 6-16 6-24 4z" fill="#ffc93c" ${INK}/>
    <text x="30" y="94" font-family="Fredoka, sans-serif" font-weight="700" font-size="30" fill="#fff" stroke="#16112b" stroke-width="4" paint-order="stroke">?</text>` },
];

function orbit(categories) {
  const hrefFor = (provider) => {
    if (!provider) return "#/nova-categoria";
    const c = categories.find((c) => c.provider === provider);
    return c ? `#/c/${encodeURIComponent(c.slug)}` : "#/";
  };
  return `<div class="orbit" id="orbit">
      <span class="orbit-core"></span>
      <span class="orbit-ring"></span>
      ${ORBITERS.map((o) => `<a class="orbiter" href="${hrefFor(o.provider)}" title="${esc(o.label)}">
        <svg viewBox="0 0 120 120" aria-hidden="true">${o.svg}</svg><span class="orbiter-label">${esc(o.label)}</span></a>`).join("")}
    </div>
    <span class="hero-caption">dê nota em tudo.</span>`;
}

// Moves the orbiters along a tilted ellipse; the ones "behind" shrink and dim.
function startOrbit() {
  const el = document.getElementById("orbit");
  if (!el) return;
  const items = [...el.querySelectorAll(".orbiter")];
  const ring = el.querySelector(".orbit-ring");
  const tilt = (-9 * Math.PI) / 180;
  let angle = 0;
  let paused = false;
  el.addEventListener("mouseenter", () => (paused = true));
  el.addEventListener("mouseleave", () => (paused = false));

  const place = () => {
    const w = el.clientWidth, h = el.clientHeight;
    const rx = w * 0.4, ry = h * 0.17, cx = w / 2, cy = h * 0.5;
    ring.style.width = `${rx * 2}px`;
    ring.style.height = `${ry * 2}px`;
    items.forEach((item, i) => {
      const a = angle + (i * 2 * Math.PI) / items.length;
      const dx = rx * Math.cos(a), dy = ry * Math.sin(a);
      const x = cx + dx * Math.cos(tilt) - dy * Math.sin(tilt);
      const y = cy + dx * Math.sin(tilt) + dy * Math.cos(tilt);
      const depth = (Math.sin(a) + 1) / 2; // 0 = behind, 1 = in front
      const wobble = Math.sin(a * 2) * 10;
      item.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%) scale(${0.55 + 0.55 * depth}) rotate(${wobble}deg)`;
      item.style.zIndex = String(Math.round(depth * 100));
      item.style.filter = `brightness(${0.7 + 0.3 * depth})`;
    });
  };

  if (matchMedia("(prefers-reduced-motion: reduce)").matches) { place(); return; }
  let last = performance.now();
  const frame = (now) => {
    if (!el.isConnected) return; // the page changed
    if (!paused) angle += ((now - last) / 1000) * 0.45;
    last = now;
    place();
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}

async function categoryPage(slug) {
  const categories = await api("/categories");
  const current = categories.find((c) => c.slug === slug);
  if (!current) throw new Error("Categoria não encontrada");
  const user = session.user;
  const canAdd = user && (current.ownerId === null || current.ownerId === user.id);

  app.innerHTML = `
    <div class="chips">${categories.map((c) =>
      `<a class="chip ${c.id === current.id ? "active" : ""}" href="#/c/${encodeURIComponent(c.slug)}">${dot(c)}${esc(c.name)}</a>`).join("")}
    </div>
    <div class="panel cat-head tilt-l">
      ${badge(current)}
      <div class="grow"><h1>${esc(current.name)}</h1><div class="muted">${esc(catSubtitle(current))}</div></div>
      ${canAdd ? `<a class="btn" href="#/c/${encodeURIComponent(current.slug)}/novo">${icon("plus")} adicionar item</a>` : ""}
    </div>
    <form class="searchbar" id="search">
      ${icon("search")}
      <input type="text" name="q" placeholder="buscar em ${esc(current.name.toLowerCase())}…" autofocus>
      <button class="btn">buscar</button>
    </form>
    <div class="panel">
      <div class="error" id="error" hidden></div>
      <h2 class="section-title" id="list-title">adicionados recentemente</h2>
      <div class="grid" id="results"></div>
    </div>`;

  const results = document.getElementById("results");
  const error = document.getElementById("error");
  const fail = (e) => { error.hidden = false; showError(error, e); };

  const showItems = (items) => {
    results.innerHTML = items.length ? "" : `<p class="muted">Nada por aqui ainda. Busque algo acima para começar.</p>`;
    for (const it of items) results.appendChild(card(it, () => (location.hash = `#/item/${it.id}`)));
  };
  showItems(await api(`/categories/${encodeURIComponent(current.slug)}/items`));

  document.getElementById("search").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const q = new FormData(ev.target).get("q").trim();
    if (!q) return;
    error.hidden = true;
    document.getElementById("list-title").textContent = `resultados para “${q}”`;
    results.innerHTML = `<p class="muted">Buscando…</p>`;
    try {
      const hits = await api(`/categories/${encodeURIComponent(current.slug)}/search?q=${encodeURIComponent(q)}`);
      results.innerHTML = hits.length ? "" : `<p class="muted">Nenhum resultado.</p>`;
      for (const hit of hits) results.appendChild(card(hit.item, () => openHit(current, hit, fail)));
    } catch (e) { results.innerHTML = ""; fail(e); }
  });
}

async function openHit(category, hit, fail) {
  if (hit.itemId) { location.hash = `#/item/${hit.itemId}`; return; }
  if (!session.user) { location.hash = "#/entrar"; return; }
  try {
    const item = await api(`/categories/${encodeURIComponent(category.slug)}/import`, { method: "POST", json: hit.item });
    location.hash = `#/item/${item.id}`;
  } catch (e) { fail(e); }
}

async function itemPage(id) {
  const d = await api(`/items/${id}`);
  const { item, category } = d;
  const user = session.user;
  const avg = d.averageRating ? (d.averageRating / 2).toFixed(1) : null;
  const catStyleVars = catStyle(category);

  app.innerHTML = `
    <div class="panel">
      <div class="detail">
        <div class="poster">${cover(item.imageUrl, item.title, isSquare(item.source))}</div>
        <div>
          <a class="crumb" href="#/c/${encodeURIComponent(category.slug)}"><span class="dot" style="--c:${catStyleVars.color}">${icon(catStyleVars.icon)}</span>${esc(category.name)}</a>
          <h1>${esc(item.title)} ${item.year ? `<span class="year">${item.year}</span>` : ""}</h1>
          ${item.subtitle ? `<div class="muted">${esc(item.subtitle)}</div>` : ""}
          <div class="score">${avg
            ? `<span class="big">★ ${avg}</span> de 5 · ${d.ratingCount} nota(s)`
            : `<span class="big">★ –</span> sem notas ainda`}</div>
          ${item.description ? `<p>${esc(item.description)}</p>` : ""}
        </div>
      </div>
    </div>
    ${user ? reviewForm() : `<div class="panel tilt-r"><a href="#/entrar" class="btn">entre para avaliar</a></div>`}
    <div class="panel">
      <h2 class="section-title">reviews</h2>
      <div id="reviews">${d.reviews.length ? d.reviews.map(reviewHtml).join("") : `<span class="muted">Ninguém comentou ainda.</span>`}</div>
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
    ${avatar(r.username)}
    <div>
      <div class="review-meta">
        <a href="#/u/${encodeURIComponent(r.username)}"><strong>${esc(r.username)}</strong></a>
        <span class="stars">${stars(r.rating)}</span>
        ${r.liked ? `<span class="heart">♥</span>` : ""}
        <span class="muted">${esc(dateOf(r))}</span>
        ${mine ? `<button class="link" data-delete="${r.id}">apagar</button>` : ""}
      </div>
      ${r.body ? `<div>${esc(r.body)}</div>` : ""}
    </div>
  </div>`;
}

function reviewForm() {
  const today = new Date().toISOString().slice(0, 10);
  return `<form class="panel form tilt-r" id="review-form">
    <h2 class="section-title" style="margin:0">registrar no diário</h2>
    <div class="review-top">
      <div class="star-input" id="star-input"></div><button type="button" class="link" id="clear-stars">limpar</button>
      <label class="inline" style="margin-left:auto"><input type="checkbox" name="liked"> <span class="heart">♥</span> curti</label>
    </div>
    <label>Quando? <input type="date" name="consumedOn" value="${today}"></label>
    <label>Review (opcional) <textarea name="body" placeholder="O que você achou?"></textarea></label>
    <div class="error" id="review-error"></div>
    <div><button class="btn">salvar</button></div>
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
  const valueAt = (ev) => {
    const s = ev.target.closest("[data-i]");
    if (!s) return null;
    const half = ev.clientX - s.getBoundingClientRect().left < s.getBoundingClientRect().width / 2;
    return Number(s.dataset.i) * 2 - (half ? 1 : 0);
  };
  paint(0);
  starEl.addEventListener("mousemove", (ev) => { const v = valueAt(ev); if (v) paint(v); });
  starEl.addEventListener("mouseleave", () => paint(rating || 0));
  starEl.addEventListener("click", (ev) => { const v = valueAt(ev); if (v) { rating = v; paint(rating); } });
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
  app.innerHTML = `
    <div class="panel profile-head tilt-l">${avatar(name)}<div><h1>${esc(name)}</h1><div class="muted">${entries.length} registro(s) no diário</div></div></div>
    <div class="panel">${entries.length ? entries.map(({ review: r, item }) => `
      <div class="diary-row">
        <span class="date-tag">${esc(dateOf(r))}</span>
        <a href="#/item/${item.id}">${cover(item.imageUrl, "", isSquare(item.source))}</a>
        <div><a href="#/item/${item.id}"><strong>${esc(item.title)}</strong></a> <span class="muted">${item.year || ""}</span>
          ${r.body ? `<div class="muted">${esc(r.body.length > 140 ? r.body.slice(0, 140) + "…" : r.body)}</div>` : ""}</div>
        <div><span class="stars">${stars(r.rating)}</span> ${r.liked ? `<span class="heart">♥</span>` : ""}</div>
      </div>`).join("") : `<span class="muted">Nenhum registro ainda.</span>`}
    </div>`;
}

function newCategoryPage() {
  if (!session.user) { location.hash = "#/entrar"; return; }
  app.innerHTML = `<div class="narrow"><form class="panel form tilt-l" id="cat-form">
      <h1>nova categoria</h1>
      <p class="muted" style="margin:0">Avalie qualquer coisa: vinhos, restaurantes, trilhas, cafés…</p>
      <label>Nome <input type="text" name="name" maxlength="60" required></label>
      <label>Descrição <input type="text" name="description"></label>
      <div class="error" id="cat-error"></div>
      <div><button class="btn">${icon("plus")} criar</button></div>
    </form></div>`;
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
  app.innerHTML = `<div class="narrow"><form class="panel form tilt-r" id="item-form">
      <a class="crumb" href="#/c/${encodeURIComponent(slug)}">${icon("back")} voltar</a>
      <h1>adicionar item</h1>
      <label>Nome <input type="text" name="title" maxlength="200" required></label>
      <label>Subtítulo (autor, artista, marca…) <input type="text" name="subtitle"></label>
      <label>Ano <input type="number" name="year" min="0" max="3000"></label>
      <label>Descrição <textarea name="description"></textarea></label>
      <label>Foto (JPEG, PNG, GIF ou WebP, até 5 MB) <input type="file" name="image" accept="image/*"></label>
      <div class="error" id="item-error"></div>
      <div><button class="btn">salvar</button></div>
    </form></div>`;
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
  app.innerHTML = `<div class="narrow"><form class="panel form tilt-l" id="login-form">
      <h1>entrar</h1>
      <label>Usuário <input type="text" name="username" autocomplete="username" required></label>
      <label>Senha <input type="password" name="password" autocomplete="current-password" required></label>
      <div class="error" id="login-error"></div>
      <div class="review-top"><button class="btn" name="action" value="login">entrar</button>
        <button class="btn secondary" name="action" value="register">criar conta</button></div>
    </form></div>`;
  document.getElementById("login-form").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const f = new FormData(ev.target);
    const action = ev.submitter?.value === "register" ? "register" : "login";
    try {
      const s = await api(`/auth/${action}`, { method: "POST", json: { username: f.get("username").trim().toLowerCase(), password: f.get("password") } });
      session.save(s); location.hash = "#/";
    } catch (e) { showError(document.getElementById("login-error"), e); }
  });
}

window.addEventListener("hashchange", route);
route();
// Drop a stored session the server no longer accepts (api() clears it on 401).
if (session.token) api("/me").catch(() => {});
