// 个人工作台 · 数据驱动渲染 + PWA
(function () {
  "use strict";

  function esc(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
  function escAttr(s) {
    return esc(s).replace(/'/g, "&#39;").replace(/"/g, "&quot;");
  }

  // ---------- 复制指令（降级） ----------
  function robustCopy(t, hintId, okMsg, failMsg) {
    var set = function (ok) {
      var h = document.getElementById(hintId);
      if (h) h.textContent = ok ? ("✓ " + okMsg) : ("⚠ " + failMsg);
    };
    var fb = function () {
      try {
        var ta = document.createElement("textarea");
        ta.value = t; ta.style.position = "fixed"; ta.style.top = "-1000px";
        document.body.appendChild(ta); ta.focus(); ta.select();
        var ok = document.execCommand("copy"); document.body.removeChild(ta); set(ok);
      } catch (e) { set(false); }
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(t).then(function () { set(true); }).catch(function () { fb(); });
    } else { fb(); }
  }
  function cmd(el) {
    var c = el.getAttribute("data-cmd");
    var box = document.getElementById("cmdbox");
    box.value = c; box.focus(); box.select();
    robustCopy(c, "hint", "已复制，到对话框 Ctrl+V 粘贴并发送", "复制被拦截，请手动选中上方框 Ctrl+C");
  }
  function cmdtext(t) {
    var box = document.getElementById("cmdbox");
    box.value = t; box.focus(); box.select();
    robustCopy(t, "hint", "已复制，到对话框 Ctrl+V 粘贴并发送", "复制被拦截，请手动选中上方框 Ctrl+C");
  }
  function inspire(t) {
    var box = document.getElementById("inspiretext");
    document.getElementById("insbox").style.display = "block";
    box.value = t; box.focus(); box.select();
    robustCopy(t, "inshint", "已复制，到下方对话框 Ctrl+V 粘贴并发送", "复制被拦截，请手动选中上面文字 Ctrl+C 再粘贴发送");
  }
  function copyInspire() {
    var box = document.getElementById("inspiretext");
    box.focus(); box.select();
    robustCopy(box.value, "inshint", "已复制，到下方对话框 Ctrl+V 粘贴并发送", "复制被拦截，请手动选中上面文字 Ctrl+C 再粘贴发送");
  }
  window.cmd = cmd; window.cmdtext = cmdtext; window.inspire = inspire; window.copyInspire = copyInspire;

  // ---------- 交互 ----------
  function filt() {
    var q = document.getElementById("q").value.toLowerCase();
    var any = false;
    document.querySelectorAll("#skills .cat").forEach(function (cat) {
      var n = 0;
      cat.querySelectorAll(".skill").forEach(function (it) {
        var hit = (q === "" || it.textContent.toLowerCase().indexOf(q) >= 0);
        it.style.display = hit ? "" : "none";
        if (hit) n++;
      });
      if (q !== "") {
        cat.style.display = (n === 0) ? "none" : "";
        if (n > 0) cat.classList.add("open");
      }
      if (n > 0) any = true;
    });
    var e = document.getElementById("sempty");
    if (e) e.style.display = (q !== "" && !any) ? "block" : "none";
  }
  function toggleCat(h) { h.parentNode.classList.toggle("open"); }
  function switchTab(id) {
    document.querySelectorAll(".tab").forEach(function (t) {
      t.classList.toggle("active", t.getAttribute("data-tab") === id);
    });
    document.querySelectorAll(".tabpane").forEach(function (p) {
      p.classList.toggle("active", p.id === "pane-" + id);
    });
  }
  window.filt = filt; window.toggleCat = toggleCat; window.switchTab = switchTab;

  // ---------- 渲染 ----------
  function renderKPI(d) {
    var k = d.kpi, disk = (d.status && d.status.disk) || {};
    var items = [
      { c: "kpi-blue", i: "📚", v: k.knowledge, l: "知识库文件" },
      { c: "kpi-green", i: "⚙️", v: k.automations, l: "定时任务" },
      { c: "kpi-purple", i: "💾", v: (disk.D ? disk.D.free + "G" : "—"), l: "磁盘可用 · 共 " + (disk.D ? disk.D.total + "G" : "—") },
      { c: "kpi-amber", i: "🚀", v: k.skills, l: "已装 Skills" },
    ];
    document.getElementById("kpis").innerHTML = items.map(function (x) {
      return '<div class="kpi ' + x.c + '"><div class="ki">' + x.i + '</div><div><div class="kv">' + x.v + '</div><div class="kl">' + x.l + "</div></div></div>";
    }).join("");
  }

  function renderQuick(d) {
    document.getElementById("quickbar").innerHTML = (d.quickActions || []).map(function (q) {
      return '<button class="qb" onclick="cmdtext(' + "'" + escAttr(q.cmd) + "'" + ')">' + q.icon + " " + esc(q.label) + "</button>";
    }).join("");
  }

  function renderSkills(skills) {
    var byCat = {};
    skills.forEach(function (s) { (byCat[s.category] = byCat[s.category] || []).push(s); });
    var html = "";
    Object.keys(byCat).forEach(function (cat) {
      html += '<div class="cat open"><div class="cat-h" onclick="toggleCat(this)"><span class="ci">📦</span>' + esc(cat) +
        '<span class="cc">' + byCat[cat].length + '</span><span class="car">▶</span></div><div class="cat-b">';
      byCat[cat].forEach(function (s) {
        html += '<span class="skill" onclick="cmd(this)" data-cmd="' + escAttr(s.cmd) + '" title="' + escAttr(s.desc) + '">' +
          '<span class="sn">' + esc(s.name) + '</span><span class="sd">' + esc(s.desc) + "</span></span>";
      });
      html += "</div></div>";
    });
    return html;
  }

  function renderSessions(sessions) {
    var groups = { "今天": [], "昨天": [], "更早": [] };
    sessions.forEach(function (s) { (groups[s.group] = groups[s.group] || []).push(s); });
    var html = "";
    ["今天", "昨天", "更早"].forEach(function (g) {
      if (!groups[g].length) return;
      html += '<div class="grp open"><div class="grp-h" onclick="toggleCat(this)"><span class="ci">🟢</span>' + g +
        '<span class="cc">' + groups[g].length + '</span><span class="car">▶</span></div><div class="grp-b">';
      groups[g].forEach(function (s) {
        var badge = s.status === "working" ? '<span class="badge on">进行中</span>' : "";
        html += '<div class="auto sess" onclick="cmdtext(' + "'回顾并继续这个会话：" + escAttr(s.title) + "'" + ')"><b>' +
          esc(s.title) + '</b><span class="meta">' + s.updated + " " + badge + "</span></div>";
      });
      html += "</div></div>";
    });
    return html;
  }

  function renderHeat(heat) {
    var total = heat.reduce(function (a, b) { return a + b.count; }, 0);
    var html = '<div class="heat"><div class="heat-t">📈 近 17 周会话活跃 · 合计 ' + total + ' 条记录</div><div class="heat-g">';
    heat.forEach(function (h) {
      var lvl = h.count === 0 ? "l0" : (h.count <= 2 ? "l1" : (h.count <= 5 ? "l2" : "l3"));
      html += '<span class="hc ' + lvl + '" title="' + h.date + " : " + h.count + ' 个会话"></span>';
    });
    html += '</div><div class="heat-lg"><span class="hc l1"></span>少 <span class="hc l2"></span>中 <span class="hc l3"></span>多</div></div>';
    return html;
  }

  function renderCap(d) {
    var skillsHtml = renderSkills(d.skills);
    var sessHtml = renderSessions(d.sessions.recent);
    var heatHtml = renderHeat(d.sessions.heatmap);
    var guideHtml = (d.guide || []).map(function (g) {
      return '<li' + (g.indexOf("⚠") >= 0 ? ' class="warn"' : "") + ">" + esc(g) + "</li>";
    }).join("");
    var inspireCmd = "根据我的工作台现状生成今日灵感：已装 " + d.kpi.skills + " 个 skill，知识库 " + d.kpi.knowledge +
      " 个文件，模型 " + d.kpi.models + " 个（本机 " + ((d.status.localModels || []).length) + "）。请给我：① 1-2 个今天可以动手的小任务灵感；② 一条 AI agent 学习路径（结合我已装的 skill）；③ 一个值得关注的 AI 趋势。";
    document.getElementById("col-cap").innerHTML =
      '<div class="card"><h2><span class="ic">🚀</span>① 能力速达（点击复制调用指令）</h2>' +
        '<input id="q" placeholder="搜索 skill 名称或描述…" oninput="filt()">' +
        '<textarea id="cmdbox" rows="2" placeholder="点击上方 skill，指令会出现在这里（也可直接编辑/粘贴）"></textarea>' +
        '<div id="hint"></div><div id="sempty" class="empty" style="display:none">没有匹配的 skill</div>' +
        '<div id="skills">' + skillsHtml + "</div></div>" +
      '<div class="card"><h2><span class="ic">🧭</span>⑤ 今日引导 / 灵感 / 学 Agent</h2>' +
        '<ul class="guide">' + guideHtml + "</ul>" +
        '<div style="margin-top:12px"><button class="btn" onclick="inspire(' + "'" + escAttr(inspireCmd) + "'" + ')">💡 给我灵感（AI 生成）</button>' +
        '<div id="insbox"><textarea id="inspiretext" rows="5" placeholder="点击上方按钮，AI 灵感指令会出现在这里；可编辑，复制后到对话框 Ctrl+V 粘贴并发送"></textarea>' +
        '<div style="margin-top:6px"><button class="btn-sm" onclick="copyInspire()">📋 复制指令</button><span id="inshint"></span></div></div></div></div>' +
      '<div class="card"><h2><span class="ic">💬</span>⑥ 近期会话 / 任务流</h2>' + sessHtml + heatHtml + "</div>" +
      '<div class="card"><h2><span class="ic">📡</span>⑧ AI 趋势 / 学习流</h2>' +
        '<div style="margin-top:10px;display:flex;gap:8px;flex-wrap:wrap">' +
        '<button class="btn" onclick="cmdtext(' + "'生成今日 AI 日报（中文）：最新模型 / 工具 / 趋势'" + ')">🗞️ 今日 AI 日报</button>' +
        '<button class="btn-sm" onclick="cmdtext(' + "'检索最近 30 天 AI 趋势，输出一份研究笔记'" + ')">🔭 趋势研究</button></div></div>';
  }

  function renderOv(d) {
    var st = d.status;
    var modelsHtml = (st.models || []).map(function (m) {
      return '<div class="model">🔧 ' + esc(m.name) + ' <span style="color:var(--sub);font-size:11px">(' + m.type + ")</span></div>";
    }).join("");
    var mcpHtml = (st.mcp || []).map(function (m) { return esc(m); }).join(" · ");
    var disk = st.disk || {};
    var localHtml = (st.localModels || []).map(function (m) { return '<div class="model">🧠 ' + esc(m) + "</div>"; }).join("");
    var autoHtml = (st.automations || []).map(function (a) {
      var badge = a.status === "ACTIVE" || a.status === "active" ? '<span class="badge on">ACTIVE</span>' : '<span class="badge off">' + esc(a.status) + "</span>";
      return '<div class="auto">' + badge + "<b>" + esc(a.name) + '</b><span class="meta">recurring · 下次 ' + esc(a.next || "—") + "</span></div>";
    }).join("") || '<div class="empty">暂无自动化任务</div>';
    var kb = d.knowledge || { total: 0, types: {}, files: [] };
    var kbTypes = Object.keys(kb.types || {}).map(function (t) { return t + " " + kb.types[t]; }).join(" · ");
    var kbHtml = (kb.files || []).map(function (f) {
      return '<div class="auto"><b>' + esc(f.name) + '</b><span class="meta">' + esc(f.mtime) + "</span></div>";
    }).join("");

    document.getElementById("col-ov").innerHTML =
      '<div class="card"><h2><span class="ic">📊</span>③ 个人状态看板</h2>' +
        '<div style="margin:2px 0 8px;color:var(--accent2);font-size:13px">已接入模型（' + (st.models || []).length + "）</div>" + modelsHtml +
        '<div style="margin:14px 0 6px;color:var(--accent2);font-size:13px">集成与资源</div>' +
        '<div class="res">' +
        '<div class="res-i"><span class="rk">MCP 集成</span><span class="rv">' + (st.mcp || []).length + '</span><span class="rn">' + esc(mcpHtml) + "</span></div>" +
        '<div class="res-i"><span class="rk">记忆库</span><span class="rv">' + d.kpi.memory + '</span><span class="rn">个文件</span></div>' +
        '<div class="res-i"><span class="rk">磁盘 C:</span><span class="rv">' + (disk.C ? disk.C.free + "G" : "—") + '</span><span class="rn">共 ' + (disk.C ? disk.C.total + "G" : "—") + "</span></div>" +
        '<div class="res-i"><span class="rk">磁盘 D:</span><span class="rv">' + (disk.D ? disk.D.free + "G" : "—") + '</span><span class="rn">磁盘可用 · 共 ' + (disk.D ? disk.D.total + "G" : "—") + "</span></div>" +
        "</div></div>" +
      '<div class="card"><h2><span class="ic">🔧</span>⑦ 环境体检台</h2>' +
        (localHtml ? '<div style="margin:8px 0 4px;color:var(--accent2);font-size:13px">本地模型（' + (st.localModels || []).length + "）</div>" + localHtml : '<div class="empty">无本地模型</div>') +
        '<div class="res" style="margin-top:10px">' +
        '<div class="res-i"><span class="rk">C 盘剩余</span><span class="rv">' + (disk.C ? disk.C.free + "G" : "—") + '</span><span class="rn">共 ' + (disk.C ? disk.C.total + "G" : "—") + "</span></div>" +
        '<div class="res-i"><span class="rk">运行时</span><span class="rv" style="font-size:13px">' + esc(st.runtime || "—") + '</span><span class="rn">Python / Node</span></div>' +
        "</div></div>" +
      '<div class="card"><h2><span class="ic">⚙️</span>② 自动化与任务编排</h2>' + autoHtml +
        '<div style="margin-top:10px"><button class="btn" onclick="cmdtext(' + "'新建定时任务：频率（如每周一10点）+ 工作区 + 任务描述'" + ')">➕ 新建定时任务</button></div></div>' +
      '<div class="card"><h2><span class="ic">📚</span>④ 内容与知识生产</h2>' +
        '<div style="margin-bottom:6px;color:var(--accent2);font-size:13px">知识库类型：' + esc(kbTypes) + "</div>" + kbHtml +
        '<div style="margin-top:10px;display:flex;gap:8px;flex-wrap:wrap">' +
        '<button class="btn" onclick="cmdtext(' + "'在 knowledge-base/ 新建一篇笔记，主题：'" + ')">➕ 新建笔记</button>' +
        '<button class="btn" onclick="cmdtext(' + "'用 video-cangjie-distill 把以下视频转成 skill：'" + ')">🎬 蒸馏视频</button>' +
        '<button class="btn-sm" onclick="cmdtext(' + "'在 knowledge-base/ 搜索：'" + ')">🔍 搜知识库</button></div></div>';
  }

  function render(d) {
    document.getElementById("snap").textContent = "📸 快照 · " + (d.generatedAt || "—");
    renderKPI(d);
    renderQuick(d);
    renderCap(d);
    renderOv(d);
  }

  // ---------- 启动 ----------
  fetch("data.json", { cache: "no-store" })
    .then(function (r) { return r.json(); })
    .then(function (d) { render(d); })
    .catch(function (e) {
      document.getElementById("col-cap").innerHTML = '<div class="card"><h2>⚠️ 数据加载失败</h2><div class="empty">无法读取 data.json：' + esc(e) + "。请确认已运行 export_data.py 生成数据。</div></div>";
    });

  if ("serviceWorker" in navigator) {
    window.addEventListener("load", function () {
      navigator.serviceWorker.register("sw.js").catch(function () {});
    });
  }
})();
