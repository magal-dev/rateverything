"use strict";

const page = document.getElementById("app");
const navBar = document.getElementById("nav");
const prefersReducedMotion = matchMedia("(prefers-reduced-motion: reduce)");

const MIN_DIARY_DATE = "1900-01-01";
const MAX_ITEM_YEAR = new Date().getFullYear() + 5;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const PAGE_FADE_OUT_MS = 140;
const LOADING_INDICATOR_DELAY_MS = 250;
const DIARY_EXCERPT_LENGTH = 140;

const session = {
  get token() { return localStorage.getItem("token"); },
  get user() {
    const storedUser = localStorage.getItem("user");
    return storedUser ? JSON.parse(storedUser) : null;
  },
  save(newSession) {
    localStorage.setItem("token", newSession.token);
    localStorage.setItem("user", JSON.stringify(newSession.user));
  },
  clear() {
    localStorage.removeItem("token");
    localStorage.removeItem("user");
  },
};

const UNREACHABLE_SERVER_STATUS = 0;

class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }

  get retryable() {
    return this.status === UNREACHABLE_SERVER_STATUS || this.status >= 500;
  }
}

async function api(path, { method = "GET", json, form } = {}) {
  const headers = {};
  if (session.token) headers.Authorization = "Bearer " + session.token;
  let body;
  if (json !== undefined) {
    headers["Content-Type"] = "application/json";
    body = JSON.stringify(json);
  }
  if (form) body = form;

  let response;
  try {
    response = await fetch("/api" + path, { method, headers, body });
  } catch (_) {
    throw new ApiError("Não foi possível falar com o servidor. Confira sua conexão e tente novamente.", UNREACHABLE_SERVER_STATUS);
  }

  const sessionWasRejected = response.status === 401 && session.token && !path.startsWith("/auth");
  if (sessionWasRejected) {
    session.clear();
    renderNavBar();
  }
  if (!response.ok) {
    const responseText = await response.text().catch(() => "");
    throw new ApiError(friendlyErrorMessage(response.status, responseText), response.status);
  }
  return response.status === 204 ? null : response.json();
}

function friendlyErrorMessage(status, responseText) {
  if (isReadableServerMessage(responseText)) return responseText;
  if (status === 413) return "Arquivo grande demais (máximo 5 MB).";
  if (status >= 500) return "O servidor teve um problema. Tente novamente em instantes.";
  if (status === 404) return "Não encontrado.";
  return "Dados inválidos. Confira o formulário e tente novamente.";
}

function isReadableServerMessage(text) {
  const looksLikeHtmlPage = text.startsWith("<");
  const looksLikeJsonParserError = text.startsWith("Error in $");
  return text && text.length < 300 && !looksLikeHtmlPage && !looksLikeJsonParserError;
}

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

const iconSvg = (name) =>
  `<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name]}</svg>`;

const PROVIDER_STYLES = {
  "tmdb-movie": { icon: "film", color: "#ff4d6d" },
  "tmdb-tv": { icon: "tv", color: "#8b5cf6" },
  musicbrainz: { icon: "disc", color: "#14b8a6" },
  rawg: { icon: "gamepad", color: "#3b82f6" },
  openlibrary: { icon: "book", color: "#f59e0b" },
};
const CUSTOM_CATEGORY_STYLE = { icon: "sparkles", color: "#ec4899" };

const categoryStyle = (category) => PROVIDER_STYLES[category.provider] || CUSTOM_CATEGORY_STYLE;

function categoryBadge(category) {
  const style = categoryStyle(category);
  return `<span class="badge-ico" style="--c:${style.color}">${iconSvg(style.icon)}</span>`;
}

function categoryDot(category) {
  const style = categoryStyle(category);
  return `<span class="dot" style="--c:${style.color}">${iconSvg(style.icon)}</span>`;
}

const isCommunityCategory = (category) => category.ownerId !== null;
const categorySubtitle = (category) =>
  category.description || (isCommunityCategory(category) ? "categoria da comunidade" : "");

const categoryHref = (slug) => `#/c/${encodeURIComponent(slug)}`;
const newItemHref = (slug) => `${categoryHref(slug)}/novo`;
const itemHref = (itemId) => `#/item/${itemId}`;
const diaryHref = (username) => `#/u/${encodeURIComponent(username)}`;
const goTo = (hash) => { location.hash = hash; };

const HTML_ESCAPES = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (character) => HTML_ESCAPES[character]);

function starsText(rating) {
  if (!rating) return "";
  const fullStars = Math.floor(rating / 2);
  const hasHalfStar = rating % 2 === 1;
  return "★".repeat(fullStars) + (hasHalfStar ? "½" : "");
}

function coverHtml(imageUrl, title, isSquare) {
  const classes = "cover" + (isSquare ? " square" : "");
  if (!imageUrl) return `<div class="${classes} cover-fallback">${escapeHtml(title)}</div>`;
  return `<img class="${classes}" src="${escapeHtml(imageUrl)}" alt="${escapeHtml(title)}" loading="lazy" onerror="replaceBrokenCover(this)">`;
}

window.replaceBrokenCover = (brokenImage) => {
  const fallback = document.createElement("div");
  fallback.className = brokenImage.className + " cover-fallback";
  fallback.textContent = brokenImage.alt;
  brokenImage.replaceWith(fallback);
};

const hasSquareCover = (source) => source === "musicbrainz";
const reviewDate = (review) => review.consumedOn || review.createdAt.slice(0, 10);

const avatarHtml = (username, avatarUrl) => avatarUrl
  ? `<img class="avatar" src="${escapeHtml(avatarUrl)}" alt="">`
  : `<span class="avatar">${escapeHtml((username || "?")[0])}</span>`;

function itemCard({ title, subtitle, year, imageUrl, source }, onClick, index = 0) {
  const card = document.createElement("div");
  card.className = "card";
  card.style.setProperty("--i", index);
  card.innerHTML = `${coverHtml(imageUrl, title, hasSquareCover(source))}
    <div class="card-title">${escapeHtml(title)}</div>
    <div class="card-sub">${escapeHtml([subtitle, year].filter(Boolean).join(" · "))}</div>`;
  card.addEventListener("click", onClick);
  return card;
}

function showError(target, error, retry) {
  target.textContent = error.message || String(error);
  if (retry && error.retryable) target.append(" ", retryButton(target, retry));
}

function retryButton(errorTarget, retry) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "btn secondary retry";
  button.textContent = "tentar novamente";
  button.onclick = () => {
    errorTarget.textContent = "";
    retry();
  };
  return button;
}

function todayInLocalTimeZone() {
  const now = new Date();
  const twoDigits = (number) => String(number).padStart(2, "0");
  return `${now.getFullYear()}-${twoDigits(now.getMonth() + 1)}-${twoDigits(now.getDate())}`;
}

const formatDateForPeople = (isoDate) => isoDate.split("-").reverse().join("/");

function renderNavBar() {
  const user = session.user;
  const hash = location.hash || "#/";
  const isBrowsing = hash === "#/" || hash.startsWith("#/c/") || hash.startsWith("#/item/");
  const navPill = (href, label, isActive, hideOnSmallScreens = false) =>
    `<a class="nav-pill ${isActive ? "active" : ""} ${hideOnSmallScreens ? "nav-extra" : ""}" href="${href}">${label}</a>`;

  navBar.innerHTML = `
    <div class="nav-links">
      ${navPill("#/", "explorar", isBrowsing)}
      ${user ? navPill(diaryHref(user.username), "diário", hash.startsWith("#/u/"), true) : ""}
      ${user ? navPill("#/nova-categoria", "criar", hash === "#/nova-categoria", true) : ""}
    </div>
    <div class="nav-actions">
      ${user ? loggedInActionsHtml(user) : loggedOutActionsHtml()}
    </div>`;

  const logoutButton = document.getElementById("logout");
  if (logoutButton) logoutButton.onclick = logOut;
}

const loggedInActionsHtml = (user) =>
  `<a class="profile-btn" href="${diaryHref(user.username)}" title="@${escapeHtml(user.username)} — meu diário">${avatarHtml(user.username, user.avatarUrl)}</a>
           <button class="round danger" id="logout" title="Sair">${iconSvg("power")}</button>`;

const loggedOutActionsHtml = () =>
  `<a class="btn secondary" href="#/entrar">entrar</a>
           <a class="btn nav-extra" href="#/criar-conta">${iconSvg("user")} criar conta</a>`;

async function logOut() {
  try {
    await api("/auth/logout", { method: "POST" });
  } catch (_) {}
  session.clear();
  goTo("#/");
  renderNavBar();
}

const routes = [
  [/^#?\/?$/, () => homePage()],
  [/^#\/c\/([^/]+)$/, (slug) => categoryPage(decodeURIComponent(slug))],
  [/^#\/c\/([^/]+)\/novo$/, (slug) => newItemPage(decodeURIComponent(slug))],
  [/^#\/item\/(\d+)$/, (itemId) => itemPage(Number(itemId))],
  [/^#\/u\/([^/]+)$/, (username) => diaryPage(decodeURIComponent(username))],
  [/^#\/nova-categoria$/, () => newCategoryPage()],
  [/^#\/entrar$/, () => authPage("login")],
  [/^#\/criar-conta$/, () => authPage("register")],
];

function findRoute(hash) {
  for (const [pattern, renderPage] of routes) {
    const match = hash.match(pattern);
    if (match) return () => renderPage(...match.slice(1));
  }
  return null;
}

const NOT_FOUND_PAGE_HTML =
  `<div class="panel"><h1>página não encontrada</h1><p><a class="btn" href="#/">voltar ao início</a></p></div>`;
const ERROR_PAGE_HTML =
  `<div class="panel"><h1>ops!</h1><p class="error" id="page-error"></p><a class="btn secondary" href="#/">voltar ao início</a></div>`;

let latestNavigationId = 0;

async function renderCurrentRoute() {
  const navigationId = ++latestNavigationId;
  const isStillCurrent = () => navigationId === latestNavigationId;
  renderNavBar();
  const renderMatchedPage = findRoute(location.hash || "#/");

  if (page.childElementCount && !prefersReducedMotion.matches) {
    await fadeOutCurrentPage();
    if (!isStillCurrent()) return;
  }
  const loadingIndicatorTimer = setTimeout(() => {
    if (isStillCurrent() && !page.childElementCount) page.innerHTML = `<span class="loading">carregando…</span>`;
  }, LOADING_INDICATOR_DELAY_MS);
  page.classList.remove("page-out");
  page.innerHTML = "";

  try {
    if (renderMatchedPage) await renderMatchedPage();
    else page.innerHTML = NOT_FOUND_PAGE_HTML;
  } catch (error) {
    if (!isStillCurrent()) return;
    page.innerHTML = ERROR_PAGE_HTML;
    showError(document.getElementById("page-error"), error, renderCurrentRoute);
  } finally {
    clearTimeout(loadingIndicatorTimer);
  }
  if (!isStillCurrent()) return;
  window.scrollTo(0, 0);
  playPageEntrance();
}

async function fadeOutCurrentPage() {
  page.classList.remove("page-in");
  page.classList.add("page-out");
  await new Promise((resolve) => setTimeout(resolve, PAGE_FADE_OUT_MS));
}

function playPageEntrance() {
  page.classList.remove("page-in");
  void page.offsetWidth;
  page.classList.add("page-in");
}

async function homePage() {
  const categories = await api("/categories");
  page.innerHTML = `
    <section class="home">
      <div>
        <h1 class="menu-head">o que vai ser hoje?<strong>escolha uma <span>categoria</span></strong></h1>
        <div class="menu">
          ${categories.map(categoryMenuCardHtml).join("")}
          <a class="menu-pill" style="--i:${categories.length}" href="#/nova-categoria"><span class="box">${iconSvg("plus")}</span>criar categoria</a>
        </div>
      </div>
      <div class="hero">${orbitHtml(categories)}</div>
    </section>`;
  startOrbitAnimation();
}

const categoryMenuCardHtml = (category, index) => `
            <a class="menu-card" style="--i:${index}" href="${categoryHref(category.slug)}">
              ${categoryBadge(category)}
              <span><span class="menu-title">${escapeHtml(category.name)}</span><span class="menu-sub">${escapeHtml(categorySubtitle(category))}</span></span>
            </a>`;

const INK_STROKE = `stroke="#16112b" stroke-width="5" stroke-linejoin="round" stroke-linecap="round"`;
const ORBITERS = [
  { provider: "tmdb-movie", label: "Filmes", svg: `
    <rect x="16" y="50" width="88" height="56" rx="8" fill="#ff4d6d" ${INK_STROKE}/>
    <rect x="16" y="50" width="88" height="14" fill="#fff" ${INK_STROKE}/>
    <path d="M34 50l-8 14M54 50l-8 14M74 50l-8 14M94 50l-8 14" ${INK_STROKE}/>
    <g transform="rotate(-16 18 48)"><rect x="16" y="32" width="88" height="16" rx="3" fill="#fff" ${INK_STROKE}/>
      <path d="M36 32l-8 16M56 32l-8 16M76 32l-8 16M96 32l-8 16" ${INK_STROKE}/></g>
    <circle cx="19" cy="49" r="5" fill="#16112b"/>` },
  { provider: "tmdb-tv", label: "Séries", svg: `
    <path d="M60 34 40 10M60 34 82 12" ${INK_STROKE}/><circle cx="40" cy="10" r="5" fill="#ffc93c" ${INK_STROKE}/><circle cx="82" cy="12" r="5" fill="#ffc93c" ${INK_STROKE}/>
    <rect x="12" y="34" width="96" height="70" rx="16" fill="#8b5cf6" ${INK_STROKE}/>
    <rect x="22" y="44" width="62" height="50" rx="10" fill="#9ff0ff" ${INK_STROKE}/>
    <path d="M30 54q8-6 16 0" stroke="#fff" stroke-width="4" fill="none" stroke-linecap="round"/>
    <circle cx="96" cy="56" r="5" fill="#ffc93c" ${INK_STROKE}/><circle cx="96" cy="78" r="5" fill="#ff6f91" ${INK_STROKE}/>
    <path d="M32 104l-6 10M88 104l6 10" ${INK_STROKE}/>` },
  { provider: "musicbrainz", label: "Álbuns", svg: `
    <circle cx="60" cy="60" r="48" fill="#1d1638" ${INK_STROKE}/>
    <circle cx="60" cy="60" r="38" fill="none" stroke="#3d3470" stroke-width="2.5"/><circle cx="60" cy="60" r="29" fill="none" stroke="#3d3470" stroke-width="2.5"/>
    <circle cx="60" cy="60" r="17" fill="#14b8a6" ${INK_STROKE}/><circle cx="60" cy="60" r="3.5" fill="#16112b"/>
    <path d="M32 36a36 36 0 0 1 22-12" stroke="#fff" stroke-width="4" fill="none" stroke-linecap="round" opacity=".7"/>` },
  { provider: "rawg", label: "Jogos", svg: `
    <path d="M32 38h56a24 24 0 0 1 24 24c0 20-6 38-19 38-9 0-13-11-22-11H49c-9 0-13 11-22 11-13 0-19-18-19-38a24 24 0 0 1 24-24z" fill="#3b82f6" ${INK_STROKE}/>
    <path d="M30 56v20M20 66h20" stroke="#fff" stroke-width="7" stroke-linecap="round"/>
    <circle cx="84" cy="58" r="6" fill="#ffc93c" ${INK_STROKE}/><circle cx="96" cy="72" r="6" fill="#ff6f91" ${INK_STROKE}/>
    <path d="M52 50h16" stroke="#16112b" stroke-width="5" stroke-linecap="round"/>` },
  { provider: "openlibrary", label: "Livros", svg: `
    <g transform="rotate(-10 60 60)">
      <rect x="28" y="14" width="68" height="92" rx="6" fill="#fff" ${INK_STROKE}/>
      <rect x="22" y="12" width="68" height="92" rx="6" fill="#f59e0b" ${INK_STROKE}/>
      <rect x="22" y="12" width="14" height="92" rx="4" fill="#d97706" ${INK_STROKE}/>
      <path d="M48 36h30M48 48h22" stroke="#fff" stroke-width="5" stroke-linecap="round"/>
    </g>` },
  { provider: null, label: "Crie sua categoria", svg: `
    <rect x="20" y="50" width="80" height="58" rx="6" fill="#ec4899" ${INK_STROKE}/>
    <rect x="14" y="34" width="92" height="20" rx="6" fill="#f472b6" ${INK_STROKE}/>
    <path d="M60 34v74" stroke="#ffc93c" stroke-width="10"/>
    <path d="M60 32c-10-18-30-14-24-4 4 6 16 6 24 4zM60 32c10-18 30-14 24-4-4 6-16 6-24 4z" fill="#ffc93c" ${INK_STROKE}/>
    <text x="30" y="94" font-family="Fredoka, sans-serif" font-weight="700" font-size="30" fill="#fff" stroke="#16112b" stroke-width="4" paint-order="stroke">?</text>` },
];

function orbitHtml(categories) {
  const orbiterHref = (provider) => {
    if (!provider) return "#/nova-categoria";
    const category = categories.find((candidate) => candidate.provider === provider);
    return category ? categoryHref(category.slug) : "#/";
  };
  return `<div class="orbit" id="orbit">
      <span class="orbit-core"></span>
      <span class="orbit-ring"></span>
      ${ORBITERS.map((orbiter) => `<a class="orbiter" href="${orbiterHref(orbiter.provider)}" title="${escapeHtml(orbiter.label)}">
        <svg viewBox="0 0 120 120" aria-hidden="true">${orbiter.svg}</svg><span class="orbiter-label">${escapeHtml(orbiter.label)}</span></a>`).join("")}
    </div>
    <span class="hero-caption">do blockbuster ao pastel da feira.</span>`;
}

const ORBIT_TILT_RADIANS = (-9 * Math.PI) / 180;
const ORBIT_RADIANS_PER_SECOND = 0.45;

function startOrbitAnimation() {
  const orbit = document.getElementById("orbit");
  if (!orbit) return;
  const orbiters = [...orbit.querySelectorAll(".orbiter")];
  const ring = orbit.querySelector(".orbit-ring");
  let rotationAngle = 0;
  let isPaused = false;
  orbit.addEventListener("mouseenter", () => (isPaused = true));
  orbit.addEventListener("mouseleave", () => (isPaused = false));

  const positionOrbiters = () => {
    const width = orbit.clientWidth;
    const height = orbit.clientHeight;
    const radiusX = width * 0.4;
    const radiusY = height * 0.17;
    const centerX = width / 2;
    const centerY = height * 0.5;
    ring.style.width = `${radiusX * 2}px`;
    ring.style.height = `${radiusY * 2}px`;
    orbiters.forEach((orbiter, index) => {
      const angle = rotationAngle + (index * 2 * Math.PI) / orbiters.length;
      const offsetX = radiusX * Math.cos(angle);
      const offsetY = radiusY * Math.sin(angle);
      const x = centerX + offsetX * Math.cos(ORBIT_TILT_RADIANS) - offsetY * Math.sin(ORBIT_TILT_RADIANS);
      const y = centerY + offsetX * Math.sin(ORBIT_TILT_RADIANS) + offsetY * Math.cos(ORBIT_TILT_RADIANS);
      const closenessToViewer = (Math.sin(angle) + 1) / 2;
      const wobbleDegrees = Math.sin(angle * 2) * 10;
      orbiter.style.transform =
        `translate(${x}px, ${y}px) translate(-50%, -50%) scale(${0.55 + 0.55 * closenessToViewer}) rotate(${wobbleDegrees}deg)`;
      orbiter.style.zIndex = String(Math.round(closenessToViewer * 100));
      orbiter.style.filter = `brightness(${0.7 + 0.3 * closenessToViewer})`;
    });
  };

  if (prefersReducedMotion.matches) {
    positionOrbiters();
    return;
  }
  let previousFrameTime = performance.now();
  const animateFrame = (frameTime) => {
    const orbitLeftThePage = !orbit.isConnected;
    if (orbitLeftThePage) return;
    if (!isPaused) rotationAngle += ((frameTime - previousFrameTime) / 1000) * ORBIT_RADIANS_PER_SECOND;
    previousFrameTime = frameTime;
    positionOrbiters();
    requestAnimationFrame(animateFrame);
  };
  requestAnimationFrame(animateFrame);
}

async function categoryPage(slug) {
  const categories = await api("/categories");
  const category = categories.find((candidate) => candidate.slug === slug);
  if (!category) throw new Error("Categoria não encontrada");
  const user = session.user;
  const canAddItems = user && (category.ownerId === null || category.ownerId === user.id);

  page.innerHTML = `
    <div class="chips">${categories.map((other) =>
      `<a class="chip ${other.id === category.id ? "active" : ""}" href="${categoryHref(other.slug)}">${categoryDot(other)}${escapeHtml(other.name)}</a>`).join("")}
    </div>
    <div class="panel cat-head tilt-l">
      ${categoryBadge(category)}
      <div class="grow"><h1>${escapeHtml(category.name)}</h1><div class="muted">${escapeHtml(categorySubtitle(category))}</div></div>
      ${canAddItems ? `<a class="btn" href="${newItemHref(category.slug)}">${iconSvg("plus")} adicionar item</a>` : ""}
    </div>
    <form class="searchbar" id="search">
      ${iconSvg("search")}
      <input type="text" name="q" placeholder="buscar em ${escapeHtml(category.name.toLowerCase())}…" autofocus>
      <button class="btn">buscar</button>
    </form>
    <div class="panel">
      <div class="error" id="error" hidden></div>
      <h2 class="section-title" id="list-title">adicionados recentemente</h2>
      <div class="grid" id="results"></div>
    </div>`;

  const results = document.getElementById("results");
  const errorBox = document.getElementById("error");
  const showSearchError = (error, retry) => {
    errorBox.hidden = false;
    showError(errorBox, error, retry);
  };

  const showRecentItems = (items) => {
    results.innerHTML = items.length ? "" : `<p class="muted">Nada por aqui ainda. Busque algo acima para começar.</p>`;
    items.forEach((item, index) => results.appendChild(itemCard(item, () => goTo(itemHref(item.id)), index)));
  };
  showRecentItems(await api(`/categories/${encodeURIComponent(category.slug)}/items`));

  const search = async (query) => {
    errorBox.hidden = true;
    document.getElementById("list-title").textContent = `resultados para “${query}”`;
    results.innerHTML = `<p class="muted searching">Buscando…</p>`;
    try {
      const hits = await api(`/categories/${encodeURIComponent(category.slug)}/search?q=${encodeURIComponent(query)}`);
      results.innerHTML = hits.length ? "" : `<p class="muted">Nenhum resultado.</p>`;
      hits.forEach((hit, index) =>
        results.appendChild(itemCard(hit.item, () => openSearchHit(category, hit, showSearchError), index)));
    } catch (error) {
      results.innerHTML = "";
      showSearchError(error, () => search(query));
    }
  };
  document.getElementById("search").addEventListener("submit", (event) => {
    event.preventDefault();
    const query = new FormData(event.target).get("q").trim();
    if (query) search(query);
  });
}

async function openSearchHit(category, hit, showSearchError) {
  if (hit.itemId) {
    goTo(itemHref(hit.itemId));
    return;
  }
  if (!session.user) {
    goTo("#/entrar");
    return;
  }
  try {
    const importedItem = await api(`/categories/${encodeURIComponent(category.slug)}/import`, { method: "POST", json: hit.item });
    goTo(itemHref(importedItem.id));
  } catch (error) {
    showSearchError(error, () => openSearchHit(category, hit, showSearchError));
  }
}

async function itemPage(itemId) {
  const detail = await api(`/items/${itemId}`);
  const { item, category } = detail;
  const user = session.user;
  const averageStars = detail.averageRating ? (detail.averageRating / 2).toFixed(1) : null;

  page.innerHTML = `
    <div class="panel">
      <div class="detail">
        <div class="poster">${coverHtml(item.imageUrl, item.title, hasSquareCover(item.source))}</div>
        <div>
          <a class="crumb" href="${categoryHref(category.slug)}">${categoryDot(category)}${escapeHtml(category.name)}</a>
          <h1>${escapeHtml(item.title)} ${item.year ? `<span class="year">${item.year}</span>` : ""}</h1>
          ${item.subtitle ? `<div class="muted">${escapeHtml(item.subtitle)}</div>` : ""}
          <div class="score">${averageStars
            ? `<span class="big">★ ${averageStars}</span> de 5 · ${detail.ratingCount} nota(s)`
            : `<span class="big">★ –</span> sem notas ainda`}</div>
          ${item.description ? `<p>${escapeHtml(item.description)}</p>` : ""}
        </div>
      </div>
    </div>
    ${user ? reviewFormHtml() : `<div class="panel tilt-r"><a href="#/entrar" class="btn">entre para avaliar</a></div>`}
    <div class="panel">
      <h2 class="section-title">reviews</h2>
      <div id="reviews">${detail.reviews.length ? detail.reviews.map(reviewHtml).join("") : `<span class="muted">Ninguém comentou ainda.</span>`}</div>
    </div>`;

  if (user) setUpReviewForm(itemId);
  page.querySelectorAll("[data-delete]").forEach((deleteButton) => deleteButton.addEventListener("click", async () => {
    if (!confirm("Apagar essa review?")) return;
    await api(`/reviews/${deleteButton.dataset.delete}`, { method: "DELETE" });
    itemPage(itemId);
  }));
}

function reviewHtml(review) {
  const isMine = session.user && session.user.id === review.userId;
  return `<div class="review">
    ${avatarHtml(review.username, review.avatarUrl)}
    <div>
      <div class="review-meta">
        <a href="${diaryHref(review.username)}"><strong>${escapeHtml(review.username)}</strong></a>
        <span class="stars">${starsText(review.rating)}</span>
        ${review.liked ? `<span class="heart">♥</span>` : ""}
        <span class="muted">${escapeHtml(reviewDate(review))}</span>
        ${isMine ? `<button class="link" data-delete="${review.id}">apagar</button>` : ""}
      </div>
      ${review.body ? `<div>${escapeHtml(review.body)}</div>` : ""}
    </div>
  </div>`;
}

function reviewFormHtml() {
  const today = todayInLocalTimeZone();
  return `<form class="panel form tilt-r" id="review-form" novalidate>
    <h2 class="section-title" style="margin:0">registrar no diário</h2>
    <div class="review-top">
      <div class="star-input" id="star-input"></div><button type="button" class="link" id="clear-stars">limpar</button>
      <label class="inline" style="margin-left:auto"><input type="checkbox" name="liked"> <span class="heart">♥</span> curti</label>
    </div>
    <label>Quando? <input type="date" name="consumedOn" value="${today}" min="${MIN_DIARY_DATE}" max="${today}"></label>
    <label>Review (opcional) <textarea name="body" placeholder="O que você achou?"></textarea></label>
    <div class="error" id="review-error"></div>
    <div><button class="btn" id="review-save">salvar</button></div>
  </form>`;
}

function setUpReviewForm(itemId) {
  const getRating = setUpStarInput(document.getElementById("star-input"), document.getElementById("clear-stars"));
  const form = document.getElementById("review-form");
  const errorBox = document.getElementById("review-error");

  const saveReview = async () => {
    const formData = new FormData(form);
    const rating = getRating();
    const body = formData.get("body").trim();
    const liked = !!formData.get("liked");
    const dateInput = form.consumedOn;
    const validationError = reviewValidationError(rating, body, liked, dateInput);
    if (validationError) {
      errorBox.textContent = validationError;
      return;
    }
    const saveButton = document.getElementById("review-save");
    saveButton.disabled = true;
    try {
      await api(`/items/${itemId}/reviews`, {
        method: "POST",
        json: { rating, body: body || null, liked, consumedOn: dateInput.value || null },
      });
      itemPage(itemId);
    } catch (error) {
      showError(errorBox, error, saveReview);
      saveButton.disabled = false;
    }
  };
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    saveReview();
  });
}

function reviewValidationError(rating, body, liked, dateInput) {
  if (!rating && !body && !liked) return "Dê uma nota, curta ou escreva algo.";
  if (dateInput.validity.badInput) return "Data inválida.";
  const date = dateInput.value;
  if (date && (date < dateInput.min || date > dateInput.max)) {
    return `A data precisa estar entre 1900 e hoje (${formatDateForPeople(dateInput.max)}).`;
  }
  return null;
}

function setUpStarInput(starInput, clearButton) {
  let chosenRating = null;
  const paintStars = (rating) => {
    starInput.innerHTML = [1, 2, 3, 4, 5].map((starNumber) => {
      const fillClass = rating >= starNumber * 2 ? "full" : rating === starNumber * 2 - 1 ? "half" : "";
      return `<span data-i="${starNumber}">★${fillClass ? `<span class="${fillClass}">★</span>` : ""}</span>`;
    }).join("");
  };
  const ratingUnderPointer = (event) => {
    const star = event.target.closest("[data-i]");
    if (!star) return null;
    const starBox = star.getBoundingClientRect();
    const isLeftHalf = event.clientX - starBox.left < starBox.width / 2;
    return Number(star.dataset.i) * 2 - (isLeftHalf ? 1 : 0);
  };

  paintStars(0);
  starInput.addEventListener("mousemove", (event) => {
    const hoveredRating = ratingUnderPointer(event);
    if (hoveredRating) paintStars(hoveredRating);
  });
  starInput.addEventListener("mouseleave", () => paintStars(chosenRating || 0));
  starInput.addEventListener("click", (event) => {
    const clickedRating = ratingUnderPointer(event);
    if (clickedRating) {
      chosenRating = clickedRating;
      paintStars(chosenRating);
    }
  });
  clearButton.onclick = () => {
    chosenRating = null;
    paintStars(0);
  };
  return () => chosenRating;
}

let noticeForNextPage = null;

function takeNoticeForThisPage() {
  const notice = noticeForNextPage;
  noticeForNextPage = null;
  return notice;
}

async function diaryPage(username) {
  const entries = await api(`/users/${encodeURIComponent(username)}/diary`);
  const loggedInUser = session.user;
  const isOwnDiary = loggedInUser && loggedInUser.username === username.toLowerCase();
  const avatarUrl = isOwnDiary ? loggedInUser.avatarUrl : entries[0]?.review.avatarUrl;
  const notice = takeNoticeForThisPage();

  page.innerHTML = `
    <div class="panel profile-head tilt-l">
      ${isOwnDiary
        ? `<label class="avatar-pick" title="Trocar foto de perfil">
             <input type="file" accept="image/jpeg,image/png,image/gif,image/webp" hidden id="photo-input">
             <span class="avatar-preview filled" id="photo-preview">${avatarHtml(username, avatarUrl)}</span>
           </label>`
        : avatarHtml(username, avatarUrl)}
      <div><h1>${escapeHtml(username)}</h1><div class="muted">${entries.length} registro(s) no diário${isOwnDiary ? " · clique na foto para trocar" : ""}</div>
        <div class="error" id="photo-error">${escapeHtml(notice || "")}</div></div>
    </div>
    <div class="panel">${entries.length ? entries.map(diaryRowHtml).join("") : `<span class="muted">Nenhum registro ainda.</span>`}
    </div>`;

  if (isOwnDiary) setUpAvatarChange();
}

const truncate = (text, maxLength) => (text.length > maxLength ? text.slice(0, maxLength) + "…" : text);

const diaryRowHtml = ({ review, item }) => `
      <div class="diary-row">
        <span class="date-tag">${escapeHtml(reviewDate(review))}</span>
        <a href="${itemHref(item.id)}">${coverHtml(item.imageUrl, "", hasSquareCover(item.source))}</a>
        <div><a href="${itemHref(item.id)}"><strong>${escapeHtml(item.title)}</strong></a> <span class="muted">${item.year || ""}</span>
          ${review.body ? `<div class="muted">${escapeHtml(truncate(review.body, DIARY_EXCERPT_LENGTH))}</div>` : ""}</div>
        <div><span class="stars">${starsText(review.rating)}</span> ${review.liked ? `<span class="heart">♥</span>` : ""}</div>
      </div>`;

function setUpAvatarChange() {
  const photoInput = document.getElementById("photo-input");
  const errorBox = document.getElementById("photo-error");
  showPhotoPreviewOnChange(photoInput, document.getElementById("photo-preview"), errorBox);
  photoInput.addEventListener("change", async () => {
    const chosenPhoto = photoInput.files[0];
    if (!chosenPhoto) return;
    try {
      await uploadAvatar(chosenPhoto);
      renderNavBar();
    } catch (error) {
      showError(errorBox, error);
    }
  });
}

function redirectToLoginUnlessLoggedIn() {
  if (session.user) return false;
  goTo("#/entrar");
  return true;
}

function newCategoryPage() {
  if (redirectToLoginUnlessLoggedIn()) return;
  page.innerHTML = `<div class="narrow"><form class="panel form tilt-l" id="cat-form">
      <h1>nova categoria</h1>
      <p class="muted" style="margin:0">Avalie qualquer coisa: vinhos, restaurantes, trilhas, cafés…</p>
      <label>Nome <input type="text" name="name" maxlength="60" required></label>
      <label>Descrição <input type="text" name="description"></label>
      <div class="error" id="cat-error"></div>
      <div><button class="btn">${iconSvg("plus")} criar</button></div>
    </form></div>`;
  document.getElementById("cat-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const formData = new FormData(event.target);
    try {
      const newCategory = { name: formData.get("name"), description: formData.get("description") || null };
      const createdCategory = await api("/categories", { method: "POST", json: newCategory });
      goTo(newItemHref(createdCategory.slug));
    } catch (error) {
      showError(document.getElementById("cat-error"), error);
    }
  });
}

function newItemPage(slug) {
  if (redirectToLoginUnlessLoggedIn()) return;
  page.innerHTML = `<div class="narrow"><form class="panel form tilt-r" id="item-form">
      <a class="crumb" href="${categoryHref(slug)}">${iconSvg("back")} voltar</a>
      <h1>adicionar item</h1>
      <label>Nome <input type="text" name="title" maxlength="200" required></label>
      <label>Subtítulo (autor, artista, marca…) <input type="text" name="subtitle"></label>
      <label>Ano <input type="number" name="year" min="1" max="${MAX_ITEM_YEAR}" step="1"></label>
      <label>Descrição <textarea name="description"></textarea></label>
      <label>Foto (JPEG, PNG, GIF ou WebP, até 5 MB) <input type="file" name="image" accept="image/*"></label>
      <div class="error" id="item-error"></div>
      <div><button class="btn">salvar</button></div>
    </form></div>`;
  document.getElementById("item-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const saveButton = event.target.querySelector("button");
    saveButton.disabled = true;
    try {
      const createdItem = await api(`/categories/${encodeURIComponent(slug)}/items`, { method: "POST", form: new FormData(event.target) });
      goTo(itemHref(createdItem.id));
    } catch (error) {
      showError(document.getElementById("item-error"), error);
      saveButton.disabled = false;
    }
  });
}

function showPhotoPreviewOnChange(fileInput, preview, errorBox) {
  fileInput.addEventListener("change", () => {
    const chosenFile = fileInput.files[0];
    if (!chosenFile) return;
    if (chosenFile.size > MAX_IMAGE_BYTES) {
      fileInput.value = "";
      errorBox.textContent = "A foto pode ter no máximo 5 MB.";
      return;
    }
    errorBox.textContent = "";
    preview.innerHTML = `<img src="${URL.createObjectURL(chosenFile)}" alt="">`;
  });
}

async function uploadAvatar(photoFile) {
  const form = new FormData();
  form.append("image", photoFile);
  const updatedUser = await api("/me/avatar", { method: "POST", form });
  session.save({ token: session.token, user: updatedUser });
  return updatedUser;
}

function authPage(mode) {
  const isSignUp = mode === "register";
  page.innerHTML = `<div class="narrow"><form class="panel form tilt-l" id="auth-form" novalidate>
      <div class="auth-tabs">
        <a class="${isSignUp ? "" : "active"}" href="#/entrar">entrar</a>
        <a class="${isSignUp ? "active" : ""}" href="#/criar-conta">criar conta</a>
      </div>
      ${isSignUp ? `
        <label class="avatar-pick" title="Escolher foto de perfil">
          <input type="file" name="image" accept="image/jpeg,image/png,image/gif,image/webp" hidden>
          <span class="avatar-preview" id="avatar-preview">${iconSvg("user")}</span>
          <span>foto de perfil <span class="muted">(opcional)</span></span>
        </label>` : ""}
      <label>Usuário <input type="text" name="username" autocomplete="username" maxlength="30" required>
        ${isSignUp ? `<span class="hint">3 a 30 caracteres: letras minúsculas, números ou _</span>` : ""}</label>
      <label>Senha <input type="password" name="password" autocomplete="${isSignUp ? "new-password" : "current-password"}" required>
        ${isSignUp ? `<span class="hint">pelo menos 8 caracteres</span>` : ""}</label>
      ${isSignUp ? `<label>Confirmar senha <input type="password" name="confirm" autocomplete="new-password" required></label>` : ""}
      <div class="error" id="auth-error"></div>
      <div><button class="btn">${isSignUp ? "criar conta" : "entrar"}</button></div>
      <p class="muted switch">${isSignUp
        ? `Já tem conta? <a href="#/entrar">Entrar</a>`
        : `Ainda não tem conta? <a href="#/criar-conta">Criar conta</a>`}</p>
    </form></div>`;

  const form = document.getElementById("auth-form");
  const errorBox = document.getElementById("auth-error");
  if (isSignUp) showPhotoPreviewOnChange(form.image, document.getElementById("avatar-preview"), errorBox);

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const formData = new FormData(form);
    const username = formData.get("username").trim().toLowerCase();
    const password = formData.get("password");
    const validationError = isSignUp
      ? signUpValidationError(username, password, formData.get("confirm"))
      : loginValidationError(username, password);
    if (validationError) {
      errorBox.textContent = validationError;
      return;
    }

    const submitButton = form.querySelector("button");
    submitButton.disabled = true;
    try {
      session.save(await api(`/auth/${isSignUp ? "register" : "login"}`, { method: "POST", json: { username, password } }));
    } catch (error) {
      showError(errorBox, error);
      submitButton.disabled = false;
      return;
    }

    const chosenPhoto = isSignUp ? formData.get("image") : null;
    if (chosenPhoto && chosenPhoto.size) {
      try {
        await uploadAvatar(chosenPhoto);
      } catch (error) {
        goTo(diaryHref(username));
        noticeForNextPage = "Conta criada, mas a foto não foi enviada: " + error.message;
        return;
      }
    }
    goTo("#/");
  });
}

const VALID_USERNAME = /^[a-z0-9_]{3,30}$/;

function signUpValidationError(username, password, passwordConfirmation) {
  if (!VALID_USERNAME.test(username)) return "Usuário: 3 a 30 caracteres, só letras minúsculas, números ou _.";
  if (password.length < 8) return "A senha precisa ter pelo menos 8 caracteres.";
  if (password !== passwordConfirmation) return "As senhas não conferem.";
  return null;
}

function loginValidationError(username, password) {
  if (!username || !password) return "Preencha usuário e senha.";
  return null;
}

const PARALLAX_EASING = 0.08;
const PARALLAX_MAX_SCROLL_PX = 600;

function startBackdropParallax() {
  const layers = [...document.querySelectorAll(".scene .layer")]
    .map((element) => ({ element, depth: Number(element.dataset.depth) }));
  if (!layers.length || prefersReducedMotion.matches) return;
  const pointerTarget = { x: 0, y: 0 };
  const currentOffset = { x: 0, y: 0 };
  let isAnimating = false;

  const animateTowardPointer = () => {
    currentOffset.x += (pointerTarget.x - currentOffset.x) * PARALLAX_EASING;
    currentOffset.y += (pointerTarget.y - currentOffset.y) * PARALLAX_EASING;
    const scrollProgress = Math.min(window.scrollY, PARALLAX_MAX_SCROLL_PX) / PARALLAX_MAX_SCROLL_PX;
    for (const { element, depth } of layers) {
      const shiftX = -currentOffset.x * 26 * depth;
      const shiftY = -currentOffset.y * 14 * depth - scrollProgress * 40 * depth;
      element.style.transform = `translate(${shiftX.toFixed(2)}px, ${shiftY.toFixed(2)}px)`;
    }
    const hasReachedTarget =
      Math.abs(pointerTarget.x - currentOffset.x) <= 0.001 && Math.abs(pointerTarget.y - currentOffset.y) <= 0.001;
    isAnimating = !hasReachedTarget;
    if (isAnimating) requestAnimationFrame(animateTowardPointer);
  };
  const startAnimatingIfIdle = () => {
    if (isAnimating) return;
    isAnimating = true;
    requestAnimationFrame(animateTowardPointer);
  };

  window.addEventListener("pointermove", (event) => {
    if (event.pointerType !== "mouse") return;
    pointerTarget.x = event.clientX / innerWidth - 0.5;
    pointerTarget.y = event.clientY / innerHeight - 0.5;
    startAnimatingIfIdle();
  }, { passive: true });
  window.addEventListener("scroll", startAnimatingIfIdle, { passive: true });
}

window.addEventListener("hashchange", renderCurrentRoute);
renderCurrentRoute();
startBackdropParallax();
if (session.token) api("/me").catch(() => {});
