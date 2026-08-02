// 个人工作台 PWA —— 前端逻辑
// 数据优先级：./data.json（若用本地服务器/部署）→ 内置示例数据（双击 file:// 也能跑）

const FALLBACK_DATA = {
  kpi: { skills: 44, automations: 3, models: 6, memory: 128 },
  skills: [
    { name: "my-workbench", desc: "个人工作台面板", cmd: "打开我的工作台" },
    { name: "obsidian", desc: "笔记与知识库管理", cmd: "整理我的 vault" },
    { name: "ollama-local-multimodal", desc: "本机多模态模型", cmd: "本地看图问答" },
    { name: "wb-ai-radar", desc: "AI 资讯与趋势", cmd: "今天 AI 圈有什么" },
    { name: "prompt-forge", desc: "把模糊需求变成提示词", cmd: "帮我写个提示词" },
    { name: "pdf", desc: "PDF 处理", cmd: "处理这个 PDF" }
  ],
  guide: [
    "回顾昨天 AI Agent 学习方案的笔记",
    "跑一次 wb-ai-radar 看今日 AI 热点",
    "把新想法用 prompt-forge 固化成提示词"
  ],
  status: {
    skillsLastUpdate: "2026-08-02",
    automations: [
      { name: "每日 AI 早报", next: "明天 08:00" },
      { name: "每周复盘", next: "周日 22:00" },
      { name: "Ollama 自启", status: "运行中" }
    ],
    models: [
      { name: "qwen2.5-text-local", type: "本机" },
      { name: "qwen2.5-vl-local", type: "本机" },
      { name: "GLM-4.7-Flash", type: "云端" }
    ],
    memoryLastUpdate: "2026-08-02"
  }
};

async function loadData() {
  try {
    const res = await fetch("./data.json", { cache: "no-store" });
    if (!res.ok) throw new Error("no data");
    return await res.json();
  } catch (e) {
    return FALLBACK_DATA;
  }
}

function toast(msg) {
  const t = document.getElementById("toast");
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toast._t);
  toast._t = setTimeout(() => (t.hidden = true), 1600);
}

async function copy(text) {
  try {
    await navigator.clipboard.writeText(text);
    toast("已复制：" + text);
  } catch (e) {
    toast("复制失败，请手动选择：" + text);
  }
}

function renderKpi(d) {
  const order = [
    ["skills", "Skills"],
    ["automations", "自动化"],
    ["models", "模型"],
    ["memory", "记忆条目"]
  ];
  document.getElementById("kpiBar").innerHTML = order
    .map(
      ([k, label]) =>
        `<div class="kpi"><div class="num">${d.kpi[k] ?? 0}</div><div class="label">${label}</div></div>`
    )
    .join("");
}

function renderSkills(d) {
  document.getElementById("skillCards").innerHTML = (d.skills || [])
    .map(
      (s, i) => `
      <div class="card" data-i="${i}">
        <div class="name">${s.name}</div>
        <div class="desc">${s.desc || ""}</div>
        <div class="hint">点击复制指令 →</div>
      </div>`
    )
    .join("");
  document.querySelectorAll("#skillCards .card").forEach((el) => {
    el.addEventListener("click", () => copy(d.skills[+el.dataset.i].cmd || ""));
  });
}

function renderGuide(d) {
  document.getElementById("guideList").innerHTML = (d.guide || [])
    .map(
      (g, i) => `
      <li>
        <input type="checkbox" data-i="${i}" />
        <span>${g}</span>
      </li>`
    )
    .join("");
  document.querySelectorAll("#guideList input").forEach((cb) => {
    cb.addEventListener("change", (e) => {
      e.target.closest("li").classList.toggle("done", e.target.checked);
    });
  });
}

function renderStatus(d) {
  const s = d.status || {};
  const autoRows = (s.automations || [])
    .map(
      (a) =>
        `<div class="row"><span class="k">${a.name}</span><span class="v">${a.next || a.status || ""}</span></div>`
    )
    .join("");
  const modelRows = (s.models || [])
    .map(
      (m) =>
        `<div class="row"><span class="k">${m.name}</span><span class="v"><span class="tag ${
          m.type === "本机" ? "local" : "cloud"
        }">${m.type}</span></span></div>`
    )
    .join("");
  document.getElementById("statusBoard").innerHTML = `
    <div class="panel">
      <h3>自动化</h3>
      ${autoRows || '<div class="row"><span class="k">暂无</span></div>'}
    </div>
    <div class="panel">
      <h3>模型</h3>
      ${modelRows || '<div class="row"><span class="k">暂无</span></div>'}
    </div>
    <div class="panel">
      <h3>数据更新</h3>
      <div class="row"><span class="k">Skills</span><span class="v">${s.skillsLastUpdate || "-"}</span></div>
      <div class="row"><span class="k">记忆</span><span class="v">${s.memoryLastUpdate || "-"}</span></div>
    </div>`;
}

(async () => {
  const d = await loadData();
  renderKpi(d);
  renderSkills(d);
  renderGuide(d);
  renderStatus(d);

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("sw.js").catch(() => {});
  }

  // PWA 安装按钮
  let deferred = null;
  window.addEventListener("beforeinstallprompt", (e) => {
    e.preventDefault();
    deferred = e;
    document.getElementById("installBtn").hidden = false;
  });
  document.getElementById("installBtn").addEventListener("click", async () => {
    if (!deferred) return;
    deferred.prompt();
    await deferred.userChoice;
    document.getElementById("installBtn").hidden = true;
  });
})();
