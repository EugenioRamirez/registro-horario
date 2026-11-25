'use strict';
(() => {
  const root = document.documentElement;
  const key = 'employee-portal-theme';
  const button = document.getElementById('theme-toggle');
  const sidebarButton = document.getElementById('sidebar-toggle');
  const setThemeLabel = () => {
    const night = root.dataset.theme === 'night';
    button.textContent = night ? '☀ Modo día' : '☾ Modo noche';
    button.setAttribute('aria-label', night ? 'Activar modo día' : 'Activar modo noche');
  };
  button.addEventListener('click', () => {
    root.dataset.theme = root.dataset.theme === 'night' ? 'day' : 'night';
    try { localStorage.setItem(key, root.dataset.theme); } catch (_) {}
    setThemeLabel();
  });
  sidebarButton.addEventListener('click', () => {
    const collapsed = document.body.classList.toggle('sidebar-collapsed');
    sidebarButton.setAttribute('aria-expanded', String(!collapsed));
    sidebarButton.setAttribute('aria-label', collapsed ? 'Expandir menú' : 'Colapsar menú');
    sidebarButton.title = collapsed ? 'Expandir menú' : 'Colapsar menú';
    sidebarButton.textContent = collapsed ? '›' : '‹';
  });
  setThemeLabel();
})();
