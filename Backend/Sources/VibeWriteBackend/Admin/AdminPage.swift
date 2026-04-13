import Foundation
import Vapor

func makeAdminPageResponse(authenticated: Bool) -> Response {
    let response = Response(status: .ok)
    response.headers.replaceOrAdd(name: .contentType, value: "text/html; charset=utf-8")
    response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
    response.body = .init(string: renderAdminPage(authenticated: authenticated))
    return response
}

func renderAdminPage(authenticated: Bool) -> String {
    let authValue = authenticated ? "true" : "false"
    let loginHidden = authenticated ? "hidden" : ""
    let dashboardHidden = authenticated ? "" : "hidden"

    return #"""
    <!doctype html>
    <html lang="zh-CN">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>VibeWrite Admin</title>
      <style>
        :root {
          color-scheme: light;
          --bg: #f7f4ef;
          --panel: rgba(255, 255, 255, 0.92);
          --text: #221f1b;
          --muted: #665c52;
          --line: rgba(34, 31, 27, 0.12);
          --accent: #7b4f2c;
          --accent-soft: rgba(123, 79, 44, 0.1);
        }

        * { box-sizing: border-box; }
        body {
          margin: 0;
          font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          background:
            radial-gradient(circle at top left, rgba(123, 79, 44, 0.12), transparent 30%),
            linear-gradient(180deg, #fcfbf8 0%, #f4efe7 100%);
          color: var(--text);
        }

        .shell {
          max-width: 1320px;
          margin: 0 auto;
          padding: 24px;
        }

        .hero {
          display: flex;
          justify-content: space-between;
          gap: 16px;
          align-items: flex-start;
          margin-bottom: 20px;
        }

        .hero h1 {
          margin: 0 0 8px;
          font-size: 28px;
          letter-spacing: -0.02em;
        }

        .hero p {
          margin: 0;
          color: var(--muted);
        }

        .status-pill {
          display: inline-flex;
          align-items: center;
          gap: 8px;
          border: 1px solid var(--line);
          background: var(--panel);
          border-radius: 999px;
          padding: 10px 14px;
          box-shadow: 0 14px 42px rgba(34, 31, 27, 0.08);
        }

        .status-dot {
          width: 10px;
          height: 10px;
          border-radius: 999px;
          background: #4d9f6a;
        }

        .grid {
          display: grid;
          gap: 16px;
          grid-template-columns: repeat(12, minmax(0, 1fr));
        }

        .panel {
          background: var(--panel);
          border: 1px solid var(--line);
          border-radius: 20px;
          padding: 16px;
          box-shadow: 0 16px 50px rgba(34, 31, 27, 0.08);
        }

        .panel h2 {
          margin: 0 0 12px;
          font-size: 18px;
        }

        .panel .meta {
          color: var(--muted);
          margin: 0 0 12px;
          font-size: 13px;
        }

        .panel.login {
          max-width: 520px;
          margin: 56px auto 0;
        }

        .form-grid {
          display: grid;
          gap: 10px;
        }

        label {
          display: grid;
          gap: 6px;
          font-size: 14px;
          color: var(--muted);
        }

        input, textarea, button, select {
          font: inherit;
          border-radius: 12px;
          border: 1px solid var(--line);
          background: #fff;
          color: var(--text);
          padding: 10px 12px;
        }

        textarea {
          min-height: 140px;
          resize: vertical;
        }

        button {
          cursor: pointer;
          background: var(--accent);
          color: #fff;
          border-color: transparent;
          font-weight: 600;
        }

        button.secondary {
          background: #fff;
          color: var(--text);
          border-color: var(--line);
        }

        button.inline {
          padding: 8px 10px;
          border-radius: 10px;
          font-size: 13px;
        }

        .actions {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
          align-items: center;
        }

        .stack {
          display: grid;
          gap: 12px;
        }

        .two-col {
          display: grid;
          gap: 12px;
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }

        pre {
          margin: 0;
          white-space: pre-wrap;
          word-break: break-word;
          background: #f9f7f2;
          border: 1px solid rgba(34, 31, 27, 0.08);
          border-radius: 14px;
          padding: 12px;
          min-height: 72px;
          color: #2b2520;
        }

        table {
          width: 100%;
          border-collapse: collapse;
        }

        th, td {
          text-align: left;
          border-bottom: 1px solid var(--line);
          padding: 10px 8px;
          vertical-align: top;
          font-size: 14px;
        }

        th {
          color: var(--muted);
          font-weight: 600;
        }

        .span-12 { grid-column: span 12; }
        .span-8 { grid-column: span 8; }
        .span-6 { grid-column: span 6; }
        .span-4 { grid-column: span 4; }

        .hint { color: var(--muted); font-size: 12px; }
        .error { color: #ad3b2d; font-size: 13px; min-height: 1.2em; }
        .ok { color: #4d9f6a; font-size: 13px; min-height: 1.2em; }
        .hidden { display: none !important; }
      </style>
    </head>
    <body data-authenticated="\#(authValue)">
      <div class="shell">
        <div class="hero">
          <div>
            <h1>VibeWrite Admin</h1>
            <p>单人运维后台，直接复用现有 session 和后端 API。</p>
          </div>
          <div class="status-pill">
            <span class="status-dot"></span>
            <span id="auth-state">\#(authenticated ? "已登录" : "未登录")</span>
          </div>
        </div>

        <section id="login-panel" class="panel login \#(loginHidden)">
          <h2>管理员登录</h2>
          <p class="meta">登录后会进入单页 dashboard。会话使用 `vibewrite_admin_session`。</p>
          <form id="login-form" class="form-grid">
            <label>
              用户名
              <input name="username" autocomplete="username" required />
            </label>
            <label>
              密码
              <input name="password" type="password" autocomplete="current-password" required />
            </label>
            <button type="submit">登录</button>
            <div id="login-feedback" class="error"></div>
          </form>
        </section>

        <main id="dashboard-panel" class="\#(dashboardHidden)">
          <div class="grid">
            <section class="panel span-12">
              <h2>总览</h2>
              <p class="meta">今日请求、成功率、超限数、活跃设备与当前模型配置。</p>
              <div class="actions">
                <button id="refresh-overview" class="secondary inline" type="button">刷新总览</button>
                <button id="logout-button" class="secondary inline" type="button">退出登录</button>
              </div>
              <pre id="overview-output">加载中…</pre>
            </section>

            <section class="panel span-12">
              <h2>请求列表</h2>
              <p class="meta">支持按 installation/action/status/errorCode/时间范围筛选。</p>
              <form id="request-filter-form" class="form-grid">
                <div class="two-col">
                  <label>installationId <input name="installationId" /></label>
                  <label>action <input name="action" placeholder="start|continue|edit" /></label>
                </div>
                <div class="two-col">
                  <label>status <input name="status" placeholder="accepted|rejected" /></label>
                  <label>errorCode <input name="errorCode" /></label>
                </div>
                <div class="two-col">
                  <label>createdAtStart <input name="createdAtStart" /></label>
                  <label>createdAtEnd <input name="createdAtEnd" /></label>
                </div>
                <div class="actions">
                  <button type="submit">查询请求</button>
                  <button id="clear-requests" class="secondary" type="button">清空条件</button>
                </div>
              </form>
              <pre id="requests-output">等待查询…</pre>
            </section>

            <section class="panel span-6">
              <h2>密钥</h2>
              <p class="meta">provider API key 与管理员凭证。</p>
              <form id="secrets-form" class="form-grid">
                <label>providerApiKey <input name="providerApiKey" /></label>
                <label>adminUsername <input name="adminUsername" required /></label>
                <label>adminPassword <input name="adminPassword" type="password" /></label>
                <div class="actions">
                  <button type="submit">保存密钥</button>
                  <button id="load-secrets" class="secondary" type="button">刷新密钥</button>
                </div>
              </form>
              <pre id="secrets-output">加载中…</pre>
            </section>

            <section class="panel span-6">
              <h2>AI System Prompt</h2>
              <p class="meta">当前生效的 template / action rules / model context rules。</p>
              <form id="system-prompt-form" class="form-grid">
                <label>templateBody<textarea name="templateBody" required></textarea></label>
                <label>actionRulesJson<textarea name="actionRulesJson" required></textarea></label>
                <label>modelContextRulesJson<textarea name="modelContextRulesJson" required></textarea></label>
                <div class="actions">
                  <button type="submit">保存 Prompt</button>
                  <button id="load-system-prompt" class="secondary" type="button">刷新 Prompt</button>
                </div>
              </form>
              <pre id="system-prompt-output">加载中…</pre>
            </section>

            <section class="panel span-6">
              <h2>Quota</h2>
              <p class="meta">日/周限额以及当前已用量。</p>
              <form id="quota-form" class="form-grid">
                <div class="two-col">
                  <label>dailyLimit <input name="dailyLimit" type="number" min="0" /></label>
                  <label>weeklyLimit <input name="weeklyLimit" type="number" min="0" /></label>
                </div>
                <div class="actions">
                  <button type="submit">保存 Quota</button>
                  <button id="load-quota" class="secondary" type="button">刷新 Quota</button>
                </div>
              </form>
              <pre id="quota-output">加载中…</pre>
            </section>

            <section class="panel span-6">
              <h2>Devices</h2>
              <p class="meta">查看设备状态、用量和封禁操作。</p>
              <div class="actions">
                <button id="load-devices" class="secondary inline" type="button">刷新 Devices</button>
              </div>
              <pre id="devices-output">加载中…</pre>
            </section>
          </div>

          <div id="dashboard-feedback" class="error" style="margin-top: 12px;"></div>
          <div id="dashboard-ok" class="ok" style="margin-top: 6px;"></div>
        </main>
      </div>

      <script>
        const isAuthenticated = document.body.dataset.authenticated === "true";
        const loginPanel = document.getElementById("login-panel");
        const dashboardPanel = document.getElementById("dashboard-panel");
        const loginFeedback = document.getElementById("login-feedback");
        const dashboardFeedback = document.getElementById("dashboard-feedback");
        const dashboardOk = document.getElementById("dashboard-ok");

        function setFeedback(message) {
          dashboardFeedback.textContent = message || "";
        }

        function setOk(message) {
          dashboardOk.textContent = message || "";
          if (message) {
            setTimeout(() => {
              if (dashboardOk.textContent === message) {
                dashboardOk.textContent = "";
              }
            }, 2200);
          }
        }

        async function readResponseText(response) {
          const text = await response.text();
          return text || response.statusText;
        }

        async function api(path, options = {}) {
          const response = await fetch(path, {
            credentials: "same-origin",
            headers: {
              ...(options.body && !(options.body instanceof FormData) ? { "Content-Type": "application/json" } : {}),
              ...(options.headers || {})
            },
            ...options
          });
          if (!response.ok) {
            throw new Error(await readResponseText(response));
          }
          const contentType = response.headers.get("content-type") || "";
          if (contentType.includes("application/json")) {
            return await response.json();
          }
          return await response.text();
        }

        function authGate() {
          if (isAuthenticated) {
            loginPanel.classList.add("hidden");
            dashboardPanel.classList.remove("hidden");
          } else {
            dashboardPanel.classList.add("hidden");
            loginPanel.classList.remove("hidden");
          }
        }

        function pretty(value) {
          return JSON.stringify(value, null, 2);
        }

        function escapeHtml(value) {
          return String(value)
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;")
            .replaceAll('"', "&quot;")
            .replaceAll("'", "&#39;");
        }

        async function refreshOverview() {
          const data = await api("/v3/admin/overview");
          document.getElementById("overview-output").textContent = pretty(data);
        }

        async function refreshRequests() {
          const form = document.getElementById("request-filter-form");
          const params = new URLSearchParams();
          for (const [key, value] of new FormData(form).entries()) {
            if (String(value).trim().length > 0) {
              params.set(key, String(value).trim());
            }
          }
          const query = params.toString();
          const data = await api("/v3/admin/requests" + (query ? "?" + query : ""));
          document.getElementById("requests-output").textContent = pretty(data);
        }

        async function refreshSecrets() {
          const data = await api("/v3/admin/secrets");
          const form = document.getElementById("secrets-form");
          form.providerApiKey.value = "";
          form.adminUsername.value = data.adminUsername;
          form.adminPassword.value = "";
          document.getElementById("secrets-output").textContent = pretty(data);
        }

        async function saveSecrets(event) {
          event.preventDefault();
          const form = event.currentTarget;
          const payload = {
            providerApiKey: form.providerApiKey.value.trim() || null,
            adminUsername: form.adminUsername.value.trim() || null,
            adminPassword: form.adminPassword.value.trim() || null
          };
          const data = await api("/v3/admin/secrets", {
            method: "PUT",
            body: JSON.stringify(payload)
          });
          document.getElementById("secrets-output").textContent = pretty(data);
          setOk("密钥已更新");
          await refreshSecrets();
        }

        async function refreshSystemPrompt() {
          const data = await api("/v3/admin/system-prompt");
          const form = document.getElementById("system-prompt-form");
          form.templateBody.value = data.templateBody;
          form.actionRulesJson.value = data.actionRulesJson;
          form.modelContextRulesJson.value = data.modelContextRulesJson;
          document.getElementById("system-prompt-output").textContent = pretty(data);
        }

        async function saveSystemPrompt(event) {
          event.preventDefault();
          const form = event.currentTarget;
          const data = await api("/v3/admin/system-prompt", {
            method: "PUT",
            body: JSON.stringify({
              templateBody: form.templateBody.value,
              actionRulesJson: form.actionRulesJson.value,
              modelContextRulesJson: form.modelContextRulesJson.value
            })
          });
          document.getElementById("system-prompt-output").textContent = pretty(data);
          setOk("System Prompt 已更新");
          await refreshSystemPrompt();
        }

        async function refreshQuota() {
          const data = await api("/v3/admin/quota");
          const form = document.getElementById("quota-form");
          form.dailyLimit.value = data.dailyLimit;
          form.weeklyLimit.value = data.weeklyLimit;
          document.getElementById("quota-output").textContent = pretty(data);
        }

        async function saveQuota(event) {
          event.preventDefault();
          const form = event.currentTarget;
          const payload = {};
          if (String(form.dailyLimit.value).trim().length > 0) {
            payload.dailyLimit = Number(form.dailyLimit.value);
          }
          if (String(form.weeklyLimit.value).trim().length > 0) {
            payload.weeklyLimit = Number(form.weeklyLimit.value);
          }
          const data = await api("/v3/admin/quota", {
            method: "PUT",
            body: JSON.stringify(payload)
          });
          document.getElementById("quota-output").textContent = pretty(data);
          setOk("Quota 已更新");
          await refreshQuota();
          await refreshOverview();
        }

        async function refreshDevices() {
          const data = await api("/v3/admin/devices");
          const rows = data.devices.map((device) => {
            const blockReason = device.blockReason ? `Block: ${escapeHtml(device.blockReason)}` : "Block: -";
            const blockedAt = device.blockedAt ? escapeHtml(device.blockedAt) : "-";
            return `
              <tr>
                <td>${escapeHtml(device.installationId)}</td>
                <td>${escapeHtml(device.status)}</td>
                <td>${escapeHtml(device.todayUsed)}</td>
                <td>${escapeHtml(device.weeklyUsed)}</td>
                <td>${escapeHtml(device.firstSeenAt)}</td>
                <td>${escapeHtml(device.lastSeenAt)}</td>
                <td>${escapeHtml(device.tokenIssuedAt)}</td>
                <td>${blockedAt}</td>
                <td>${blockReason}</td>
                <td>
                  <div class="actions">
                    <button type="button" class="inline secondary" data-action="block" data-installation-id="${escapeHtml(device.installationId)}">Block</button>
                    <button type="button" class="inline secondary" data-action="unblock" data-installation-id="${escapeHtml(device.installationId)}">Unblock</button>
                  </div>
                </td>
              </tr>
            `;
          }).join("");
          document.getElementById("devices-output").innerHTML = `
            <table>
              <thead>
                <tr>
                  <th>installationId</th>
                  <th>status</th>
                  <th>todayUsed</th>
                  <th>weeklyUsed</th>
                  <th>firstSeenAt</th>
                  <th>lastSeenAt</th>
                  <th>tokenIssuedAt</th>
                  <th>blockedAt</th>
                  <th>blockReason</th>
                  <th>actions</th>
                </tr>
              </thead>
              <tbody>${rows || "<tr><td colspan='10'>暂无设备</td></tr>"}</tbody>
            </table>
          `;
        }

        async function updateDeviceState(installationId, action) {
          let url = `/v3/admin/devices/${encodeURIComponent(installationId)}/${action}`;
          let body = undefined;
          if (action === "block") {
            const blockReason = window.prompt("Block reason", "manual");
            body = JSON.stringify({ blockReason: blockReason || "manual" });
          }
          const data = await api(url, {
            method: "POST",
            body
          });
          setOk(`设备 ${installationId} 已 ${action === "block" ? "封禁" : "解除封禁"}`);
          document.getElementById("devices-output").textContent = pretty({ updated: data });
          await refreshDevices();
          await refreshOverview();
          await refreshQuota();
        }

        async function logout() {
          await api("/v3/admin/logout", { method: "POST" });
          window.location.reload();
        }

        async function login(event) {
          event.preventDefault();
          loginFeedback.textContent = "";
          const form = event.currentTarget;
          const payload = {
            username: form.username.value.trim(),
            password: form.password.value
          };
          const response = await fetch("/v3/admin/login", {
            method: "POST",
            credentials: "same-origin",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload)
          });
          if (!response.ok) {
            loginFeedback.textContent = await readResponseText(response);
            return;
          }
          window.location.reload();
        }

        authGate();

        if (isAuthenticated) {
          document.getElementById("login-form").addEventListener("submit", login);
          document.getElementById("logout-button").addEventListener("click", logout);
          document.getElementById("refresh-overview").addEventListener("click", refreshOverview);
          document.getElementById("request-filter-form").addEventListener("submit", async (event) => {
            event.preventDefault();
            await refreshRequests();
          });
          document.getElementById("clear-requests").addEventListener("click", async () => {
            document.getElementById("request-filter-form").reset();
            await refreshRequests();
          });
          document.getElementById("secrets-form").addEventListener("submit", saveSecrets);
          document.getElementById("load-secrets").addEventListener("click", refreshSecrets);
          document.getElementById("system-prompt-form").addEventListener("submit", saveSystemPrompt);
          document.getElementById("load-system-prompt").addEventListener("click", refreshSystemPrompt);
          document.getElementById("quota-form").addEventListener("submit", saveQuota);
          document.getElementById("load-quota").addEventListener("click", refreshQuota);
          document.getElementById("load-devices").addEventListener("click", refreshDevices);
          document.getElementById("devices-output").addEventListener("click", async (event) => {
            const target = event.target;
            if (!(target instanceof HTMLButtonElement)) {
              return;
            }
            const installationId = target.dataset.installationId;
            const action = target.dataset.action;
            if (!installationId || !action) {
              return;
            }
            await updateDeviceState(installationId, action);
          });

          refreshOverview().catch((error) => setFeedback(error.message));
          refreshRequests().catch((error) => setFeedback(error.message));
          refreshSecrets().catch((error) => setFeedback(error.message));
          refreshSystemPrompt().catch((error) => setFeedback(error.message));
          refreshQuota().catch((error) => setFeedback(error.message));
          refreshDevices().catch((error) => setFeedback(error.message));
        } else {
          document.getElementById("login-form").addEventListener("submit", login);
        }
      </script>
    </body>
    </html>
    """#
}
