'use strict';

// ─── Config ──────────────────────────────────────────────────────────────────

const CURRENT_ORIGIN = window.location.origin;
const API = `${CURRENT_ORIGIN}/api`;

// Forward current extension/profile selection to API calls
function getSchemaFilterParams() {
  const params = new URLSearchParams(window.location.search);
  const parts = [];
  const ext = params.get('extensions');
  if (ext !== null) parts.push('extensions=' + encodeURIComponent(ext));
  const prof = params.get('profiles');
  if (prof !== null) parts.push('profiles=' + encodeURIComponent(prof));
  return parts.length ? '?' + parts.join('&') : '';
}

async function apiFetch(path) {
  const filterParams = getSchemaFilterParams();
  const joiner = path.includes('?') ? '&' : '?';
  const url = API + path + (filterParams ? joiner + filterParams.substring(1) : '');
  const r = await fetch(url, { headers: { Accept: 'application/json' } });
  if (!r.ok) throw new Error(`HTTP ${r.status} – ${url}`);
  return r.json();
}

// ─── State ───────────────────────────────────────────────────────────────────

const S = {
  cy: null,
  categories: [],
  classes: [],
  objects: [],
  classDetails: {},
  objectDetails: {},
  search: '',
};

// ─── Scope detection ─────────────────────────────────────────────────────────

const SCOPE_PARAMS = new URLSearchParams(window.location.search);
const SCOPE_CLASS = SCOPE_PARAMS.get('class');
const SCOPE_OBJECT = SCOPE_PARAMS.get('object');
const SCOPE_CATEGORY = SCOPE_PARAMS.get('category');

// ─── Color maps ──────────────────────────────────────────────────────────────

const CAT_COLOR = {
  1: '#0F1B5C', 2: '#b91c1c', 3: '#7c2d9e',
  4: '#0E7490', 5: '#166534', 6: '#0F766E',
  7: '#92400e', 8: '#374151',
};

const CAT_CLASS_COLOR = {
  1: '#0891B2', 2: '#ff7b72', 3: '#c084fc',
  4: '#34d399', 5: '#4ade80', 6: '#14B8A6',
  7: '#fbbf24', 8: '#94a3b8',
};

// ─── Normalize API responses ─────────────────────────────────────────────────

function normCats(data) {
  return Object.entries(data.attributes || data).map(([k, v]) => ({ name: k, ...v }));
}

function normClasses(data) {
  return Object.entries(data).map(([k, v]) => ({ name: k, ...v }));
}

function normObjects(data) {
  return Object.entries(data).map(([k, v]) => ({ name: k, ...v }));
}

// ─── Graph builders ──────────────────────────────────────────────────────────

function buildEventEls() {
  const els = [];
  const classMap = new Map(S.classes.map(c => [c.name, c]));

  for (const cat of S.categories) {
    els.push({ data: {
      id: `cat_${cat.uid}`, label: (cat.caption || cat.name).replace(/ /g, '\n'),
      type: 'category', nodeType: 'category', name: cat.name,
      caption: cat.caption || cat.name, description: cat.description,
      uid: cat.uid, color: CAT_COLOR[cat.uid] || '#374151',
    }});
  }

  for (const cls of S.classes) {
    const catUid = cls.category_uid || (cls.uid ? Math.floor(cls.uid / 1000) : null);
    const color = CAT_CLASS_COLOR[catUid] || '#8b949e';

    els.push({ data: {
      id: `cls_${cls.name}`, label: (cls.caption || cls.name).replace(/ /g, '\n'),
      type: 'class', nodeType: 'class', name: cls.name,
      extension: cls.extension || null, caption: cls.caption || cls.name,
      categoryUid: catUid, description: cls.description, color,
    }});

    const parentCls = cls.extends ? classMap.get(cls.extends) : null;
    const parentCatUid = parentCls
      ? (parentCls.category_uid || (parentCls.uid ? Math.floor(parentCls.uid / 1000) : null))
      : null;
    const extendsInSameCat = parentCls && parentCatUid === catUid;

    if (extendsInSameCat) {
      els.push({ data: {
        id: `e_ext_${cls.name}`, source: `cls_${cls.extends}`, target: `cls_${cls.name}`,
        type: 'extends',
      }});
    } else if (catUid && S.categories.some(c => c.uid === catUid)) {
      els.push({ data: {
        id: `e_cc_${cls.name}`, source: `cat_${catUid}`, target: `cls_${cls.name}`,
        type: 'contains',
      }});
    }
  }

  return els;
}

function buildObjectEls() {
  const els = [];
  const knownIds = new Set(['obj__root_']);

  els.push({ data: {
    id: 'obj__root_', label: 'object\n(base)',
    type: 'object-root', nodeType: 'object', name: 'object',
    caption: 'Base Object',
  }});

  for (const obj of S.objects) {
    const id = obj.extension ? `obj_${obj.extension}_${obj.name}` : `obj_${obj.name}`;
    knownIds.add(id);
    els.push({ data: {
      id, label: (obj.extension ? `${obj.extension}/${obj.name}` : (obj.caption || obj.name)).replace(/ /g, '\n'),
      type: 'object', nodeType: 'object', name: obj.name,
      extension: obj.extension || null, caption: obj.caption || obj.name,
      description: obj.description,
    }});
  }

  for (const obj of S.objects) {
    const id = obj.extension ? `obj_${obj.extension}_${obj.name}` : `obj_${obj.name}`;
    const parentRaw = obj.extends || 'object';
    const parentId = parentRaw === 'object' ? 'obj__root_' : `obj_${parentRaw}`;
    const src = knownIds.has(parentId) ? parentId : 'obj__root_';
    els.push({ data: {
      id: `e_obj_${id}`, source: src, target: id, type: 'extends',
    }});
  }

  return els;
}

// ─── Cytoscape styles ────────────────────────────────────────────────────────

function buildStyles() {
  return [
    { selector: 'node', style: {
      label: 'data(label)', color: '#fff',
      'font-size': 9, 'font-weight': 500,
      'text-valign': 'center', 'text-halign': 'center',
      'text-wrap': 'wrap', 'text-max-width': 70,
      'font-family': 'Inter, -apple-system, sans-serif',
    }},
    { selector: 'node[type="category"]', style: {
      shape: 'round-rectangle', width: 90, height: 45,
      'background-color': 'data(color)', 'background-opacity': 0.9,
      'font-size': 10, 'font-weight': 700,
    }},
    { selector: 'node[type="class"]', style: {
      shape: 'ellipse', width: 60, height: 60,
      'background-color': 'data(color)', 'background-opacity': 0.85,
      'font-size': 8,
    }},
    { selector: 'node[type="object"], node[type="object-root"]', style: {
      shape: 'diamond', width: 55, height: 55,
      'background-color': '#a371f7', 'background-opacity': 0.8,
      'font-size': 8,
    }},
    { selector: 'edge', style: {
      width: 1, 'curve-style': 'bezier',
      'target-arrow-shape': 'triangle', 'arrow-scale': 0.6,
      'line-color': '#30363d', 'target-arrow-color': '#30363d',
      opacity: 0.6,
    }},
    { selector: 'edge[type="extends"]', style: {
      'line-color': '#8b949e', 'target-arrow-color': '#8b949e',
      'line-style': 'dashed', 'line-dash-pattern': [5, 3], width: 1.5,
    }},
    { selector: 'edge[type="has_attr"]', style: {
      'line-color': '#a371f7', 'target-arrow-color': '#a371f7',
      width: 1.5, opacity: 0.8,
      label: 'data(label)', 'font-size': 7, color: '#8b949e',
      'text-rotation': 'autorotate', 'text-margin-y': -8,
    }},
    { selector: ':selected', style: { 'border-width': 3, 'border-color': '#22D3EE' }},
    { selector: '.faded', style: { opacity: 0.12 }},
    { selector: '.highlighted', style: { opacity: 1 }},
  ];
}

// ─── Cytoscape init ──────────────────────────────────────────────────────────

function initCy(elements, layoutName) {
  if (S.cy) { S.cy.destroy(); S.cy = null; }

  S.cy = cytoscape({
    container: document.getElementById('cy'),
    elements,
    style: buildStyles(),
    layout: layoutOpts(layoutName || 'cose'),
    minZoom: 0.2, maxZoom: 4,
    wheelSensitivity: 0.3,
  });

  S.cy.on('tap', 'node', async (e) => { await onNodeClick(e.target); });
  S.cy.on('tap', (e) => { if (e.target === S.cy) clearSelection(); });
}

function layoutOpts(name) {
  const base = { animate: false, nodeDimensionsIncludeLabels: true };
  switch (name) {
    case 'breadthfirst': return { name, ...base, directed: true, spacingFactor: 1.2 };
    case 'circle': return { name, ...base };
    case 'grid': return { name, ...base };
    default: return { name: 'cose', ...base, nodeRepulsion: 50000, idealEdgeLength: 80, gravity: 0.1, numIter: 300 };
  }
}

// ─── Node interaction ────────────────────────────────────────────────────────

async function onNodeClick(node) {
  const { nodeType, name } = node.data();

  S.cy.elements().removeClass('faded highlighted');
  const conn = node.closedNeighborhood();
  S.cy.elements().not(conn).addClass('faded');

  setDetailLoading(node);

  try {
    if (nodeType === 'category') {
      renderCategoryDetail(node);
    } else if (nodeType === 'class') {
      const ext = node.data('extension');
      const cacheKey = ext ? `${ext}/${name}` : name;
      if (!S.classDetails[cacheKey]) {
        S.classDetails[cacheKey] = await apiFetch(ext ? `/classes/${ext}/${name}` : `/classes/${name}`);
      }
      renderNodeDetail(S.classDetails[cacheKey], 'class', name);
    } else if (nodeType === 'object') {
      const ext = node.data('extension');
      const cacheKey = ext ? `${ext}/${name}` : name;
      if (!S.objectDetails[cacheKey]) {
        const obj = S.objects.find(o => o.name === name && (o.extension || null) === ext);
        const path = obj && obj.extension ? `/objects/${obj.extension}/${name}` : `/objects/${name}`;
        S.objectDetails[cacheKey] = await apiFetch(path);
      }
      renderNodeDetail(S.objectDetails[cacheKey], 'object', name);
    }
  } catch (e) {
    document.getElementById('detail-inner').innerHTML =
      `<div class="detail-content"><p style="color:var(--error-color)">${e.message}</p></div>`;
  }
}

function clearSelection() {
  S.cy && S.cy.elements().removeClass('faded highlighted');
  clearDetailPanel();
}

// Navigate on double-click
function initNodeNavigation() {
  S.cy.on('dbltap', 'node', function(e) {
    const d = e.target.data();
    if (d.nodeType === 'object' && d.name) {
      const params = new URLSearchParams(window.location.search);
      params.delete('class');
      params.set('object', d.name);
      window.location.search = '?' + params.toString();
    } else if (d.nodeType === 'class' && d.name) {
      const params = new URLSearchParams(window.location.search);
      params.delete('object');
      params.set('class', d.name);
      window.location.search = '?' + params.toString();
    } else if (d.nodeType === 'category' && d.name) {
      const params = new URLSearchParams(window.location.search);
      params.delete('class');
      params.delete('object');
      params.set('category', d.name);
      window.location.search = '?' + params.toString();
    }
  });
}

// ─── Detail panel rendering ──────────────────────────────────────────────────

function setDetailLoading(node) {
  document.getElementById('detail-inner').innerHTML = `
    <div class="detail-content">
      <span class="type-badge ${node.data('nodeType')}">${node.data('nodeType')}</span>
      <h2>${node.data('caption') || node.data('name')}</h2>
      <p style="color:var(--text-muted)">Loading…</p>
    </div>`;
}

function clearDetailPanel() {
  document.getElementById('detail-inner').innerHTML = `
    <div class="detail-empty">
      <div class="icon">◈</div>
      <div class="hint">Click a node to see its attributes</div>
    </div>`;
}

function renderCategoryDetail(node) {
  const { uid, caption, name } = node.data();
  const classes = S.classes.filter(c => {
    const cu = c.category_uid || (c.uid ? Math.floor(c.uid / 1000) : null);
    return cu === uid;
  });

  document.getElementById('detail-inner').innerHTML = `
    <div class="detail-content">
      <div class="detail-header">
        <span class="type-badge category">Category</span>
        <h2>${caption || name}</h2>
        <div class="detail-meta">${classes.length} event classes</div>
      </div>
      <div class="attr-section">
        <div class="attr-list">
          ${classes.map(c => `
            <div class="attr-item optional class-link" onclick="focusNode('cls_${c.name}')">
              <div class="attr-name">${c.caption || c.name}</div>
            </div>
          `).join('')}
        </div>
      </div>
    </div>`;
}

function renderNodeDetail(data, type, nodeName) {
  const attrs = data.attributes || {};
  const groups = { required: [], recommended: [], optional: [] };

  for (const [n, a] of Object.entries(attrs)) {
    const req = (a.requirement || 'optional').toLowerCase();
    (groups[req] || groups.optional).push({ attrName: n, ...a });
  }

  const caption = data.caption || data.name || '';
  const isCurrent = (type === 'class' && nodeName === SCOPE_CLASS) || (type === 'object' && nodeName === SCOPE_OBJECT);
  const navHint = !isCurrent ? `<p style="font-size:11px;color:var(--text-muted);margin-top:8px">Double-click to explore this ${type}</p>` : '';

  document.getElementById('detail-inner').innerHTML = `
    <div class="detail-content">
      <div class="detail-header">
        <span class="type-badge ${type}">${type === 'class' ? 'Class' : 'Object'}</span>
        <h2>${caption}</h2>
        ${navHint}
      </div>
      ${attrSection('required', groups.required, 'Required')}
      ${attrSection('recommended', groups.recommended, 'Recommended')}
      ${attrSection('optional', groups.optional, 'Optional')}
    </div>`;
}

function attrSection(key, items, label) {
  if (!items.length) return '';
  return `
    <div class="attr-section">
      <div class="attr-section-header" onclick="this.parentElement.classList.toggle('collapsed')">
        <span class="req-dot ${key}"></span>
        <h3>${label}</h3>
        <span class="attr-count">${items.length}</span>
        <span class="chevron">▾</span>
      </div>
      <div class="attr-list">
        ${items.map(a => `
          <div class="attr-item ${key}">
            <div class="attr-name">
              ${a.attrName}
              <span class="attr-type">${a.object_type || a.type_name || a.type || ''}</span>
            </div>
          </div>
        `).join('')}
      </div>
    </div>`;
}

function focusNode(id) {
  if (!S.cy) return;
  const n = S.cy.$(`#${id}`);
  if (!n.length) return;
  S.cy.animate({ center: { eles: n }, zoom: 1.4 }, { duration: 350 });
  onNodeClick(n);
}

// ─── Controls ────────────────────────────────────────────────────────────────

function fitGraph() {
  if (S.cy) S.cy.fit(undefined, 30);
}

function relayout(name) {
  if (!S.cy) return;
  S.cy.layout({ ...layoutOpts(name), animate: true, animationDuration: 400 }).run();
}

function onSearch(q) {
  if (!S.cy) return;
  S.search = q;
  q = q.toLowerCase().trim();
  if (!q) { S.cy.elements().removeClass('faded highlighted'); return; }
  S.cy.elements().addClass('faded');
  const matched = S.cy.nodes().filter(n => {
    const d = n.data();
    return (d.name && d.name.includes(q)) || (d.caption && d.caption.toLowerCase().includes(q));
  });
  matched.removeClass('faded').addClass('highlighted');
  matched.connectedEdges().removeClass('faded');
  matched.connectedEdges().connectedNodes().removeClass('faded');
}

function togglePanel() {
  const panel = document.getElementById('detail-panel');
  panel.classList.toggle('collapsed');
  const btn = document.getElementById('panel-toggle');
  btn.textContent = panel.classList.contains('collapsed') ? '«' : '»';
}

function setStatus(t) {
  document.getElementById('status').textContent = t;
}

// ─── Scoped graph builders ───────────────────────────────────────────────────

async function buildScopedClassGraph(className) {
  const clsDetail = await apiFetch(`/classes/${className}`);
  S.classDetails[className] = clsDetail;

  const els = [];
  const addedIds = new Set();

  function addNode(id, data) { if (!addedIds.has(id)) { addedIds.add(id); els.push({ data: { id, ...data } }); } }
  function addEdge(id, src, tgt, data) { if (!addedIds.has(id)) { addedIds.add(id); els.push({ data: { id, source: src, target: tgt, ...data } }); } }

  const cls = S.classes.find(c => c.name === className);
  const catUid = cls ? (cls.category_uid || (cls.uid ? Math.floor(cls.uid / 1000) : null)) : null;

  // Center class node
  addNode(`cls_${className}`, {
    label: (clsDetail.caption || className).replace(/ /g, '\n'),
    type: 'class', nodeType: 'class', name: className,
    caption: clsDetail.caption || className,
    description: clsDetail.description,
    color: CAT_CLASS_COLOR[catUid] || '#8b949e',
  });

  // Parent category
  if (catUid) {
    const cat = S.categories.find(c => c.uid === catUid);
    if (cat) {
      addNode(`cat_${catUid}`, {
        label: (cat.caption || cat.name).replace(/ /g, '\n'),
        type: 'category', nodeType: 'category', name: cat.name,
        caption: cat.caption || cat.name, uid: catUid,
        color: CAT_COLOR[catUid] || '#374151',
      });
      addEdge(`e_cc_${className}`, `cat_${catUid}`, `cls_${className}`, { type: 'contains' });

    }
  }

  // Parent class (extends)
  if (clsDetail.extends && clsDetail.extends !== 'base_event') {
    const parentCls = S.classes.find(c => c.name === clsDetail.extends);
    if (parentCls) {
      const pCatUid = parentCls.category_uid || (parentCls.uid ? Math.floor(parentCls.uid / 1000) : null);
      addNode(`cls_${parentCls.name}`, {
        label: (parentCls.caption || parentCls.name).replace(/ /g, '\n'),
        type: 'class', nodeType: 'class', name: parentCls.name,
        caption: parentCls.caption || parentCls.name,
        color: CAT_CLASS_COLOR[pCatUid] || '#8b949e',
      });
      addEdge(`e_ext_${className}`, `cls_${parentCls.name}`, `cls_${className}`, { type: 'extends' });
    }
  }

  // Object-type attributes as connected object nodes
  if (clsDetail.attributes) {
    const addedObjs = new Set();
    for (const [key, attr] of Object.entries(clsDetail.attributes)) {
      if (attr.object_type) {
        const objName = attr.object_type;
        if (!addedObjs.has(objName)) {
          addedObjs.add(objName);
          addNode(`obj_${objName}`, {
            label: objName.replace(/_/g, '\n'),
            type: 'object', nodeType: 'object', name: objName,
            caption: objName,
          });
        }
        addEdge(`e_attr_${className}_${key}`, `cls_${className}`, `obj_${objName}`, {
          type: 'has_attr', label: key, requirement: attr.requirement || 'optional',
        });
      }
    }
  }

  return els;
}

async function buildScopedObjectGraph(objectName) {
  const objDetail = await apiFetch(`/objects/${objectName}`);
  S.objectDetails[objectName] = objDetail;

  const els = [];
  const addedIds = new Set();

  function addNode(id, data) { if (!addedIds.has(id)) { addedIds.add(id); els.push({ data: { id, ...data } }); } }
  function addEdge(id, src, tgt, data) { if (!addedIds.has(id)) { addedIds.add(id); els.push({ data: { id, source: src, target: tgt, ...data } }); } }

  // Center object node
  addNode(`obj_${objectName}`, {
    label: (objDetail.caption || objectName).replace(/ /g, '\n'),
    type: 'object', nodeType: 'object', name: objectName,
    caption: objDetail.caption || objectName,
    description: objDetail.description,
  });

  // Parent object (extends)
  if (objDetail.extends && objDetail.extends !== 'object') {
    const parentObj = S.objects.find(o => o.name === objDetail.extends);
    if (parentObj) {
      addNode(`obj_${parentObj.name}`, {
        label: (parentObj.caption || parentObj.name).replace(/ /g, '\n'),
        type: 'object', nodeType: 'object', name: parentObj.name,
        caption: parentObj.caption || parentObj.name,
      });
      addEdge(`e_ext_${objectName}`, `obj_${parentObj.name}`, `obj_${objectName}`, { type: 'extends' });
    }
  }

  // Child objects that extend this one
  const children = S.objects.filter(o => o.extends === objectName);
  for (const child of children) {
    addNode(`obj_${child.name}`, {
      label: (child.caption || child.name).replace(/ /g, '\n'),
      type: 'object', nodeType: 'object', name: child.name,
      caption: child.caption || child.name,
    });
    addEdge(`e_ext_${child.name}`, `obj_${objectName}`, `obj_${child.name}`, { type: 'extends' });
  }

  // Object-type attributes as nested object nodes
  if (objDetail.attributes) {
    const addedObjs = new Set();
    for (const [key, attr] of Object.entries(objDetail.attributes)) {
      if (attr.object_type) {
        const childName = attr.object_type;
        if (!addedObjs.has(childName)) {
          addedObjs.add(childName);
          addNode(`obj_${childName}`, {
            label: childName.replace(/_/g, '\n'),
            type: 'object', nodeType: 'object', name: childName,
            caption: childName,
          });
        }
        addEdge(`e_attr_${objectName}_${key}`, `obj_${objectName}`, `obj_${childName}`, {
          type: 'has_attr', label: key, requirement: attr.requirement || 'optional',
        });
      }
    }
  }

  return els;
}

async function buildScopedCategoryGraph(categoryName) {
  const cat = S.categories.find(c => c.name === categoryName);
  if (!cat) return [];

  const els = [];
  const addedIds = new Set();

  function addNode(id, data) { if (!addedIds.has(id)) { addedIds.add(id); els.push({ data: { id, ...data } }); } }
  function addEdge(id, src, tgt, data) { if (!addedIds.has(id)) { addedIds.add(id); els.push({ data: { id, source: src, target: tgt, ...data } }); } }

  // Category node
  addNode(`cat_${cat.uid}`, {
    label: (cat.caption || cat.name).replace(/ /g, '\n'),
    type: 'category', nodeType: 'category', name: cat.name,
    caption: cat.caption || cat.name, uid: cat.uid,
    color: CAT_COLOR[cat.uid] || '#374151',
  });

  // All classes in this category
  const classMap = new Map(S.classes.map(c => [c.name, c]));
  const catClasses = S.classes.filter(c => {
    const cu = c.category_uid || (c.uid ? Math.floor(c.uid / 1000) : null);
    return cu === cat.uid;
  });

  for (const cls of catClasses) {
    addNode(`cls_${cls.name}`, {
      label: (cls.caption || cls.name).replace(/ /g, '\n'),
      type: 'class', nodeType: 'class', name: cls.name,
      caption: cls.caption || cls.name,
      color: CAT_CLASS_COLOR[cat.uid] || '#8b949e',
    });

    // Check if class extends another class in the same category
    const parentCls = cls.extends ? classMap.get(cls.extends) : null;
    const parentCatUid = parentCls
      ? (parentCls.category_uid || (parentCls.uid ? Math.floor(parentCls.uid / 1000) : null))
      : null;

    if (parentCls && parentCatUid === cat.uid) {
      addEdge(`e_ext_${cls.name}`, `cls_${cls.extends}`, `cls_${cls.name}`, { type: 'extends' });
    } else {
      addEdge(`e_cc_${cls.name}`, `cat_${cat.uid}`, `cls_${cls.name}`, { type: 'contains' });
    }
  }

  return els;
}

// ─── Schema loading & init ───────────────────────────────────────────────────

async function loadSchema() {
  try {
    const [catData, clsData, objData] = await Promise.all([
      apiFetch('/categories'),
      apiFetch('/classes'),
      apiFetch('/objects'),
    ]);

    S.categories = normCats(catData);
    S.classes = normClasses(clsData);
    S.objects = normObjects(objData);

    S.categories.sort((a, b) => a.uid - b.uid);
    S.classes.sort((a, b) => (a.uid || 0) - (b.uid || 0));
    S.objects.sort((a, b) => (a.name || '').localeCompare(b.name || ''));

    // Hide loading overlay
    document.getElementById('loading-overlay').style.display = 'none';

    // Build a focused graph for the scoped entity
    let els;
    if (SCOPE_CLASS) {
      els = await buildScopedClassGraph(SCOPE_CLASS);
    } else if (SCOPE_OBJECT) {
      els = await buildScopedObjectGraph(SCOPE_OBJECT);
    } else if (SCOPE_CATEGORY) {
      els = await buildScopedCategoryGraph(SCOPE_CATEGORY);
    } else {
      els = buildEventEls();
    }

    initCy(els, 'cose');
    initNodeNavigation();

    const nodeCount = els.filter(e => !e.data.source).length;
    setStatus(`${nodeCount} nodes`);

    // Auto-select center node
    if (SCOPE_CLASS || SCOPE_OBJECT) {
      setTimeout(() => {
        const targetId = SCOPE_CLASS ? `cls_${SCOPE_CLASS}` : `obj_${SCOPE_OBJECT}`;
        const targetNode = S.cy.getElementById(targetId);
        if (targetNode.length) {
          onNodeClick(targetNode);
        }
      }, 400);
    }

  } catch (err) {
    document.getElementById('loading-overlay').innerHTML = `
      <div style="text-align:center;padding:24px;color:var(--text-muted)">
        <p style="color:var(--error-color);font-weight:600">Could not load schema</p>
        <p style="font-size:12px;margin-top:8px">${err.message}</p>
        <button onclick="loadSchema()" style="margin-top:12px;padding:6px 14px;background:var(--accent-color);color:#fff;border:none;border-radius:var(--radius-md);cursor:pointer">Retry</button>
      </div>`;
  }
}

loadSchema();
