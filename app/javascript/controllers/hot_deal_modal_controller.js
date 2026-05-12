import { Controller } from "@hotwired/stimulus"

// ═══════════════════════════════════════════════════════════════════════════
// HotDealModalController — Rama 6 "Hot Deals" premium mini-ficha
// ═══════════════════════════════════════════════════════════════════════════
// Abre un overlay premium con los datos completos de la parcela al hacer
// clic en una card del catálogo (payload @parcels_full — Premier/Admin).
//
// Datos: inyectados como data-* attrs en el <article> de _card_full.html.erb
// Cierre: Esc · click en backdrop · botón ×
//
// REGLAS (hotdeals/mini_ficha.md):
//   - NO muestra Mini CRM (pertenece solo a la Ficha Rama 2)
//   - NO consume créditos
//   - "View Full Dossier" → research_parcel_path (Rama 2)
//   - NO se abre para cards teaser (no-Premier)
// ═══════════════════════════════════════════════════════════════════════════

const STARS = { optimo: 5, viable: 4, deficiente: 2 }
const STAR_COLORS = {
  optimo:     "#16a34a",  // green-600
  viable:     "#ca8a04",  // yellow-600
  deficiente: "#dc2626",  // red-600
}

export default class extends Controller {
  // ── Lifecycle ──────────────────────────────────────────────────────────

  connect() {
    this._handleKeydown = this._onKeydown.bind(this)
  }

  disconnect() {
    this._removeModal()
  }

  // ── Actions ────────────────────────────────────────────────────────────

  // data-action="click->hot-deal-modal#openCard" on the <article>
  openCard(event) {
    // Ignore clicks on the "View dossier" link — let it navigate normally
    if (event.target.closest("a[href]")) return

    const card = event.currentTarget
    if (!card.dataset.parcelId) return  // guard: no datos = no abrir

    this._open(card.dataset)
  }

  close() {
    this._removeModal()
  }

  // ── Private ────────────────────────────────────────────────────────────

  _open(d) {
    if (document.getElementById("hd-modal-overlay")) return  // ya abierto

    const grade      = (d.grade || "").toLowerCase()
    const starCount  = STARS[grade] || 0
    const starColor  = STAR_COLORS[grade] || "#94a3b8"
    const filledStars = "★".repeat(starCount)
    const emptyStars  = "☆".repeat(5 - starCount)
    const gradeLabel  = grade === "optimo" ? "Óptimo" : grade === "viable" ? "Viable" : grade === "deficiente" ? "Deficiente" : "Sin clasificar"

    const minBid    = d.openingBid   ? this._currency(d.openingBid)   : "TBD"
    const mktValue  = d.marketValue  ? this._currency(d.marketValue)  : "—"
    const saleDate  = d.saleDate     || "TBD"
    const propType  = d.propertyType || "—"
    const lotAcres  = d.lotAreaAcres ? `${parseFloat(d.lotAreaAcres).toFixed(2)} acres` : "—"
    const yearBuilt = d.yearBuilt    || "—"
    const location  = [d.county, d.state].filter(Boolean).join(" · ")
    const address   = d.address      || "Address on file"
    const mapUrl    = d.mapUrl       || ""
    const dossierUrl = d.dossierUrl  || "#"

    // ── Overlay backdrop ─────────────────────────────────────────────────
    const overlay = document.createElement("div")
    overlay.id = "hd-modal-overlay"
    overlay.setAttribute("role", "dialog")
    overlay.setAttribute("aria-modal", "true")
    overlay.setAttribute("aria-label", `Hot Deal preview: ${address}`)
    overlay.style.cssText = [
      "position:fixed;inset:0;z-index:9000;",
      "display:flex;align-items:center;justify-content:center;",
      "background:rgba(15,23,42,0.60);",
      "backdrop-filter:blur(4px);",
      "padding:16px;",
      "animation:hd-fade-in 180ms ease both;"
    ].join("")

    // ── Modal panel ──────────────────────────────────────────────────────
    overlay.innerHTML = `
      <style>
        @keyframes hd-fade-in  { from { opacity:0; transform:scale(0.97) translateY(8px); } to { opacity:1; transform:none; } }
        @keyframes hd-fade-out { from { opacity:1; } to { opacity:0; } }
        #hd-modal-panel { font-family:'Geist',ui-sans-serif,system-ui,sans-serif; }
      </style>

      <div id="hd-modal-panel"
           style="
             position:relative;
             background:#fff;
             border-radius:20px;
             box-shadow:0 32px 80px -16px rgba(15,23,42,0.35),0 8px 24px rgba(15,23,42,0.12);
             max-width:520px;
             width:100%;
             overflow:hidden;
             max-height:92vh;
             display:flex;
             flex-direction:column;
           ">

        <%#── Close button ──%>
        <button id="hd-modal-close"
                aria-label="Close preview"
                style="
                  position:absolute;top:14px;right:14px;z-index:10;
                  width:32px;height:32px;border-radius:50%;border:none;cursor:pointer;
                  background:rgba(15,23,42,0.55);color:#fff;
                  display:grid;place-items:center;
                  font-size:18px;line-height:1;
                  transition:background 150ms;
                "
                onmouseover="this.style.background='rgba(15,23,42,0.80)'"
                onmouseout="this.style.background='rgba(15,23,42,0.55)'">×</button>

        <%#── Satellite photo ──%>
        <div style="position:relative;aspect-ratio:16/9;background:#1e293b;flex-shrink:0;overflow:hidden;">
          ${mapUrl
            ? `<img src="${this._esc(mapUrl)}" alt="Satellite view"
                    style="width:100%;height:100%;object-fit:cover;"
                    onerror="this.style.display='none'">`
            : `<div style="display:grid;place-items:center;height:100%;color:#64748b;font-size:13px;">Map unavailable</div>`
          }
          <%#── Grade badge overlaid on photo ──%>
          <div style="
            position:absolute;bottom:14px;left:14px;
            display:inline-flex;align-items:center;gap:7px;
            background:rgba(15,23,42,0.75);backdrop-filter:blur(6px);
            border-radius:10px;padding:7px 12px;
          ">
            <span style="color:${starColor};font-size:15px;letter-spacing:2px;">${filledStars}<span style="color:#334155;">${emptyStars}</span></span>
            <span style="color:#fff;font:600 12px var(--font-mono,'ui-monospace');letter-spacing:0.08em;text-transform:uppercase;">${this._esc(gradeLabel)}</span>
          </div>
          <%#── "PREMIER" ribbon ──%>
          <div style="
            position:absolute;top:14px;left:14px;
            background:linear-gradient(90deg,#c79a4a,#f0d28a,#c79a4a);
            background-size:200% 100%;
            animation:shimmer 6s linear infinite;
            border-radius:6px;padding:3px 9px;
            font:700 9px ui-monospace,monospace;letter-spacing:0.12em;
            color:#422e07;
          ">★ PREMIER</div>
        </div>

        <%#── Body ──%>
        <div style="padding:22px 24px 24px;overflow-y:auto;flex:1;">

          <%#── Location breadcrumb ──%>
          <div style="font:500 11px ui-monospace,monospace;color:#94a3b8;letter-spacing:0.1em;text-transform:uppercase;margin-bottom:6px;">
            📍 ${this._esc(location)}
          </div>

          <%#── Address ──%>
          <h2 style="font:600 20px 'Geist',system-ui;color:#0f172a;margin:0 0 18px;line-height:1.25;">
            ${this._esc(address)}
          </h2>

          <%#── KPI grid ──%>
          <dl style="display:grid;grid-template-columns:1fr 1fr;gap:1px;background:#e2e8f0;border-radius:12px;overflow:hidden;border:1px solid #e2e8f0;margin-bottom:18px;">
            ${this._kpi("Min Bid", minBid, "#0f172a")}
            ${this._kpi("Market Value", mktValue)}
            ${this._kpi("Auction Date", this._esc(saleDate))}
            ${this._kpi("Property Type", this._esc(propType))}
            ${this._kpi("Lot Area", this._esc(lotAcres))}
            ${this._kpi("Year Built", this._esc(yearBuilt))}
          </dl>

          <%#── Actions ──%>
          <div style="display:flex;gap:10px;">
            <a href="${this._esc(dossierUrl)}"
               id="hd-modal-dossier-btn"
               style="
                 flex:1;display:inline-flex;align-items:center;justify-content:center;gap:7px;
                 padding:12px 18px;border-radius:12px;
                 background:#0f172a;color:#fff;text-decoration:none;
                 font:600 13px 'Geist',system-ui;
                 transition:background 160ms;
               "
               onmouseover="this.style.background='#1e293b'"
               onmouseout="this.style.background='#0f172a'">
              View Full Dossier
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M5 12h14M13 5l7 7-7 7"/></svg>
            </a>
            <button id="hd-modal-close-btn"
                    style="
                      width:46px;height:46px;border-radius:12px;border:1px solid #e2e8f0;
                      background:#fff;cursor:pointer;display:grid;place-items:center;
                      transition:background 160ms;
                    "
                    onmouseover="this.style.background='#f8fafc'"
                    onmouseout="this.style.background='#fff'"
                    title="Close">
              <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
          </div>

        </div>
      </div>
    `

    document.body.appendChild(overlay)
    document.addEventListener("keydown", this._handleKeydown)

    // Bind close targets
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) this._removeModal()
    })
    overlay.querySelector("#hd-modal-close")?.addEventListener("click",     () => this._removeModal())
    overlay.querySelector("#hd-modal-close-btn")?.addEventListener("click", () => this._removeModal())

    // Focus the dossier button for accessibility
    requestAnimationFrame(() => {
      overlay.querySelector("#hd-modal-dossier-btn")?.focus()
    })
  }

  _removeModal() {
    const overlay = document.getElementById("hd-modal-overlay")
    if (!overlay) return
    document.removeEventListener("keydown", this._handleKeydown)
    overlay.style.animation = "hd-fade-out 160ms ease both"
    overlay.addEventListener("animationend", () => overlay.remove(), { once: true })
  }

  _onKeydown(e) {
    if (e.key === "Escape") this._removeModal()
  }

  // ── Formatting helpers ─────────────────────────────────────────────────

  _currency(raw) {
    const n = parseFloat(raw)
    if (isNaN(n)) return raw
    return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 }).format(n)
  }

  _esc(str) {
    if (!str) return ""
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#x27;")
  }

  _kpi(label, value, valueColor = "#334155") {
    return `
      <div style="background:#fff;padding:14px 16px;">
        <dt style="font:600 9.5px ui-monospace,monospace;color:#94a3b8;letter-spacing:0.12em;text-transform:uppercase;margin-bottom:4px;">${label}</dt>
        <dd style="font:600 16px 'Geist',system-ui;color:${valueColor};margin:0;">${value}</dd>
      </div>
    `
  }
}
