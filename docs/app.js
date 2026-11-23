(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const profile = $('profileSelect');
  const level = $('levelSelect');
  const pattern = $('patternSelect');
  const enhanced = $('enhancedToggle');
  const roleOutput = $('roleOutput');
  const nameOutput = $('nameOutput');
  const responseOutput = $('responseOutput');
  const countOutput = $('countOutput');
  const bars = [...document.querySelectorAll('#responseBars i')];
  const controls = [...document.querySelectorAll('.ax-control')];
  let entryCount = 0;
  let lastRole = '';
  let currentControl = null;
  let pulseTimeout;
  const customRules = {};
  const defaults = { level: 1, pattern: 'Alignment' };

  // A visual demo only: none of this code attempts to produce hardware haptics.
  function settingsFor(role) {
    if (profile.value === 'silent') return { level: 0, pattern: 'Alignment' };
    if (profile.value === 'default') return defaults;
    return customRules[role] || defaults;
  }

  function setUiToRole(role) {
    const settings = settingsFor(role);
    level.value = String(settings.level);
    pattern.value = settings.pattern;
    level.disabled = profile.value !== 'custom';
    pattern.disabled = profile.value !== 'custom';
  }

  function renderBars(power) {
    bars.forEach((item, index) => {
      item.classList.toggle('on', power > index);
      item.style.height = power > index ? `${15 + ((index + 1) * 7)}px` : '9px';
    });
  }

  function enter(control) {
    if (currentControl === control) return;
    if (currentControl) currentControl.classList.remove('is-triggered');
    currentControl = control;
    lastRole = control.dataset.role || 'AXUnknown';
    const desc = control.dataset.label || 'Accessible control';
    const s = settingsFor(lastRole);
    entryCount += 1;
    countOutput.textContent = String(entryCount).padStart(2, '0');
    roleOutput.textContent = lastRole;
    nameOutput.textContent = desc;
    responseOutput.textContent = s.level === 0 ? 'Feedback Off · no snap' : `${s.pattern} · Level ${s.level}${enhanced.getAttribute('aria-pressed') === 'true' ? ' · enhanced preview' : ' · standard preview'}`;
    renderBars(s.level);
    control.classList.add('is-triggered');
    clearTimeout(pulseTimeout);
    pulseTimeout = setTimeout(() => control.classList.remove('is-triggered'), 340);
    if (profile.value !== 'custom') setUiToRole(lastRole);
    else setUiToRole(lastRole);
  }

  controls.forEach((control) => {
    control.addEventListener('pointerenter', () => enter(control));
    control.addEventListener('focus', () => enter(control));
    control.addEventListener('click', () => enter(control));
    control.addEventListener('pointerleave', () => {
      if (currentControl === control) currentControl = null;
    });
  });

  profile.addEventListener('change', () => {
    setUiToRole(lastRole || 'AXButton');
    const s = settingsFor(lastRole || 'AXButton');
    responseOutput.textContent = profile.value === 'silent'
      ? 'Silent profile · all controls Off'
      : profile.value === 'default'
      ? 'Default profile · Level 1 across controls'
      : 'Custom profile · change settings for the last hovered role';
    renderBars(s.level);
  });

  const editRule = () => {
    if (profile.value !== 'custom') return;
    const role = lastRole || 'AXButton';
    customRules[role] = { level: Number(level.value), pattern: pattern.value };
    roleOutput.textContent = role;
    responseOutput.textContent = `Saved demo override: ${role} → ${customRules[role].level ? `${customRules[role].pattern} Level ${customRules[role].level}` : 'Off'}`;
    renderBars(customRules[role].level);
  };
  level.addEventListener('change', editRule);
  pattern.addEventListener('change', editRule);

  enhanced.addEventListener('click', () => {
    const isOn = enhanced.getAttribute('aria-pressed') !== 'true';
    enhanced.setAttribute('aria-pressed', String(isOn));
    responseOutput.textContent = isOn
      ? 'Enhanced visual preview · physical haptics unavailable in browser'
      : 'Standard visual preview · fixed physical haptic pattern on macOS';
  });

  $('clearButton').addEventListener('click', () => {
    entryCount = 0;
    currentControl?.classList.remove('is-triggered');
    currentControl = null;
    lastRole = '';
    countOutput.textContent = '00';
    roleOutput.textContent = 'Move over a control';
    nameOutput.textContent = 'No boundary event yet';
    responseOutput.textContent = 'Waiting for an entry event…';
    renderBars(0);
    setUiToRole('AXButton');
  });

  $('copyInstall').addEventListener('click', async () => {
    const copyButton = $('copyInstall');
    const text = $('terminalCode').textContent.trim();
    try {
      await navigator.clipboard.writeText(text);
      copyButton.textContent = 'Copied ✓';
      window.setTimeout(() => { copyButton.textContent = 'Copy command'; }, 1800);
    } catch {
      copyButton.textContent = 'Select code to copy';
      window.setTimeout(() => { copyButton.textContent = 'Copy command'; }, 1800);
    }
  });

  // Link to the actual repo only when GitHub Pages provides its owner/repo location.
  // Local previews remain self-contained with working source-ZIP downloads.
  const host = location.hostname.toLowerCase();
  if (host.endsWith('.github.io')) {
    const owner = host.slice(0, -'.github.io'.length);
    const segments = location.pathname.split('/').filter(Boolean);
    const repository = segments[0];
    if (owner && repository) {
      const url = `https://github.com/${encodeURIComponent(owner)}/${encodeURIComponent(repository)}`;
      $('headerSource').href = url;
      $('sourceLink').href = url;
      $('headerSource').target = '_blank';
      $('sourceLink').target = '_blank';
      $('headerSource').rel = 'noopener noreferrer';
      $('sourceLink').rel = 'noopener noreferrer';
    }
  }
  profile.value = 'default';
  setUiToRole('AXButton');
  renderBars(0);
})();
