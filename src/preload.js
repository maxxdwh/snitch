const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('snitchApi', {
  listProcesses: () => ipcRenderer.invoke('process:list'),
  killProcess: (pid) => ipcRenderer.invoke('process:kill', pid),
  openUrl: (url) => ipcRenderer.invoke('url:open', url),
  setWindowHeight: (height) => ipcRenderer.invoke('window:set-height', height)
});
