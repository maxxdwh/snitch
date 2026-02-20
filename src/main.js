const { app, BrowserWindow, ipcMain, Tray, nativeImage, Menu, shell, screen } = require('electron');
const path = require('path');
const { execFile } = require('child_process');

const WINDOW_WIDTH = 375;
const WINDOW_MIN_HEIGHT = 120;
const WINDOW_MAX_HEIGHT = 600;
const TRAY_POLL_MS = 4000;

let mainWindow = null;
let tray = null;
let isQuitting = false;
let trayCountTimer = null;

function run(cmd, args) {
  return new Promise((resolve, reject) => {
    execFile(cmd, args, { maxBuffer: 4 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) {
        const wrappedError = new Error(stderr || error.message);
        wrappedError.code = error.code;
        reject(wrappedError);
        return;
      }
      resolve(stdout);
    });
  });
}

function parseProcessList(raw) {
  return raw
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const match = line.match(/^(\d+)\s+(\S+)(?:\s+(.*))?$/);
      if (!match) return null;
      return {
        pid: Number(match[1]),
        comm: match[2] || '',
        args: match[3] || ''
      };
    })
    .filter(Boolean)
    .filter((item) => item.pid !== process.pid);
}

function parseListenLsof(raw) {
  const listeners = new Map();
  let currentPid = null;
  let currentCommand = '';

  for (const line of raw.split('\n')) {
    if (!line) continue;
    const tag = line[0];
    const value = line.slice(1);

    if (tag === 'p') {
      currentPid = Number(value);
      if (!listeners.has(currentPid)) {
        listeners.set(currentPid, { pid: currentPid, comm: '', endpoints: new Set() });
      }
      continue;
    }

    if (!currentPid) continue;

    if (tag === 'c') {
      currentCommand = value;
      const row = listeners.get(currentPid);
      if (row && !row.comm) row.comm = value;
      continue;
    }

    if (tag === 'n') {
      const row = listeners.get(currentPid);
      if (!row) continue;
      if (!row.comm && currentCommand) row.comm = currentCommand;
      row.endpoints.add(value.replace(/\s+\(LISTEN\)$/i, ''));
    }
  }

  return listeners;
}

function parseCwdLsof(raw) {
  const cwdByPid = new Map();
  let currentPid = null;

  for (const line of raw.split('\n')) {
    if (!line) continue;
    const tag = line[0];
    const value = line.slice(1);

    if (tag === 'p') {
      currentPid = Number(value);
      continue;
    }

    if (tag === 'n' && currentPid) {
      cwdByPid.set(currentPid, value);
    }
  }

  return cwdByPid;
}

function extractPort(endpoint) {
  const value = String(endpoint || '');
  const match = value.match(/:(\d+)$/);
  return match ? match[1] : '';
}

function hasFolderTitle(row) {
  return Boolean(row.cwd && row.cwd !== 'Unavailable' && row.cwd !== '/');
}

function shouldIncludeRow(row) {
  return row.cwd !== '/';
}

function sortRows(rows) {
  return rows.sort((a, b) => {
    const aHasTitle = hasFolderTitle(a) ? 1 : 0;
    const bHasTitle = hasFolderTitle(b) ? 1 : 0;
    if (aHasTitle !== bHasTitle) return bHasTitle - aHasTitle;
    return a.pid - b.pid;
  });
}

async function getProcessRows() {
  const listenRaw = await run('/usr/sbin/lsof', ['-nP', '-iTCP', '-sTCP:LISTEN', '-Fpcn']);
  const listenersByPid = parseListenLsof(listenRaw);
  const pidList = Array.from(listenersByPid.keys()).filter((pid) => pid !== process.pid);
  if (!pidList.length) return [];

  const pidArg = pidList.join(',');
  const psRaw = await run('/bin/ps', ['-p', pidArg, '-o', 'pid=,comm=,args=']);
  const psRows = parseProcessList(psRaw);
  const psByPid = new Map(psRows.map((row) => [row.pid, row]));

  let cwdByPid = new Map();
  try {
    const lsofRaw = await run('/usr/sbin/lsof', ['-a', '-d', 'cwd', '-Fn', '-p', pidArg]);
    cwdByPid = parseCwdLsof(lsofRaw);
  } catch {
    cwdByPid = new Map();
  }

  return pidList.map((pid) => {
    const listenRow = listenersByPid.get(pid);
    const psRow = psByPid.get(pid);
    const comm = (psRow && psRow.comm) || (listenRow && listenRow.comm) || '';
    const args = (psRow && psRow.args) || comm;
    const endpoints = Array.from((listenRow && listenRow.endpoints) || []);
    const ports = endpoints.map(extractPort).filter(Boolean).join(', ');

    return {
      pid,
      comm,
      args,
      cwd: cwdByPid.get(pid) || 'Unavailable',
      endpoints,
      ports
    };
  });
}

async function getVisibleRows() {
  const rows = await getProcessRows();
  return sortRows(rows.filter(shouldIncludeRow));
}

ipcMain.handle('process:list', async () => {
  const rows = await getVisibleRows();
  setTrayCount(rows.length);
  return rows;
});

ipcMain.handle('process:kill', async (_event, pid) => {
  const targetPid = Number(pid);
  if (!Number.isInteger(targetPid) || targetPid <= 0) {
    throw new Error('Invalid PID');
  }

  try {
    process.kill(targetPid, 'SIGTERM');
    return { ok: true, signal: 'SIGTERM' };
  } catch (firstError) {
    if (firstError.code !== 'ESRCH') {
      try {
        process.kill(targetPid, 'SIGKILL');
        return { ok: true, signal: 'SIGKILL' };
      } catch (secondError) {
        throw new Error(secondError.message || 'Unable to kill process');
      }
    }
    throw new Error(firstError.message || 'Process not found');
  }
});

ipcMain.handle('url:open', async (_event, url) => {
  const value = String(url || '').trim();
  if (!/^https?:\/\/localhost:\d+\/?$/i.test(value)) {
    throw new Error('Invalid localhost URL');
  }

  await shell.openExternal(value);
  return { ok: true };
});

ipcMain.handle('window:set-height', async (_event, rawHeight) => {
  if (!mainWindow) return { ok: false };

  const nextHeight = Math.max(WINDOW_MIN_HEIGHT, Math.min(WINDOW_MAX_HEIGHT, Number(rawHeight) || 0));
  if (!Number.isFinite(nextHeight)) return { ok: false };

  const [currentWidth, currentHeight] = mainWindow.getSize();
  if (Math.abs(currentHeight - nextHeight) <= 2) {
    return { ok: true, height: currentHeight };
  }

  mainWindow.setSize(currentWidth, nextHeight, false);
  return { ok: true, height: nextHeight };
});

function createTrayIcon() {
  const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
  <rect x="2" y="2" width="14" height="14" rx="3" fill="black"/>
  <rect x="5" y="5" width="8" height="8" rx="1.5" fill="white"/>
</svg>`;
  const data = `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`;
  return nativeImage.createFromDataURL(data).resize({ width: 18, height: 18 });
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: WINDOW_WIDTH,
    height: 260,
    minWidth: WINDOW_WIDTH,
    maxWidth: WINDOW_WIDTH,
    minHeight: WINDOW_MIN_HEIGHT,
    maxHeight: WINDOW_MAX_HEIGHT,
    title: 'Snitch',
    backgroundColor: '#121212',
    show: false,
    frame: false,
    resizable: false,
    focusable: true,
    acceptFirstMouse: true,
    skipTaskbar: true,
    alwaysOnTop: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  mainWindow.on('blur', () => {
    if (mainWindow && mainWindow.isVisible()) mainWindow.hide();
  });

  mainWindow.on('close', (event) => {
    if (isQuitting) return;
    event.preventDefault();
    mainWindow.hide();
  });
}

function showWindowFromTray() {
  if (!tray || !mainWindow) return;

  const trayBounds = tray.getBounds();
  const windowBounds = mainWindow.getBounds();
  const display = screen.getDisplayNearestPoint({ x: trayBounds.x, y: trayBounds.y });
  const area = display.workArea;

  const idealX = Math.round(trayBounds.x + trayBounds.width / 2 - windowBounds.width / 2);
  const maxX = area.x + area.width - windowBounds.width;
  const x = Math.max(area.x, Math.min(idealX, maxX));
  const y = Math.round(trayBounds.y + trayBounds.height + 6);

  mainWindow.setPosition(x, y, false);
  mainWindow.show();
  mainWindow.moveTop();
  mainWindow.focus();
  mainWindow.webContents.focus();

  setTimeout(() => {
    if (!mainWindow) return;
    mainWindow.focus();
    mainWindow.webContents.focus();
  }, 30);
}

function setTrayCount(count) {
  if (!tray) return;
  tray.setTitle(`🐀 ${count}`);
}

async function refreshTrayCount() {
  try {
    const rows = await getVisibleRows();
    setTrayCount(rows.length);
  } catch {
    setTrayCount('?');
  }
}

function createTray() {
  tray = new Tray(createTrayIcon());
  tray.setToolTip('Rat');
  setTrayCount(0);

  tray.on('click', () => {
    if (!mainWindow) return;
    if (mainWindow.isVisible()) {
      mainWindow.hide();
    } else {
      showWindowFromTray();
    }
  });

  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: 'Show Snitch', click: () => showWindowFromTray() },
      {
        label: 'Quit',
        click: () => {
          isQuitting = true;
          app.quit();
        }
      }
    ])
  );
}

app.whenReady().then(() => {
  if (process.platform === 'darwin') app.dock.hide();

  createWindow();
  createTray();
  refreshTrayCount();

  trayCountTimer = setInterval(() => {
    refreshTrayCount();
  }, TRAY_POLL_MS);

  app.on('activate', () => {
    showWindowFromTray();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', () => {
  if (!trayCountTimer) return;
  clearInterval(trayCountTimer);
  trayCountTimer = null;
});
