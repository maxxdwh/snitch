const refreshBtn = document.getElementById('refreshBtn');
const activeCountEl = document.getElementById('activeCount');
const statusEl = document.getElementById('status');
const processListEl = document.getElementById('processList');
const appShellEl = document.querySelector('.app-shell');

let isLoading = false;
let refreshTimer = null;
let resizeTimer = null;

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function iconHtml(type) {
  if (type === 'kill') {
    return `
      <svg class="lucide" viewBox="0 0 24 24" aria-hidden="true">
        <path d="M18 6 6 18" />
        <path d="m6 6 12 12" />
      </svg>
    `;
  }

  if (type === 'spinner') {
    return `
      <svg class="lucide spinner-icon" viewBox="0 0 24 24" aria-hidden="true">
        <path d="M21 12a9 9 0 1 1-6.2-8.56" />
      </svg>
    `;
  }

  return '';
}

function setRefreshLoading(loading) {
  refreshBtn.classList.toggle('is-loading', Boolean(loading));
}

function pickPort(row) {
  const fromPorts = String(row.ports || '')
    .split(',')
    .map((part) => part.trim())
    .find(Boolean);
  if (fromPorts) return fromPorts;

  for (const endpoint of row.endpoints || []) {
    const match = String(endpoint).match(/:(\d+)$/);
    if (match) return match[1];
  }
  return '';
}

function syncWindowHeight() {
  if (resizeTimer) clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    const contentHeight = appShellEl
      ? Math.ceil(appShellEl.scrollHeight)
      : Math.max(
          document.documentElement ? document.documentElement.scrollHeight : 0,
          document.body ? document.body.scrollHeight : 0
        );
    window.snitchApi.setWindowHeight(contentHeight).catch(() => {});
  }, 10);
}

function renderRows(rows) {
  processListEl.innerHTML = '';
  activeCountEl.textContent = String(rows.length);

  if (!rows.length) {
    const li = document.createElement('li');
    li.className = 'empty';
    li.textContent = 'No matching processes found.';
    processListEl.appendChild(li);
    return;
  }

  for (const row of rows) {
    const li = document.createElement('li');
    li.className = 'process-item';

    const main = document.createElement('div');
    main.className = 'process-main';
    const pathValue = row.cwd || 'Unavailable';
    main.setAttribute('data-cwd', pathValue);
    main.title = pathValue;
    const metaBits = [`PID ${row.pid}`];
    if (row.ports) metaBits.push(`Port ${row.ports}`);
    const folderName = pathValue && pathValue !== 'Unavailable'
      ? pathValue.split('/').filter(Boolean).pop() || pathValue
      : row.args || row.comm;
    main.innerHTML = `
      <div class="process-title">${escapeHtml(folderName)}</div>
      <div class="process-meta">${escapeHtml(metaBits.join(' • '))}</div>
    `;

    const actions = document.createElement('div');
    actions.className = 'row-actions';

    const port = pickPort(row);
    if (port) {
      li.classList.add('process-item--clickable');
      li.title = `Open http://localhost:${port}`;
    }
    li.addEventListener('click', async (event) => {
      if (event.target.closest('.kill-btn')) return;
      if (!port) return;
      try {
        await window.snitchApi.openUrl(`http://localhost:${port}`);
      } catch (error) {
        statusEl.textContent = `Failed to open localhost:${port}: ${error.message}`;
      }
    });

    const killBtn = document.createElement('button');
    killBtn.className = 'kill-btn';
    killBtn.innerHTML = iconHtml('kill');
    killBtn.setAttribute('aria-label', `Kill PID ${row.pid}`);
    killBtn.title = `Kill PID ${row.pid}`;
    killBtn.addEventListener('click', async () => {
      killBtn.disabled = true;
      killBtn.innerHTML = iconHtml('spinner');

      try {
        await window.snitchApi.killProcess(row.pid);
        statusEl.textContent = `Killed PID ${row.pid}`;
        await refresh();
      } catch (error) {
        statusEl.textContent = `Failed to kill PID ${row.pid}: ${error.message}`;
        killBtn.disabled = false;
        killBtn.innerHTML = iconHtml('kill');
      }
    });

    actions.appendChild(killBtn);
    li.appendChild(main);
    li.appendChild(actions);
    processListEl.appendChild(li);
  }

  syncWindowHeight();
}

async function refresh() {
  if (isLoading) return;
  isLoading = true;
  setRefreshLoading(true);

  try {
    const rows = await window.snitchApi.listProcesses();

    renderRows(rows);
    statusEl.textContent = '';
  } catch (error) {
    statusEl.textContent = `Error: ${error.message}`;
  } finally {
    isLoading = false;
    setRefreshLoading(false);
    syncWindowHeight();
  }
}

function setupAutoRefresh() {
  if (refreshTimer) clearInterval(refreshTimer);
  refreshTimer = setInterval(() => {
    refresh();
  }, 2500);
}

refreshBtn.addEventListener('click', () => refresh());

setupAutoRefresh();
refresh();
