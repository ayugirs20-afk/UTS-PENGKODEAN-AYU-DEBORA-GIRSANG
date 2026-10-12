import { createClient } from "@supabase/supabase-js";
import "./styles.css";

const app = document.querySelector("#app");
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
const clientReady = Boolean(supabaseUrl && supabaseAnonKey);
const supabase = clientReady ? createClient(supabaseUrl, supabaseAnonKey) : null;

const money = new Intl.NumberFormat("id-ID", {
  style: "currency",
  currency: "IDR",
  maximumFractionDigits: 2,
});

let currentUser = null;
let supabaseConnection = clientReady ? "checking" : "missing";
let workspaceUserId = null;
let accounts = [];
let lines = [emptyLine(), emptyLine()];

function emptyLine() {
  return { account_id: "", debit: "", credit: "" };
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[char]);
}

function amountInCents(value) {
  if (value === "" || !Number.isFinite(Number(value))) return 0;
  const amount = Number(value);
  const cents = Math.round(amount * 100);
  if (
    amount < 0
    || !Number.isSafeInteger(cents)
    || Math.abs(amount * 100 - cents) > 1e-7
  ) return -1;
  return cents;
}

function formatMoney(cents) {
  return money.format(cents / 100);
}

function localDateValue(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function showMessage(message, kind = "info") {
  const area = document.querySelector("#notice");
  if (!area) return;
  area.textContent = message;
  area.className = `notice notice--${kind}`;
  area.hidden = false;
}

function clearMessage() {
  const area = document.querySelector("#notice");
  if (area) area.hidden = true;
}

function renderConnectionStatus() {
  const status = document.querySelector("#supabase-status");
  if (!status) return;

  const labels = {
    checking: "MEMERIKSA · Supabase",
    connected: "TERHUBUNG · Supabase",
    error: "GANGGUAN · Supabase",
    missing: "BELUM DIATUR · Supabase",
  };
  status.textContent = labels[supabaseConnection];
  status.className = `connection-status connection-status--${supabaseConnection}`;
}

async function checkSupabaseConnection() {
  if (!clientReady) {
    renderConnectionStatus();
    return;
  }

  try {
    const response = await fetch(`${supabaseUrl.replace(/\/+$/, "")}/auth/v1/health`, {
      headers: { apikey: supabaseAnonKey },
      signal: AbortSignal.timeout(8000),
    });
    supabaseConnection = response.ok ? "connected" : "error";
  } catch {
    supabaseConnection = "error";
  }
  renderConnectionStatus();
}

function renderShell() {
  app.innerHTML = `
    <header class="topbar">
      <a class="brand" href="#" aria-label="Voucher kas keluar beranda">
        <span class="brand-overline">SISTEM INFORMASI AKUNTANSI · GENERAL LEDGER</span>
        <span class="brand-title">Voucher Kas Keluar</span>
        <span class="brand-subtitle">(Bukti Kas Keluar)</span>
      </a>
      <div class="header-actions">
        <span id="supabase-status" class="connection-status"></span>
        <div id="session-area" class="session-area"></div>
      </div>
    </header>
    <main class="page">
      <section id="notice" class="notice" role="status" aria-live="polite" hidden></section>
      <section id="auth-panel" class="panel auth-panel"></section>
      <section id="workspace" hidden>
        <div class="panel form-panel">
          <div class="panel-heading">
            <div>
              <p class="eyebrow">ENTRI TRANSAKSI</p>
              <h2>Buat voucher baru</h2>
            </div>
            <span class="status-pill status-pill--draft">POSTING AMAN</span>
          </div>
          <form id="voucher-form">
            <div class="form-grid">
              <label class="field">
                <span>Nomor bukti</span>
                <input id="reference-no" name="reference_no" maxlength="50"
                  placeholder="Contoh: KK-2026-001" required />
              </label>
              <label class="field">
                <span>Tanggal transaksi</span>
                <input id="trx-date" name="trx_date" type="date" required />
              </label>
              <label class="field field--wide">
                <span>Keterangan</span>
                <input id="description" name="description" maxlength="500"
                  placeholder="Jelaskan tujuan pembayaran" required />
              </label>
            </div>
            <div class="table-wrap">
              <table class="entry-table">
                <thead><tr>
                  <th>Akun</th><th class="numeric">Debit (Rp)</th>
                  <th class="numeric">Kredit (Rp)</th><th></th>
                </tr></thead>
                <tbody id="journal-lines"></tbody>
                <tfoot><tr>
                  <th>Total</th><th id="total-debit" class="numeric">Rp0</th>
                  <th id="total-credit" class="numeric">Rp0</th><th></th>
                </tr></tfoot>
              </table>
            </div>
            <div class="form-actions">
              <button id="add-line" type="button" class="button button--secondary">
                <span aria-hidden="true">＋</span> Tambah baris
              </button>
              <p id="balance-state" class="balance-state" aria-live="polite"></p>
            </div>
            <div class="submit-row">
              <p class="form-hint">Jurnal divalidasi kembali oleh PostgreSQL sebelum disimpan.</p>
              <button id="submit-voucher" type="submit" class="button button--primary" disabled>
                Posting voucher <span aria-hidden="true">→</span>
              </button>
            </div>
          </form>
        </div>
        <section class="panel history-panel">
          <div class="panel-heading">
            <div>
              <p class="eyebrow">AUDIT TRAIL</p>
              <h2>Voucher saya</h2>
            </div>
            <button id="refresh-history" type="button" class="button button--secondary">Muat ulang</button>
          </div>
          <div class="table-wrap">
            <table class="history-table">
              <thead><tr>
                <th>Bukti</th><th>Tanggal</th><th>Keterangan</th>
                <th>Status</th><th>Checksum</th><th>Aksi</th>
              </tr></thead>
              <tbody id="voucher-history"></tbody>
            </table>
          </div>
          <div id="audit-details" class="audit-details" hidden></div>
        </section>
      </section>
      <footer class="footer">
        <span>Ledger Prototype</span>
        <span>Double-entry · Audit trail · PostgreSQL</span>
      </footer>
    </main>`;

  document.querySelector("#trx-date").value = localDateValue();
  document.querySelector("#add-line").addEventListener("click", () => {
    lines.push(emptyLine());
    renderLines();
  });
  document.querySelector("#voucher-form").addEventListener("submit", submitVoucher);
  document.querySelector("#refresh-history").addEventListener("click", loadHistory);
}

function renderAuth() {
  const sessionArea = document.querySelector("#session-area");
  const authPanel = document.querySelector("#auth-panel");
  const workspace = document.querySelector("#workspace");
  renderConnectionStatus();

  if (currentUser) {
    sessionArea.innerHTML = `
      <span class="user-email">${escapeHtml(currentUser.email)}</span>
      <button id="sign-out" class="button button--quiet" type="button">Keluar</button>`;
    document.querySelector("#sign-out").addEventListener("click", async () => {
      const { error } = await supabase.auth.signOut();
      if (error) showMessage(`Gagal keluar: ${error.message}`, "error");
    });
    authPanel.hidden = true;
    workspace.hidden = false;
    if (workspaceUserId !== currentUser.id) {
      workspaceUserId = currentUser.id;
      accounts = [];
      lines = [emptyLine(), emptyLine()];
      loadAccounts();
      loadHistory();
    }
    return;
  }

  workspaceUserId = null;
  accounts = [];
  lines = [emptyLine(), emptyLine()];
  sessionArea.replaceChildren();
  workspace.hidden = true;
  authPanel.hidden = false;
  if (!clientReady) {
    authPanel.innerHTML = `
      <p class="eyebrow">KONFIGURASI DIPERLUKAN</p>
      <h2>Hubungkan proyek Supabase</h2>
      <p>Salin <code>.env.example</code> menjadi <code>.env</code>, lalu isi URL proyek dan anon/publishable key Supabase.</p>
      <p class="form-hint">Jangan pernah menaruh service-role key di browser atau repository.</p>`;
    return;
  }

  authPanel.innerHTML = `
    <p class="eyebrow">AKUN SUPABASE AUTH</p>
    <h2 id="auth-title">Masuk</h2>
    <p class="auth-description">Login diperlukan agar setiap voucher tercatat dengan identitas pembuatnya sebagai bagian dari jejak audit.</p>
    <div class="auth-note">
      <strong>Akses aman untuk pengguna terdaftar</strong>
      <p>Identitas <code>created_by</code> diambil dari sesi Supabase Auth dan diverifikasi kembali oleh database.</p>
    </div>
    <form id="auth-form" class="auth-form">
      <label class="field"><span>Email</span><input id="auth-email" type="email" autocomplete="email" required /></label>
      <label class="field"><span>Password</span><input id="auth-password" type="password"
        minlength="8" autocomplete="current-password" required /></label>
      <div class="auth-actions">
        <button id="auth-submit" class="button button--primary" type="submit">Masuk</button>
        <button id="auth-toggle" class="button button--quiet" type="button">Buat akun baru</button>
      </div>
    </form>`;
  let signUpMode = false;
  document.querySelector("#auth-toggle").addEventListener("click", () => {
    signUpMode = !signUpMode;
    document.querySelector("#auth-title").textContent =
      signUpMode ? "Buat akun" : "Masuk";
    document.querySelector("#auth-submit").textContent =
      signUpMode ? "Daftar" : "Masuk";
    document.querySelector("#auth-toggle").textContent =
      signUpMode ? "Sudah punya akun? Masuk" : "Buat akun baru";
  });
  document.querySelector("#auth-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    clearMessage();
    const email = document.querySelector("#auth-email").value.trim();
    const password = document.querySelector("#auth-password").value;
    const button = document.querySelector("#auth-submit");
    button.disabled = true;
    try {
      if (signUpMode) {
        const { data, error } = await supabase.auth.signUp({ email, password });
        if (error) throw error;
        if (!data.session) {
          showMessage("Pendaftaran berhasil. Periksa email untuk konfirmasi akun, lalu masuk.", "success");
        } else {
          showMessage("Akun berhasil dibuat.", "success");
        }
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
      }
    } catch (error) {
      showMessage(`Autentikasi gagal: ${error.message}`, "error");
    } finally {
      button.disabled = false;
    }
  });
}

function renderLines() {
  const tbody = document.querySelector("#journal-lines");
  if (!tbody) return;
  tbody.replaceChildren();

  lines.forEach((line, index) => {
    const row = document.createElement("tr");
    const accountCell = document.createElement("td");
    const select = document.createElement("select");
    select.className = "input-control account-select";
    select.setAttribute("aria-label", `Akun baris ${index + 1}`);
    select.add(new Option("Pilih akun", ""));
    for (const account of accounts) {
      select.add(new Option(`${account.account_code} · ${account.account_name}`, String(account.account_id)));
    }
    select.value = line.account_id;
    select.addEventListener("change", () => {
      line.account_id = select.value;
      updateBalance();
    });
    accountCell.append(select);
    row.append(accountCell);

    for (const field of ["debit", "credit"]) {
      const cell = document.createElement("td");
      const input = document.createElement("input");
      input.type = "number";
      input.min = "0.01";
      input.step = "0.01";
      input.inputMode = "decimal";
      input.className = "input-control numeric amount-input";
      input.value = line[field];
      input.setAttribute("aria-label", `${field === "debit" ? "Debit" : "Kredit"} baris ${index + 1}`);
      input.addEventListener("input", () => {
        line[field] = input.value;
        updateBalance();
      });
      cell.append(input);
      row.append(cell);
    }

    const actionCell = document.createElement("td");
    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "icon-button";
    remove.textContent = "Hapus";
    remove.disabled = lines.length <= 2;
    remove.setAttribute("aria-label", `Hapus baris ${index + 1}`);
    remove.addEventListener("click", () => {
      lines.splice(index, 1);
      renderLines();
    });
    actionCell.append(remove);
    row.append(actionCell);
    tbody.append(row);
  });
  updateBalance();
}

function updateBalance() {
  const debit = lines.reduce((sum, line) => sum + amountInCents(line.debit), 0);
  const credit = lines.reduce((sum, line) => sum + amountInCents(line.credit), 0);
  const validLines = lines.length >= 2 && lines.every((line) => {
    const debitCents = amountInCents(line.debit);
    const creditCents = amountInCents(line.credit);
    return line.account_id
      && debitCents >= 0
      && creditCents >= 0
      && ((debitCents > 0) !== (creditCents > 0));
  });
  const cashCredit = lines.some((line) => {
    const account = accounts.find((item) => String(item.account_id) === line.account_id);
    return account?.is_cash && amountInCents(line.credit) > 0;
  });
  const cashDebit = lines.some((line) => {
    const account = accounts.find((item) => String(item.account_id) === line.account_id);
    return account?.is_cash && amountInCents(line.debit) > 0;
  });
  const balanced = debit > 0 && debit === credit;
  const valid = validLines && balanced && cashCredit && !cashDebit;
  const messages = [];
  if (lines.length < 2) messages.push("Minimal dua baris.");
  if (!validLines) messages.push("Pilih akun dan isi tepat satu sisi pada tiap baris.");
  if (lines.some((line) => amountInCents(line.debit) < 0 || amountInCents(line.credit) < 0)) {
    messages.push("Nominal tidak boleh negatif atau memiliki lebih dari dua angka desimal.");
  }
  if (!balanced) messages.push(`Debit/kredit belum seimbang (selisih ${formatMoney(Math.abs(debit - credit))}).`);
  if (!cashCredit || cashDebit) messages.push("Akun kas/bank wajib dikredit untuk kas keluar.");

  document.querySelector("#total-debit").textContent = formatMoney(debit);
  document.querySelector("#total-credit").textContent = formatMoney(credit);
  const state = document.querySelector("#balance-state");
  state.textContent = valid ? "Seimbang — siap diposting" : messages.join(" ");
  state.className = `balance-state ${valid ? "balance-state--ok" : "balance-state--pending"}`;
  document.querySelector("#submit-voucher").disabled = !valid;
}

async function loadAccounts() {
  const userId = currentUser?.id;
  if (!userId) return;
  const { data, error } = await supabase
    .from("chart_of_accounts")
    .select("account_id, account_code, account_name, is_cash")
    .eq("is_active", true)
    .order("account_code");
  if (currentUser?.id !== userId) return;
  if (error) {
    showMessage(`Gagal memuat bagan akun: ${error.message}`, "error");
    return;
  }
  accounts = data;
  renderLines();
}

async function submitVoucher(event) {
  event.preventDefault();
  clearMessage();
  const button = document.querySelector("#submit-voucher");
  button.disabled = true;
  try {
    const payload = {
      p_reference_no: document.querySelector("#reference-no").value.trim(),
      p_trx_date: document.querySelector("#trx-date").value,
      p_description: document.querySelector("#description").value.trim(),
      p_lines: lines.map((line) => ({
        account_id: line.account_id,
        debit: amountInCents(line.debit) / 100,
        credit: amountInCents(line.credit) / 100,
      })),
    };
    const { data, error } = await supabase.rpc("create_cash_voucher", payload);
    if (error) throw error;
    showMessage(`Voucher berhasil diposting. ID jurnal: ${data}`, "success");
    document.querySelector("#voucher-form").reset();
    document.querySelector("#trx-date").value = localDateValue();
    lines = [emptyLine(), emptyLine()];
    renderLines();
    await loadHistory();
  } catch (error) {
    showMessage(`Voucher gagal disimpan: ${error.message}`, "error");
  } finally {
    updateBalance();
  }
}

async function loadHistory() {
  const tbody = document.querySelector("#voucher-history");
  if (!tbody || !currentUser) return;
  const userId = currentUser.id;
  tbody.innerHTML = `<tr><td colspan="6" class="empty-cell">Memuat voucher…</td></tr>`;
  const { data, error } = await supabase
    .from("journal_headers")
    .select("header_id, reference_no, trx_date, description, posting_status, hash_checksum, reversal_of")
    .order("created_at", { ascending: false })
    .limit(50);
  if (currentUser?.id !== userId) return;
  if (error) {
    tbody.innerHTML = `<tr><td colspan="6" class="empty-cell">Gagal memuat voucher.</td></tr>`;
    showMessage(`Gagal memuat riwayat: ${error.message}`, "error");
    return;
  }
  if (!data.length) {
    tbody.innerHTML = `<tr><td colspan="6" class="empty-cell">Belum ada voucher.</td></tr>`;
    return;
  }
  tbody.replaceChildren();
  for (const voucher of data) {
    const row = document.createElement("tr");
    const status = voucher.reversal_of ? "REVERSAL" : voucher.posting_status;
    const values = [
      voucher.reference_no,
      voucher.trx_date,
      voucher.description,
      status,
      voucher.hash_checksum ? `${voucher.hash_checksum.slice(0, 12)}…` : "—",
    ];
    for (const [index, value] of values.entries()) {
      const cell = document.createElement("td");
      cell.textContent = value || "—";
      if (index === 3) {
        cell.innerHTML = `<span class="status-pill status-pill--posted">${escapeHtml(value)}</span>`;
      }
      row.append(cell);
    }
    const actions = document.createElement("td");
    const audit = document.createElement("button");
    audit.type = "button";
    audit.className = "text-button";
    audit.textContent = "Audit";
    audit.addEventListener("click", () => loadAudit(voucher.header_id));
    actions.append(audit);
    if (voucher.posting_status === "POSTED") {
      const verify = document.createElement("button");
      verify.type = "button";
      verify.className = "text-button";
      verify.textContent = "Cek hash";
      verify.addEventListener("click", () => verifyChecksum(voucher.header_id));
      actions.append(verify);
    }
    if (voucher.posting_status === "POSTED" && !voucher.reversal_of) {
      const reverse = document.createElement("button");
      reverse.type = "button";
      reverse.className = "text-button text-button--danger";
      reverse.textContent = "Balikkan";
      reverse.addEventListener("click", () => reverseVoucher(voucher));
      actions.append(reverse);
    }
    row.append(actions);
    tbody.append(row);
  }
}

async function verifyChecksum(headerId) {
  clearMessage();
  const { data, error } = await supabase.rpc("verify_voucher_checksum", {
    p_header_id: headerId,
  });
  if (error) {
    showMessage(`Verifikasi checksum gagal: ${error.message}`, "error");
    return;
  }
  showMessage(
    data ? `Checksum jurnal ${headerId} valid.` : `Checksum jurnal ${headerId} tidak cocok.`,
    data ? "success" : "error",
  );
}

async function loadAudit(headerId) {
  clearMessage();
  const details = document.querySelector("#audit-details");
  details.hidden = false;
  details.innerHTML = `<h3>Riwayat audit</h3><p class="form-hint">Memuat catatan…</p>`;
  const { data, error } = await supabase.rpc("get_voucher_audit", {
    p_header_id: headerId,
  });
  if (error) {
    showMessage(`Gagal memuat audit trail: ${error.message}`, "error");
    details.innerHTML = "";
    return;
  }
  details.innerHTML = `<h3>Riwayat audit · jurnal ${escapeHtml(headerId)}</h3>`;
  if (!data.length) {
    details.insertAdjacentHTML("beforeend", `<p class="form-hint">Belum ada catatan audit.</p>`);
    return;
  }
  const list = document.createElement("ol");
  list.className = "audit-list";
  for (const event of data) {
    const item = document.createElement("li");
    const summary = document.createElement("strong");
    summary.textContent = `${event.action} · ${event.table_name} · ${new Date(event.changed_at).toLocaleString("id-ID")}`;
    item.append(summary);
    const actor = document.createElement("p");
    actor.textContent = `Pengguna: ${event.changed_by || "system"}`;
    item.append(actor);
    list.append(item);
  }
  details.append(list);
}

async function reverseVoucher(voucher) {
  if (!window.confirm(`Buat jurnal pembalik untuk ${voucher.reference_no}?`)) return;
  clearMessage();
  try {
    const { data, error } = await supabase.rpc("reverse_cash_voucher", {
      p_header_id: voucher.header_id,
      p_reason: "Pembalikan melalui antarmuka voucher",
    });
    if (error) throw error;
    showMessage(`Jurnal pembalik berhasil diposting. ID jurnal: ${data}`, "success");
    await loadHistory();
  } catch (error) {
    showMessage(`Jurnal pembalik gagal: ${error.message}`, "error");
  }
}

function start() {
  renderShell();
  renderAuth();
  checkSupabaseConnection();
  if (clientReady) {
    supabase.auth.onAuthStateChange((_event, session) => {
      currentUser = session?.user ?? null;
      renderAuth();
    });
  }
}

start();
