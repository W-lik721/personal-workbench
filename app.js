// 个人工作台 · 数据驱动渲染 + PWA
(function () {
  "use strict";

  // 分类中英文映射（上游英文 kebab-case，未命中回退原值）
  var CAT_ZH = {
    "academic-writing": "学术写作",
    "content": "内容创作",
    "document-generation": "文档生成",
    "通用能力": "通用能力"
  };
  function catLabel(c) { return CAT_ZH[c] || c; }

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
    if (q !== "") switchTab("cap");
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
  function openHeat(span) {
    var date = span.getAttribute("data-date");
    var count = span.getAttribute("data-count");
    var titles = (span.getAttribute("data-titles") || "").split("\n").filter(Boolean);
    document.getElementById("heat-detail-date").textContent = date + " · " + count + " 个会话";
    var body = document.getElementById("heat-detail-body");
    body.innerHTML = titles.length
      ? titles.map(function (t) {
          return '<div class="hdi" onclick="cmdtext(' + "'回顾并继续这个会话：" + escAttr(t) + "'" + ')">' + esc(t) + '<span class="hd-arrow">›</span></div>';
        }).join("")
      : '<div class="empty">这天没有会话记录</div>';
    document.getElementById("heat-detail").style.display = "flex";
  }
  function closeHeat() { document.getElementById("heat-detail").style.display = "none"; }

  // ---------- 我的速记（localStorage，纯前端） ----------
  function notesLoad() {
    try { return JSON.parse(localStorage.getItem("wb_notes") || "[]"); } catch (e) { return []; }
  }
  function notesSave(list) { try { localStorage.setItem("wb_notes", JSON.stringify(list)); } catch (e) {} }
  function renderNotes() {
    var ul = document.getElementById("notesList");
    if (!ul) return;
    var list = notesLoad();
    if (!list.length) { ul.innerHTML = '<li class="empty">还没有速记，记一笔吧～</li>'; return; }
    ul.innerHTML = list.map(function (n, i) {
      return '<li class="note"><span class="nt">' + esc(n.text) + '</span><button class="nd" onclick="delNote(' + i + ')" title="删除">✕</button></li>';
    }).join("");
  }
  function addNote() {
    var ta = document.getElementById("noteInput");
    var t = (ta.value || "").trim();
    var h = document.getElementById("notesHint");
    if (!t) { if (h) h.textContent = "先写点内容"; return; }
    var list = notesLoad();
    list.unshift({ text: t, at: Date.now() });
    notesSave(list); ta.value = ""; if (h) h.textContent = "✓ 已添加";
    renderNotes();
  }
  function delNote(i) { var list = notesLoad(); list.splice(i, 1); notesSave(list); renderNotes(); }

  // ---------- 主题切换 ----------
  function applyTheme() {
    var light = localStorage.getItem("wb_theme") === "light";
    document.body.classList.toggle("light", light);
    var b = document.getElementById("themeBtn");
    if (b) b.textContent = light ? "☀️" : "🌙";
  }
  function toggleTheme() {
    var light = !document.body.classList.contains("light");
    document.body.classList.toggle("light", light);
    localStorage.setItem("wb_theme", light ? "light" : "dark");
    var b = document.getElementById("themeBtn");
    if (b) b.textContent = light ? "☀️" : "🌙";
  }

  function toggleNews(btn) {
    var d = btn.previousElementSibling;
    if (!d || !d.classList.contains("nw-d")) return;
    var open = d.classList.toggle("open");
    btn.textContent = open ? "收起 ▴" : "展开 ▾";
  }

  window.filt = filt; window.toggleCat = toggleCat; window.switchTab = switchTab;
  window.openHeat = openHeat; window.closeHeat = closeHeat;
  window.addNote = addNote; window.delNote = delNote; window.toggleTheme = toggleTheme;
  window.toggleNews = toggleNews;

  // ---------- 待办清单（可勾选，localStorage 纯前端） ----------
  var TODO_KEY = "wb_todos";
  function todosLoad() {
    try { return JSON.parse(localStorage.getItem(TODO_KEY) || "[]"); } catch (e) { return []; }
  }
  function todosSave(list) { try { localStorage.setItem(TODO_KEY, JSON.stringify(list)); } catch (e) {} }
  function renderTodos() {
    var ul = document.getElementById("todosList");
    if (!ul) return;
    var list = todosLoad();
    var done = list.filter(function (t) { return t.done; }).length;
    var prog = document.getElementById("todoProg");
    if (prog) prog.textContent = list.length ? ("已完成 " + done + " / 共 " + list.length) : "";
    if (!list.length) { ul.innerHTML = '<li class="empty">还没有待办，写一条吧～</li>'; return; }
    ul.innerHTML = list.map(function (t, i) {
      return '<li class="todo' + (t.done ? " done" : "") + '">' +
        '<input type="checkbox" class="tc" ' + (t.done ? "checked" : "") + ' onchange="toggleTodo(' + i + ')">' +
        '<span class="tt">' + esc(t.text) + '</span>' +
        '<button class="nd" onclick="delTodo(' + i + ')" title="删除">✕</button></li>';
    }).join("");
  }
  function addTodo() {
    var ta = document.getElementById("todoInput");
    var t = (ta.value || "").trim();
    var h = document.getElementById("todosHint");
    if (!t) { if (h) h.textContent = "先写点内容"; return; }
    var list = todosLoad();
    list.unshift({ text: t, done: false, at: Date.now() });
    todosSave(list); ta.value = ""; if (h) h.textContent = "✓ 已添加";
    renderTodos();
  }
  function toggleTodo(i) {
    var list = todosLoad();
    if (i < 0 || i >= list.length) return;
    list[i].done = !list[i].done;
    todosSave(list); renderTodos();
  }
  function delTodo(i) {
    var list = todosLoad();
    if (i < 0 || i >= list.length) return;
    list.splice(i, 1); todosSave(list); renderTodos();
  }
  function clearDone() {
    var list = todosLoad().filter(function (t) { return !t.done; });
    todosSave(list); renderTodos();
    var h = document.getElementById("todosHint");
    if (h) h.textContent = "✓ 已清除已完成";
  }
  window.addTodo = addTodo; window.toggleTodo = toggleTodo; window.delTodo = delTodo; window.clearDone = clearDone;
  window.dnewsDateChanged = dnewsDateChanged;

  // ---------- 渲染 ----------
  function renderKPI(d) {
    var k = d.kpi, disk = (d.status && d.status.disk) || {};
    var items = [
      { c: "kpi-blue", i: "📚", v: k.knowledge, l: "知识库文件" },
      { c: "kpi-green", i: "⚙️", v: k.automations, l: "定时任务" },
      { c: "kpi-purple", i: "💾", v: (disk.D ? disk.D.free + "G" : "-"), l: "磁盘可用 · 共 " + (disk.D ? disk.D.total + "G" : "-") },
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
      var list = byCat[cat].slice().sort(function (a, b) { return (b.usage || 0) - (a.usage || 0); });
      html += '<div class="cat open"><div class="cat-h" onclick="toggleCat(this)"><span class="ci">📦</span>' + esc(catLabel(cat)) +
        '<span class="cc">' + list.length + '</span><span class="car">▶</span></div><div class="cat-b">';
      list.forEach(function (s) {
        var fire = (s.usage > 0) ? '<span class="fire">🔥' + s.usage + "</span>" : "";
        html += '<span class="skill" onclick="cmd(this)" data-cmd="' + escAttr(s.cmd) + '" title="' + escAttr(s.desc) + '">' +
          '<span class="sn">' + esc(s.name) + fire + '</span><span class="sd">' + esc(s.desc) + "</span></span>";
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
    var html = '<div class="heat"><div class="heat-t">📈 近 17 周会话活跃 · 合计 ' + total + ' 条记录 · 点格子看当天聊了啥</div><div class="heat-g">';
    heat.forEach(function (h) {
      var lvl = h.count === 0 ? "l0" : (h.count <= 2 ? "l1" : (h.count <= 5 ? "l2" : "l3"));
      var titles = (h.titles || []).map(function (t) { return esc(t); }).join("\n");
      html += '<span class="hc ' + lvl + '" data-date="' + h.date + '" data-count="' + h.count + '" data-titles="' + escAttr(titles) + '" onclick="openHeat(this)" title="' + h.date + " : " + h.count + ' 个会话"></span>';
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
      '<div class="card"><h2><span class="ic">🧭</span>⑤ 今日引导 / 灵感 / 学 Agent</h2>' +
        '<ul class="guide">' + guideHtml + "</ul>" +
        '<div style="margin-top:12px"><button class="btn" onclick="inspire(' + "'" + escAttr(inspireCmd) + "'" + ')">💡 给我灵感（AI 生成）</button>' +
        '<div id="insbox"><textarea id="inspiretext" rows="5" placeholder="点击上方按钮，AI 灵感指令会出现在这里；可编辑，复制后到对话框 Ctrl+V 粘贴并发送"></textarea>' +
        '<div style="margin-top:6px"><button class="btn-sm" onclick="copyInspire()">📋 复制指令</button><span id="inshint"></span></div></div></div></div>' +
      '<div class="card"><h2><span class="ic">📡</span>⑧ AI 趋势 / 学习流</h2>' +
        (d.aiDaily && d.aiDaily.count
          ? '<div class="empty" style="margin:2px 0 4px">今日已抓 ' + d.aiDaily.count + ' 条 AI 资讯（' + esc(d.aiDaily.date || "") + '），每天 08:30 自动更新</div>'
          : '<div class="empty" style="margin:2px 0 4px">今日尚无日报数据</div>') +
        '<div style="margin-top:10px;display:flex;gap:8px;flex-wrap:wrap">' +
        '<button class="btn" onclick="switchTab(' + "'news'" + ')">🗞️ 看今日 AI 日报</button>' +
        '<button class="btn-sm" onclick="cmdtext(' + "'检索最近 30 天 AI 趋势，输出一份研究笔记'" + ')">🔭 趋势研究</button></div></div>' +
      '<div class="card"><h2><span class="ic">🚀</span>① 能力速达（点击复制调用指令）</h2>' +
        '<textarea id="cmdbox" rows="2" placeholder="点击上方 skill，指令会出现在这里（也可直接编辑/粘贴）"></textarea>' +
        '<div id="hint"></div><div id="sempty" class="empty" style="display:none">没有匹配的 skill</div>' +
        '<div id="skills">' + skillsHtml + "</div></div>" +
      '<div class="card"><h2><span class="ic">💬</span>⑥ 近期会话 / 任务流</h2>' + sessHtml + heatHtml + "</div>";
  }

  // ---------- AI 日报（支持历史日期切换） ----------
  var NEWS_DATA = null;
  function renderNews(d) {
    NEWS_DATA = d;
    var a = d.aiDaily || {};
    var box = document.getElementById("col-news");
    if (!box) return;
    var dot = document.getElementById("newsDot");
    if (dot) dot.style.display = ((a.count || 0) > 0) ? "inline-block" : "none";

    // 历史日期下拉（>1 天时显示）
    var hist = a.history || [];
    var curDate = a.date || "";
    var selHtml = "";
    if (hist.length > 1) {
      selHtml = '<div class="card"><div class="news-sel">📅 历史日报：' +
        '<select id="newsSel" onchange="newsDateChanged()">' +
        hist.map(function (h) {
          return '<option value="' + escAttr(h.date) + '"' + (h.date === curDate ? " selected" : "") + '>' +
            esc(h.date) + ' (' + (h.count || 0) + ' 条)</option>';
        }).join("") + '</select></div></div>';
    }
    box.innerHTML = selHtml + '<div id="newsBody"></div>';
    renderNewsBody(curDate);
  }
  function newsDateChanged() {
    var sel = document.getElementById("newsSel");
    if (sel) renderNewsBody(sel.value);
  }
  function renderNewsBody(date) {
    var box = document.getElementById("newsBody");
    if (!box || !NEWS_DATA) return;
    var a = NEWS_DATA.aiDaily || {};
    var day = (a.history || []).filter(function (h) { return h.date === date; })[0] || a;
    var secs = day.sections || [];
    if (!secs.length) {
      box.innerHTML = '<div class="card"><h2><span class="ic">🗞️</span>AI 日报</h2>' +
        '<div class="empty">这一天还没有抓到日报数据。可以点「立即刷新」让本机重新抓一次；也可以让 WorkBuddy 手动跑 <code>fetch_ai_daily.py</code>。</div>' +
        '<div style="margin-top:10px"><button class="btn" onclick="cmdtext(' + "'跑一下 personal-workbench 的 fetch_ai_daily.py 抓今天的 AI 日报，然后 export + push'" + ')">🔄 让 AI 现在抓一次</button></div></div>';
      return;
    }
    var html = '<div class="card news-head"><h2><span class="ic">🗞️</span>' + esc(day.date || "") + ' AI 日报' +
      '<span class="news-n">' + (day.count || 0) + ' 条</span></h2>' +
      '<div class="news-meta">数据源 ' + esc(day.source || a.source || "AI HOT") + ' · 抓取于 ' + esc(day.fetchedAt || "-") +
      (day.canonical ? ' · <a href="' + escAttr(day.canonical) + '" target="_blank" rel="noopener">看完整日报 ↗</a>' : "") + "</div></div>" +
      '<div class="card"><h2><span class="ic">🧪</span>基于日报做点什么</h2>' +
      '<div style="display:flex;gap:8px;flex-wrap:wrap">' +
      '<button class="btn" onclick="cmdtext(' + "'把今天工作台里的 AI 日报总结成 3 条对我最有用的要点，并各给一个可以今天动手试的小实验'" + ')">📝 提炼 3 条要点</button>' +
      '<button class="btn-sm" onclick="cmdtext(' + "'把今天的 AI 日报存进 vault/ 知识库，按主题归档'" + ')">📚 存进知识库</button>' +
      "</div></div>";

    secs.forEach(function (s) {
      html += '<div class="card"><h2><span class="ic">📌</span>' + esc(s.label) +
        '<span class="news-n">' + (s.items || []).length + "</span></h2>";
      (s.items || []).forEach(function (it) {
        var link = it.url
          ? '<a class="nw-a" href="' + escAttr(it.url) + '" target="_blank" rel="noopener">原文 ↗</a>' : "";
        var src = it.source ? '<span class="nw-s">' + esc(it.source) + "</span>" : "";
        var dHtml = "";
        if (it.summary) {
          var long = it.summary.length > 90;
          dHtml = '<div class="nw-d' + (long ? " clamp" : "") + '">' + esc(it.summary) + "</div>" +
            (long ? '<button class="nw-toggle" onclick="toggleNews(this)">展开 ▾</button>' : "");
        }
        html += '<div class="nw"><div class="nw-t">' + esc(it.title) + "</div>" +
          dHtml +
          '<div class="nw-f">' + src + link +
          '<button class="nw-ask" onclick="cmdtext(' + "'展开讲讲这条 AI 新闻，并说说对我有什么用：" + escAttr(it.title) + "'" + ')">💬 让 AI 讲讲</button>' +
          "</div></div>";
      });
      html += "</div>";
    });

    box.innerHTML = html;
  }

  // ---------- 每日新闻（国内/中文，支持历史日期切换） ----------
  var DNEWS_DATA = null;
  function renderDailyNews(d) {
    DNEWS_DATA = d;
    var a = d.dailyNews || {};
    var box = document.getElementById("col-dnews");
    if (!box) return;
    var dot = document.getElementById("dnewsDot");
    if (dot) dot.style.display = ((a.count || 0) > 0) ? "inline-block" : "none";

    var hist = a.history || [];
    var curDate = a.date || "";
    var selHtml = "";
    if (hist.length > 1) {
      selHtml = '<div class="card"><div class="news-sel">📅 历史新闻：' +
        '<select id="dnewsSel" onchange="dnewsDateChanged()">' +
        hist.map(function (h) {
          return '<option value="' + escAttr(h.date) + '"' + (h.date === curDate ? " selected" : "") + '>' +
            esc(h.date) + ' (' + (h.count || 0) + ' 条)</option>';
        }).join("") + '</select></div></div>';
    }
    box.innerHTML = selHtml + '<div id="dnewsBody"></div>';
    renderDNewsBody(curDate);
  }
  function dnewsDateChanged() {
    var sel = document.getElementById("dnewsSel");
    if (sel) renderDNewsBody(sel.value);
  }
  function renderDNewsBody(date) {
    var box = document.getElementById("dnewsBody");
    if (!box || !DNEWS_DATA) return;
    var a = DNEWS_DATA.dailyNews || {};
    var day = (a.history || []).filter(function (h) { return h.date === date; })[0] || a;
    var items = day.items || [];
    var tip = day.tip || "";
    if (!items.length) {
      box.innerHTML = '<div class="card"><h2><span class="ic">📰</span>每日新闻</h2>' +
        '<div class="empty">这一天还没有抓到新闻数据。可以点「立即刷新」让本机重新抓一次；也可以让 WorkBuddy 手动跑 <code>fetch_daily_news.py</code>。</div>' +
        '<div style="margin-top:10px"><button class="btn" onclick="cmdtext(' + "'跑一下 personal-workbench 的 fetch_daily_news.py 抓今天的国内新闻，然后 export + push'" + ')">🔄 让 AI 现在抓一次</button></div></div>';
      return;
    }
    var html = '<div class="card news-head"><h2><span class="ic">📰</span>' + esc(day.date || "") + ' 每日新闻' +
      '<span class="news-n">' + (day.count || 0) + ' 条</span></h2>' +
      '<div class="news-meta">数据源 ' + esc(day.source || a.source || "每日60秒") + ' · 抓取于 ' + esc(day.fetchedAt || "-") +
      (day.canonical ? ' · <a href="' + escAttr(day.canonical) + '" target="_blank" rel="noopener">看来源 ↗</a>' : "") + "</div>" +
      (tip ? '<div style="margin-top:8px;color:var(--sub);font-style:italic;line-height:1.5">💡 ' + esc(tip) + "</div>" : "") + "</div>" +
      '<div class="card"><h2><span class="ic">🧪</span>基于新闻做点什么</h2>' +
      '<div style="display:flex;gap:8px;flex-wrap:wrap">' +
      '<button class="btn" onclick="cmdtext(' + "'把今天工作台里的每日新闻挑 3 条跟我最相关的，说说为什么值得关注'" + ')">📝 挑 3 条相关的</button>' +
      '<button class="btn-sm" onclick="cmdtext(' + "'把今天的每日新闻存进 vault/ 知识库，按主题归档'" + ')">📚 存进知识库</button>' +
      "</div></div>";

    html += '<div class="card"><h2><span class="ic">📌</span>今日头条</h2>';
    items.forEach(function (it, i) {
      var ask = '<button class="nw-ask" onclick="cmdtext(' + "'展开讲讲这条新闻，并说说对我有什么影响：" + escAttr(it.title) + "'" + ')">💬 让 AI 讲讲</button>';
      html += '<div class="nw"><div class="nw-t"><span style="color:var(--accent2);font-weight:700;margin-right:7px;flex:0 0 auto">' + (i + 1) + '.</span>' + esc(it.title) + "</div>" +
        '<div class="nw-f"><span class="nw-s">' + esc(it.source || "每日60秒") + "</span>" + ask + "</div></div>";
    });
    html += "</div>";

    box.innerHTML = html;
  }

  function renderOv(d) {
    var st = d.status;
    var modelsHtml = (st.models || []).map(function (m) {
      return '<div class="model"><span class="mn">' + esc(m.name) + '</span><span class="mm">' + esc(m.type) + "</span></div>";
    }).join("");
    var mcpHtml = (st.mcp || []).map(function (m) {
      var off = (m.online === false);
      return '<span class="mcp' + (off ? " off" : "") + '">' + esc(m.name) +
        (off ? ' <span class="mcp-badge">离线</span>' : "") + "</span>";
    }).join("");
    var disk = st.disk || {};
    var localHtml = (st.localModels || []).map(function (m) { return '<div class="model">🧠 ' + esc(m) + "</div>"; }).join("");
    var ol = st.ollama || {};
    var olModels = ol.models || [];
    var olRunning = ol.running || [];
    var olHtml = ol.available === false ? '<div class="empty">Ollama 未安装</div>' :
      (olModels.length ? olModels.map(function (m) {
        var tags = m.tags || [m.name];
        var run = olRunning.some(function (r) { return tags.indexOf(r.name) >= 0; });
        var alias = tags.length > 1 ? " · 等 " + tags.length + " 个标签" : "";
        return '<div class="model ol-model"><span class="ol-dot ' + (run ? "on" : "") + '"></span><b>' + esc(tags[0]) + '</b>' +
          '<span class="meta">' + esc(m.size || "") + alias + (run ? " · 运行中" : "") + "</span></div>";
      }).join("") : '<div class="empty">Ollama 未运行 · 暂无本地模型</div>');
    var autoHtml = (st.automations || []).map(function (a) {
      var badge = a.status === "ACTIVE" || a.status === "active" ? '<span class="badge on">ACTIVE</span>' : '<span class="badge off">' + esc(a.status) + "</span>";
      return '<div class="auto">' + badge + "<b>" + esc(a.name) + '</b><span class="meta">recurring · 下次 ' + esc(a.next || "-") + "</span></div>";
    }).join("") || '<div class="empty">暂无自动化任务</div>';
    var kb = d.knowledge || { total: 0, types: {}, files: [] };
    var kbTypes = Object.keys(kb.types || {}).map(function (t) { return t + " " + kb.types[t]; }).join(" · ");
    var kbHtml = (kb.files || []).map(function (f) {
      return '<div class="auto"><b>' + esc(f.name) + '</b><span class="meta">' + esc(f.mtime) + "</span></div>";
    }).join("");

    document.getElementById("col-ov").innerHTML =
      '<div class="card"><h2><span class="ic">📊</span>③ 个人状态看板</h2>' +
        '<div class="ov-sub">已接入模型（' + (st.models || []).length + '）</div><div class="ov-models">' + modelsHtml + "</div>" +
        '<div class="ov-sub">集成与资源</div>' +
        '<div class="ov-res">' +
        '<div class="ov-mcp"><div class="ov-mcp-h"><span class="rk">MCP 集成</span><span class="rv">' + (st.mcp || []).length + '</span></div><div class="ov-mcp-chips">' + mcpHtml + "</div></div>" +
        '<div class="ov-metric"><span class="rk">记忆库</span><span class="rv">' + d.kpi.memory + '</span><span class="rn">个文件</span></div>' +
        '<div class="ov-metric"><span class="rk">磁盘 C:</span><span class="rv">' + (disk.C ? disk.C.free + "G" : "-") + '</span><span class="rn">共 ' + (disk.C ? disk.C.total + "G" : "-") + "</span></div>" +
        '<div class="ov-metric"><span class="rk">磁盘 D:</span><span class="rv">' + (disk.D ? disk.D.free + "G" : "-") + '</span><span class="rn">可用 · 共 ' + (disk.D ? disk.D.total + "G" : "-") + "</span></div>" +
        "</div></div>" +
      '<div class="card"><h2><span class="ic">🔧</span>⑦ 环境体检台</h2>' +
        '<div style="margin:6px 0 2px;color:var(--accent2);font-size:13px">本地 Ollama 模型（' + olModels.length + '）</div>' + olHtml +
        '<div class="res" style="margin-top:10px">' +
        '<div class="res-i"><span class="rk">C 盘剩余</span><span class="rv">' + (disk.C ? disk.C.free + "G" : "-") + '</span><span class="rn">共 ' + (disk.C ? disk.C.total + "G" : "-") + "</span></div>" +
        '<div class="res-i"><span class="rk">运行时</span><span class="rv" style="font-size:13px">' + esc(st.runtime || "-") + '</span><span class="rn">Python / Node</span></div>' +
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

  function renderWeekly(d) {
    var box = document.getElementById("wkList");
    if (!box) return;
    var items = d.weekly || [];
    var h2 = document.querySelector(".wk-card h2");
    if (h2) h2.innerHTML = '<span class="ic">📅</span>本周动态 · 近期变化（' + items.length + '）';
    if (!items.length) {
      box.innerHTML = '<li class="empty">本周暂无新增变化 · 工作台平稳运行中</li>';
      return;
    }
    var icon = { skill: "📦", automation: "⚙️", kb: "📄", model: "🧠" };
    var label = { skill: "新增/更新 skill", automation: "新建自动化任务", kb: "新增知识库文件", model: "拉取本地模型" };
    var shown = items.slice(0, 12);
    box.innerHTML = shown.map(function (it) {
      var dt = new Date((it.when || 0) * 1000);
      var ds = (dt.getMonth() + 1) + "-" + dt.getDate() + " " +
        ("0" + dt.getHours()).slice(-2) + ":" + ("0" + dt.getMinutes()).slice(-2);
      var scope = it.scope ? "（" + it.scope + "）" : "";
      return '<li class="wk"><span class="wk-ic">' + (icon[it.kind] || "•") + '</span>' +
        '<div class="wk-b"><span class="wk-name">' + esc(it.name) + '</span>' +
        '<span class="wk-meta">' + (label[it.kind] || it.kind) + scope + " · " + ds + '</span></div></li>';
    }).join("") + (items.length > shown.length ? '<li class="empty" style="padding-top:4px">本周共 ' + items.length + ' 条变化，显示最近 12 条</li>' : "");
  }

  // ---------- 课程表（localStorage 草稿 + GitHub 云端同步） ----------
  var GH_REPO = "W-lik721/personal-workbench";
  var GH_API = "https://api.github.com/repos/" + GH_REPO + "/contents/schedule.json";
  var GH_RAW = "https://raw.githubusercontent.com/" + GH_REPO + "/main/schedule.json";
  var GH_TOKEN_KEY = "wb_gh_token";
  function ghToken() { return localStorage.getItem(GH_TOKEN_KEY) || ""; }
  function setGhToken() {
    var t = window.prompt("粘贴你的 GitHub Personal Access Token（需要 repo + workflow 权限）。\n仅存于本浏览器 localStorage，不会上传。留空可清除。", ghToken());
    if (t === null) return;
    if (t.trim()) localStorage.setItem(GH_TOKEN_KEY, t.trim());
    else localStorage.removeItem(GH_TOKEN_KEY);
    var h = document.getElementById("schedHint");
    if (h) h.textContent = t.trim() ? "✓ Token 已保存（仅本浏览器）" : "已清除 Token";
  }
  function b64encodeUtf8(str) {
    return btoa(unescape(encodeURIComponent(str)));
  }
  // 把本地课程表推到 GitHub（schedule.json）
  function schedulePushCloud() {
    var token = ghToken();
    var hint = document.getElementById("schedHint");
    if (!token) { if (hint) hint.textContent = "请先点 ⚙️ 设置 GitHub Token"; return; }
    var list = scheduleLoad();
    var body = b64encodeUtf8(JSON.stringify(list, null, 2));
    var put = function (sha) {
      return fetch(GH_API, {
        method: "PUT",
        headers: { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
        body: JSON.stringify({ message: "chore: update schedule from workbench", content: body, sha: sha })
      });
    };
    fetch(GH_API, { headers: { "Authorization": "Bearer " + token } })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (meta) { return put(meta && meta.sha ? meta.sha : undefined); })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function () { if (hint) hint.textContent = "✓ 已备份到云端（" + list.length + " 条）"; })
      .catch(function (err) { if (hint) hint.textContent = "备份失败：" + err.message; });
  }
  // 从 GitHub 拉取课程表覆盖本地
  function schedulePullCloud(silent) {
    var hint = document.getElementById("schedHint");
    fetch(GH_RAW, { cache: "no-store" })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (list) {
        if (list && list.length) {
          scheduleSave(list); renderSchedule();
          if (hint && !silent) hint.textContent = "✓ 已从云端拉取 " + list.length + " 条";
        } else if (!silent && hint) {
          hint.textContent = "云端暂无课程表";
        }
      })
      .catch(function (err) { if (!silent && hint) hint.textContent = "拉取失败：" + err.message; });
  }
  window.schedulePushCloud = schedulePushCloud;
  window.schedulePullCloud = schedulePullCloud;
  window.setGhToken = setGhToken;

  var WEEKDAYS = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];
  var SCHED_KEY = "wb_schedule";
  function scheduleLoad() {
    try { return JSON.parse(localStorage.getItem(SCHED_KEY) || "[]"); } catch (e) { return []; }
  }
  function scheduleSave(list) {
    try { localStorage.setItem(SCHED_KEY, JSON.stringify(list)); } catch (e) {}
  }
  function normDow(s) {
    if (s == null) return "";
    s = String(s).trim();
    var cn = { "一": "周一", "二": "周二", "三": "周三", "四": "周四", "五": "周五", "六": "周六", "日": "周日", "天": "周日" };
    for (var k in cn) { if (s.indexOf(k) >= 0) return cn[k]; }
    var low = s.toLowerCase();
    var en = { "mon": "周一", "tue": "周二", "wed": "周三", "thu": "周四", "fri": "周五", "sat": "周六", "sun": "周日" };
    for (var e in en) { if (low.indexOf(e) === 0) return en[e]; }
    if (/^[1-7]$/.test(s)) return WEEKDAYS[parseInt(s, 10) - 1];
    return s;
  }
  var COL_ALIAS = {
    dow: ["星期", "周几", "星期几", "weekday", "dow"],
    time: ["时间", "节次", "时段", "time", "period"],
    name: ["课程", "课名", "科目", "名称", "course", "subject"],
    location: ["地点", "教室", "位置", "room", "location", "place", "场地"],
    teacher: ["老师", "教师", "授课", "讲师", "teacher", "instructor"],
    note: ["备注", "说明", "note", "remark", "注释", "批注"]
  };
  function detectField(header) {
    if (!header) return null;
    header = String(header).trim().toLowerCase();
    for (var f in COL_ALIAS) {
      var als = COL_ALIAS[f];
      for (var i = 0; i < als.length; i++) {
        if (header.indexOf(als[i].toLowerCase()) >= 0) return f;
      }
    }
    return null;
  }
  function headerHits(row) {
    var n = 0;
    for (var i = 0; i < row.length; i++) { if (detectField(row[i])) n++; }
    return n;
  }
  function rowToCourse(arr, headers) {
    var obj = {};
    if (headers && headers.length) {
      headers.forEach(function (h, i) {
        var f = detectField(h);
        if (f && arr[i] != null) obj[f] = String(arr[i]).trim();
      });
    } else {
      var pos = ["dow", "time", "name", "location", "teacher", "note"];
      arr.forEach(function (v, i) { if (pos[i] && v != null) obj[pos[i]] = String(v).trim(); });
    }
    obj.dow = normDow(obj.dow);
    if (!obj.name && !obj.time && !obj.dow) return null;
    if (!obj.name && arr.length === 1 && arr[0]) obj.name = String(arr[0]).trim();
    return obj;
  }
  function parseDelimited(text) {
    var lines = String(text).split(/\r?\n/).map(function (l) { return l.trim(); }).filter(function (l) { return l.length; });
    if (!lines.length) return [];
    var sep = lines[0].indexOf("\t") >= 0 ? "\t" : (lines[0].indexOf(",") >= 0 ? "," : null);
    var rows = lines.map(function (l) {
      if (sep === "\t") return l.split("\t");
      if (sep === ",") return l.split(",");
      return [l];
    });
    var hasHeader = headerHits(rows[0]) >= 2;
    var headers = hasHeader ? rows[0] : null;
    var dataRows = hasHeader ? rows.slice(1) : rows;
    return dataRows.map(function (r) { return rowToCourse(r, headers); }).filter(Boolean);
  }
  function ensureXLSX() {
    return new Promise(function (resolve, reject) {
      if (typeof XLSX !== "undefined") { resolve(); return; }
      var s = document.createElement("script");
      s.src = "xlsx.full.min.js";
      s.onload = function () { resolve(); };
      s.onerror = function () { reject(new Error("xlsx 解析库加载失败（请检查网络后重试）")); };
      document.head.appendChild(s);
    });
  }
  function parseXLSX(file) {
    return new Promise(function (resolve, reject) {
      if (typeof XLSX === "undefined") { reject(new Error("xlsx 解析库未加载（需联网后重试）")); return; }
      var reader = new FileReader();
      reader.onload = function (e) {
        try {
          var wb = XLSX.read(new Uint8Array(e.target.result), { type: "array" });
          var out = [];
          wb.SheetNames.forEach(function (sn) {
            var ws = wb.Sheets[sn];
            var rows = XLSX.utils.sheet_to_json(ws, { header: 1, defval: "", raw: false });
            rows = rows.filter(function (r) { return r.some(function (c) { return c != null && String(c).trim() !== ""; }); });
            if (!rows.length) return;
            var hasHeader = headerHits(rows[0]) >= 2;
            var headers = hasHeader ? rows[0] : null;
            var dataRows = hasHeader ? rows.slice(1) : rows;
            dataRows.forEach(function (r) { var c = rowToCourse(r, headers); if (c) out.push(c); });
          });
          resolve(out);
        } catch (err) { reject(err); }
      };
      reader.onerror = function () { reject(new Error("读取文件失败")); };
      reader.readAsArrayBuffer(file);
    });
  }
  function mergeSchedule(list) {
    if (scheduleLoad().length && !window.confirm("导入将替换当前课程表全部内容，确定吗？\n（点“取消”可改为手动逐条补充）")) return;
    scheduleSave(list);
  }
  function scheduleFileChosen(input) {
    var f = input.files && input.files[0];
    if (!f) return;
    var hint = document.getElementById("schedHint");
    var lower = f.name.toLowerCase();
    var done = function (list) {
      if (!list.length) { if (hint) hint.textContent = "没解析出课程，检查表头或内容"; return; }
      mergeSchedule(list);
      if (hint) hint.textContent = "✓ 已导入 " + list.length + " 条";
      renderSchedule();
    };
    var fail = function (err) { if (hint) hint.textContent = "导入失败：" + (err && err.message ? err.message : err); };
    if (lower.endsWith(".xlsx") || lower.endsWith(".xls")) {
      ensureXLSX().then(function () { parseXLSX(f).then(done).catch(fail); }).catch(fail);
    } else {
      var reader = new FileReader();
      reader.onload = function (e) { try { done(parseDelimited(String(e.target.result))); } catch (err) { fail(err); } };
      reader.onerror = function () { fail(new Error("读取文件失败")); };
      reader.readAsText(f, "utf-8");
    }
    input.value = "";
  }
  function importSchedulePaste() {
    var ta = document.getElementById("schedPaste");
    var hint = document.getElementById("schedHint");
    var list = parseDelimited(ta.value || "");
    if (!list.length) { if (hint) hint.textContent = "粘贴内容没解析出课程"; return; }
    mergeSchedule(list);
    if (hint) hint.textContent = "✓ 已导入 " + list.length + " 条（粘贴）";
    renderSchedule();
  }
  function addCourse() {
    var g = function (id) { var el = document.getElementById(id); return el ? el.value.trim() : ""; };
    var c = { dow: normDow(g("scDow")), time: g("scTime"), name: g("scName"), location: g("scLoc"), teacher: g("scTeach"), note: g("scNote") };
    if (!c.name && !c.time && !c.dow) { var h = document.getElementById("schedHint"); if (h) h.textContent = "至少填课程名或时间"; return; }
    var list = scheduleLoad(); list.push(c); scheduleSave(list); renderSchedule();
    ["scDow", "scTime", "scName", "scLoc", "scTeach", "scNote"].forEach(function (id) { var el = document.getElementById(id); if (el) el.value = ""; });
  }
  function delCourse(i) {
    var list = scheduleLoad(); list.splice(i, 1); scheduleSave(list); renderSchedule();
  }
  function downloadFile(name, content, mime) {
    var blob = new Blob([content], { type: mime });
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a"); a.href = url; a.download = name;
    document.body.appendChild(a); a.click();
    setTimeout(function () { document.body.removeChild(a); URL.revokeObjectURL(url); }, 0);
  }
  function exportSchedule(fmt) {
    var list = scheduleLoad();
    var hint = document.getElementById("schedHint");
    if (!list.length) { if (hint) hint.textContent = "没有可导出的数据"; return; }
    var fn = "课程表";
    if (fmt === "csv") {
      var head = ["星期", "时间", "课程", "地点", "老师", "备注"];
      var rows = list.map(function (c) { return [c.dow || "", c.time || "", c.name || "", c.location || "", c.teacher || "", c.note || ""]; });
      var csv = "﻿" + head.join(",") + "\n" + rows.map(function (r) {
        return r.map(function (v) { return '"' + String(v).replace(/"/g, '""') + '"'; }).join(",");
      }).join("\n");
      downloadFile(fn + ".csv", csv, "text/csv;charset=utf-8");
      if (hint) hint.textContent = "✓ 已导出 CSV";
    } else {
      downloadFile(fn + ".json", JSON.stringify(list, null, 2), "application/json");
      if (hint) hint.textContent = "✓ 已导出 JSON";
    }
  }
  function renderSchedule() {
    var box = document.getElementById("col-schedule");
    if (!box) return;
    var list = scheduleLoad();
    var byDay = {}; WEEKDAYS.concat(["其他"]).forEach(function (d) { byDay[d] = []; });
    list.forEach(function (c, idx) {
      var d = WEEKDAYS.indexOf(c.dow) >= 0 ? c.dow : "其他";
      c.__i = idx; byDay[d].push(c);
    });
    Object.keys(byDay).forEach(function (d) {
      byDay[d].sort(function (a, b) { return (a.time || "").localeCompare(b.time || ""); });
    });
    var importCard =
      '<div class="card"><h2><span class="ic">📥</span>导入课程表（CSV / Excel / 粘贴）</h2>' +
      '<div class="sched-imp">' +
      '<label class="sched-file">📁 选择文件<input type="file" accept=".csv,.xlsx,.xls,.txt" onchange="scheduleFileChosen(this)"></label>' +
      '<span class="empty" style="margin:0">或</span>' +
      '<button class="btn-sm" onclick="document.getElementById(&quot;schedPaste&quot;).focus()">📋 粘贴表格</button>' +
      '<button class="btn-sm" onclick="exportSchedule(&quot;csv&quot;)">⬇️ 导出 CSV</button>' +
      '<button class="btn-sm" onclick="exportSchedule(&quot;json&quot;)">⬇️ 导出 JSON</button>' +
      '</div>' +
      '<textarea id="schedPaste" rows="3" class="sched-paste" placeholder="把 Excel/表格里的几行复制粘贴到这里（首行写表头：星期/时间/课程/地点/老师/备注，用制表符或逗号分开），再点“解析粘贴内容”。"></textarea>' +
      '<div style="margin-top:8px;display:flex;gap:8px;align-items:center">' +
      '<button class="btn" onclick="importSchedulePaste()">🔄 解析粘贴内容</button>' +
      '<span id="schedHint" class="empty"></span></div>' +
      '<div style="margin-top:9px;display:flex;gap:8px;align-items:center;border-top:1px solid var(--line);padding-top:9px">' +
      '<span class="empty" style="margin:0">☁️ 云端同步：</span>' +
      '<button class="btn-sm" onclick="schedulePushCloud()">⬆️ 备份到云端</button>' +
      '<button class="btn-sm" onclick="schedulePullCloud(false)">⬇️ 从云端拉取</button>' +
      '<button class="btn-sm" onclick="setGhToken()">⚙️ Token</button>' +
      '</div></div>';
    var addCard =
      '<div class="card"><h2><span class="ic">➕</span>手动加一行</h2>' +
      '<div class="sched-form">' +
      '<input id="scDow" class="sf" placeholder="星期（如 周一）">' +
      '<input id="scTime" class="sf" placeholder="时间（如 08:00-09:40）">' +
      '<input id="scName" class="sf" placeholder="课程名 *">' +
      '<input id="scLoc" class="sf" placeholder="地点">' +
      '<input id="scTeach" class="sf" placeholder="老师">' +
      '<input id="scNote" class="sf" placeholder="备注">' +
      '</div>' +
      '<div style="margin-top:8px"><button class="btn-sm" onclick="addCourse()">➕ 添加这一行</button></div></div>';
    var tableCard;
    if (!list.length) {
      tableCard = '<div class="card"><h2><span class="ic">📅</span>课程表</h2><div class="empty">还没有课程。用上方导入，或手动加一行。</div></div>';
    } else {
      var body = "";
      WEEKDAYS.concat(["其他"]).forEach(function (d) {
        var arr = byDay[d]; if (!arr.length) return;
        body += '<div class="sched-day"><div class="sched-day-h">' + esc(d) + ' <span class="cc">' + arr.length + '</span></div>';
        arr.forEach(function (c) {
          body += '<div class="sched-row">' +
            '<div class="sr-time">' + esc(c.time || "-") + '</div>' +
            '<div class="sr-main"><b>' + esc(c.name || "未命名") + '</b>' +
            (c.location ? '<span class="sr-loc">📍 ' + esc(c.location) + '</span>' : '') +
            (c.teacher ? '<span class="sr-teach">👤 ' + esc(c.teacher) + '</span>' : '') +
            (c.note ? '<span class="sr-note">📝 ' + esc(c.note) + '</span>' : '') + '</div>' +
            '<button class="nd" onclick="delCourse(' + c.__i + ')">✕</button>' +
            '</div>';
        });
        body += '</div>';
      });
      tableCard = '<div class="card"><h2><span class="ic">📅</span>我的课程表 · 共 ' + list.length + ' 节</h2>' + body + '</div>';
    }
    box.innerHTML = importCard + addCard + tableCard;
  }
  window.renderSchedule = renderSchedule;
  window.scheduleFileChosen = scheduleFileChosen;
  window.importSchedulePaste = importSchedulePaste;
  window.addCourse = addCourse;
  window.delCourse = delCourse;
  window.exportSchedule = exportSchedule;

  function render(d) {
    document.getElementById("snap").textContent = "📸 快照 · " + (d.generatedAt || "-");
    renderSync(d);
    renderKPI(d);
    renderQuick(d);
    renderCap(d);
    renderNews(d);
    renderDailyNews(d);
    renderOv(d);
    renderWeekly(d);
  }

  // ---------- 同步健康度（数据新鲜度 + 失败/陈旧告警） ----------
  function renderSync(d) {
    var el = document.getElementById("syncStatus");
    if (!el) return;
    var s = d.sync;
    if (!s || !s.lastRun) {
      el.className = "sync-status warn";
      el.textContent = "⚠️ 暂无同步记录，定时任务可能未运行";
      return;
    }
    var last = new Date(s.lastRun.replace(" ", "T"));
    var stale = (s.staleHours != null) ? s.staleHours : 2;
    var diffMs = Date.now() - last.getTime();
    var diffH = diffMs / 3600000;
    var hhmm = (last.getMonth() + 1) + "-" + last.getDate() + " " +
      ("0" + last.getHours()).slice(-2) + ":" + ("0" + last.getMinutes()).slice(-2);

    if (s.status === "fail" || diffH > stale) {
      el.className = "sync-status warn";
      var overdue = diffH > 0 ? "，已超时约 " + (diffH >= 1 ? diffH.toFixed(1) + " 小时" : Math.round(diffMs / 60000) + " 分钟") : "";
      el.textContent = "⚠️ 同步可能已停止（上次 " + hhmm + overdue + "）· 定时任务或网络异常";
    } else {
      el.className = "sync-status ok";
      var next = s.nextRun ? new Date(s.nextRun.replace(" ", "T")) : null;
      var nextStr = next ? (" · 下次约 " + ("0" + next.getHours()).slice(-2) + ":" + ("0" + next.getMinutes()).slice(-2)) : "";
      el.textContent = "✅ 同步正常（上次 " + hhmm + nextStr + "）";
    }

    // 刷新按钮旁标注「下次自动同步」时间（④）
    var ns = document.getElementById("nextSync");
    if (ns) {
      if (s && s.nextRun) {
        var n = new Date(s.nextRun.replace(" ", "T"));
        ns.textContent = "下次自动同步 · " + ("0" + n.getHours()).slice(-2) + ":" + ("0" + n.getMinutes()).slice(-2);
      } else {
        ns.textContent = "下次自动同步 · -";
      }
    }
  }

  // ---------- 启动 ----------
  var __lastGen = "";
  function loadData() {
    return fetch("data.json?t=" + Date.now(), { cache: "no-store" })
      .then(function (r) { return r.json(); })
      .then(function (d) { render(d); __lastGen = d.generatedAt || ""; return d; });
  }
  // 数据变化时自动重渲染（覆盖自动/手动同步），免去手动刷新浏览器
  function maybeReload() {
    return fetch("data.json?t=" + Date.now(), { cache: "no-store" })
      .then(function (r) { return r.json(); })
      .then(function (d) {
        if ((d.generatedAt || "") !== __lastGen) {
          render(d); __lastGen = d.generatedAt || "";
          return true;
        }
        return false;
      })
      .catch(function () { return false; });
  }
  // ---------- 立即刷新：触发 GitHub Actions 同步（等同手动 Run workflow） ----------
  function refreshData() {
    var btn = document.getElementById("refreshBtn");
    var token = ghToken();
    if (!token) {
      window.alert("首次使用需要先填 GitHub Token（只存你浏览器）。\n点「确定」后在弹窗粘贴 Token（需要 repo + workflow 权限），填好再来点刷新。");
      setGhToken();
      return;
    }
    var old = btn ? btn.textContent : "🔄 立即刷新";
    if (btn) { btn.disabled = true; btn.textContent = "⏳ 触发同步…"; }

    var api = "https://api.github.com/repos/" + GH_REPO + "/actions/workflows/sync.yml/dispatches";
    // 在发起请求前记录时间戳，并预留 3 秒缓冲，避免 run 创建时间早于 POST 响应导致漏检
    var afterTs = Date.now() - 3000;
    fetch(api, {
      method: "POST",
      headers: {
        "Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
        "X-GitHub-Api-Version": "2022-11-28"
      },
      body: JSON.stringify({ ref: "main" })
    }).then(function (r) {
      if (r.ok) return;
      if (r.status === 401 || r.status === 403) throw new Error("Token 无效或权限不足（需要 repo + workflow 权限，HTTP " + r.status + "）");
      if (r.status === 404) throw new Error("找不到同步工作流（404），请确认仓库/分支名");
      throw new Error("触发失败：HTTP " + r.status);
    }).then(function () {
      if (btn) btn.textContent = "🔄 本机 Runner 执行中…";
      pollUntilSynced(btn, old, 0, afterTs);
    }).catch(function (err) {
      if (btn) { btn.disabled = false; btn.textContent = old; }
      window.alert("立即刷新失败：" + err.message);
    });
  }

  // 轮询本次触发的运行，完成后等 Pages 重新部署再刷新页面
  function pollUntilSynced(btn, old, tries, afterTs) {
    var MAX = 24; // 24 × 10s ≈ 4 分钟
    if (tries >= MAX) {
      if (btn) { btn.disabled = false; btn.textContent = old; }
      window.alert("同步任务已提交，但本机 Runner 似乎没在运行（任务一直排队）。\n请确认本机 Runner 进程已启动，或稍后手动刷新浏览器。");
      loadData().catch(function () {});
      return;
    }
    var runsApi = "https://api.github.com/repos/" + GH_REPO + "/actions/workflows/sync.yml/runs?per_page=10";
    fetch(runsApi, {
      headers: {
        "Authorization": "Bearer " + ghToken(),
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28"
      }
    }).then(function (r) { return r.json(); }).then(function (j) {
      // 取 created_at >= afterTs 的最新一次运行
      var runs = (j.workflow_runs || []).filter(function (x) {
        return new Date(x.created_at).getTime() >= afterTs;
      }).sort(function (a, b) {
        return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
      });
      var run = runs[0] || null;
      if (run && run.status === "completed") {
        if (run.conclusion === "success") {
          if (btn) btn.textContent = "✅ 同步完成，刷新中…";
          tightReload(btn, old, 0);
        } else {
          if (btn) { btn.disabled = false; btn.textContent = old; }
          window.alert("本次同步运行失败（" + (run.conclusion || "unknown") + "），请到 GitHub Actions 看日志。");
          loadData().catch(function () {});
        }
      } else if (run && (run.status === "in_progress" || run.status === "queued" || run.status === "waiting")) {
        if (btn) btn.textContent = "🔄 本机 Runner 执行中… (" + (tries + 1) + "/" + MAX + ")";
        setTimeout(function () { pollUntilSynced(btn, old, tries + 1, afterTs); }, 10000);
      } else {
        // 列表里还没出现本次触发，继续等
        setTimeout(function () { pollUntilSynced(btn, old, tries + 1, afterTs); }, 10000);
      }
    }).catch(function () {
      setTimeout(function () { pollUntilSynced(btn, old, tries + 1, afterTs); }, 10000);
    });
  }
  // 同步完成后紧轮询：每 10s 看一次数据，直到 generatedAt 变化（新数据已上线）再复位按钮
  function tightReload(btn, old, tries) {
    if (tries >= 30) { // 30 × 10s ≈ 5 分钟，给 GitHub Pages 部署留足时间
      if (btn) { btn.disabled = false; btn.textContent = old; }
      window.alert("本机同步已完成，但 GitHub Pages 上线略有延迟。\n页面会在后台继续检测，30 秒内若数据上线会自动刷新；也可稍后手动刷新浏览器。");
      return;
    }
    if (btn) btn.textContent = "✅ 同步完成，刷新中… (" + (tries + 1) + "/30)";
    maybeReload().then(function (reloaded) {
      if (reloaded) { if (btn) { btn.disabled = false; btn.textContent = old; } }
      else setTimeout(function () { tightReload(btn, old, tries + 1); }, 10000);
    });
  }
  window.refreshData = refreshData;

  // ---------- 功能自检：一键验证「触发 → 同步 → 自动刷新」全链路 ----------
  function setSelfCheck(cls, msg) {
    var box = document.getElementById("selfCheckResult");
    if (!box) return;
    box.className = "selfcheck" + (cls ? " " + cls : "");
    box.style.display = "block";
    box.textContent = msg;
  }
  function selfCheck() {
    var btn = document.getElementById("selfCheckBtn");
    var token = ghToken();
    if (!token) {
      setSelfCheck("warn", "⚠️ 需先填 GitHub Token（点「🌙」旁的 ⚙️ 或首次点「立即刷新」会提示）");
      return;
    }
    if (btn) { btn.disabled = true; btn.textContent = "🔍 自检中…"; }
    setSelfCheck("run", "步骤 1/4 · 正在触发同步…");

    var api = "https://api.github.com/repos/" + GH_REPO + "/actions/workflows/sync.yml/dispatches";
    var afterTs = Date.now() - 3000;
    fetch(api, {
      method: "POST",
      headers: {
        "Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
        "X-GitHub-Api-Version": "2022-11-28"
      },
      body: JSON.stringify({ ref: "main" })
    }).then(function (r) {
      if (r.ok) return;
      if (r.status === 401 || r.status === 403) throw new Error("Token 无效或权限不足（HTTP " + r.status + "）");
      if (r.status === 404) throw new Error("找不到同步工作流（404）");
      throw new Error("触发失败：HTTP " + r.status);
    }).then(function () {
      pollSelfCheck(btn, afterTs, 0);
    }).catch(function (err) {
      if (btn) { btn.disabled = false; btn.textContent = "🔍 功能自检"; }
      setSelfCheck("warn", "❌ 自检中断：" + err.message);
    });
  }
  function pollSelfCheck(btn, afterTs, tries) {
    var MAX = 24;
    if (tries >= MAX) {
      if (btn) { btn.disabled = false; btn.textContent = "🔍 功能自检"; }
      setSelfCheck("warn", "❌ 超时：本机 Runner 一直没响应，请确认 Runner 服务在运行");
      return;
    }
    var runsApi = "https://api.github.com/repos/" + GH_REPO + "/actions/workflows/sync.yml/runs?per_page=10";
    fetch(runsApi, {
      headers: {
        "Authorization": "Bearer " + ghToken(),
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28"
      }
    }).then(function (r) { return r.json(); }).then(function (j) {
      var runs = (j.workflow_runs || []).filter(function (x) {
        return new Date(x.created_at).getTime() >= afterTs;
      }).sort(function (a, b) {
        return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
      });
      var run = runs[0] || null;
      if (run && run.status === "completed") {
        if (run.conclusion === "success") {
          setSelfCheck("run", "步骤 3/4 · 同步成功 (run " + run.id + ")，等待数据上线…");
          tightReloadSelfCheck(btn, 0);
        } else {
          if (btn) { btn.disabled = false; btn.textContent = "🔍 功能自检"; }
          setSelfCheck("warn", "❌ 同步运行失败（" + (run.conclusion || "unknown") + "），请到 GitHub Actions 看日志");
        }
      } else if (run && (run.status === "in_progress" || run.status === "queued" || run.status === "waiting")) {
        setSelfCheck("run", "步骤 2/4 · Runner 执行中（" + run.status + "）…");
        setTimeout(function () { pollSelfCheck(btn, afterTs, tries + 1); }, 10000);
      } else {
        setSelfCheck("run", "步骤 2/4 · 等待 Runner 接收任务…");
        setTimeout(function () { pollSelfCheck(btn, afterTs, tries + 1); }, 10000);
      }
    }).catch(function () {
      setTimeout(function () { pollSelfCheck(btn, afterTs, tries + 1); }, 10000);
    });
  }
  function tightReloadSelfCheck(btn, tries) {
    if (tries >= 30) {
      if (btn) { btn.disabled = false; btn.textContent = "🔍 功能自检"; }
      setSelfCheck("warn", "⚠️ 同步已完成，但数据上线略有延迟，页面会在后台自动刷新");
      return;
    }
    maybeReload().then(function (reloaded) {
      if (reloaded) {
        if (btn) { btn.disabled = false; btn.textContent = "🔍 功能自检"; }
        setSelfCheck("ok", "✅ 自检通过：触发 → 同步 → 自动刷新 全链路正常");
      } else {
        setTimeout(function () { tightReloadSelfCheck(btn, tries + 1); }, 10000);
      }
    });
  }
  // ---------- 常用入口（纯前端，本机 localStorage 存，不依赖 data.json） ----------
  var LINKS_KEY = "wb_links";
  var DEFAULT_LINKS = [
    {"label": "抖音", "url": "https://www.douyin.com"},
    {"label": "WorkBuddy 文档", "url": "https://www.workbuddy.cn/docs/"},
    {"label": "本仓库源码", "url": "https://github.com/W-lik721/personal-workbench"},
    {"label": "AI 日报源", "url": "https://aihot.virxact.com/daily"},
    {"label": "每日新闻源", "url": "https://github.com/vikiboss/60s"},
    {"label": "本地 Ollama", "url": "http://localhost:11434"}
  ];
  function getLinks() {
    try { var v = localStorage.getItem(LINKS_KEY); if (v) return JSON.parse(v); } catch (e) {}
    return DEFAULT_LINKS.slice();
  }
  function saveLinks(a) { try { localStorage.setItem(LINKS_KEY, JSON.stringify(a)); } catch (e) {} }
  function renderLinks() {
    var g = document.getElementById("linksGrid");
    if (!g) return;
    var links = getLinks();
    if (!links.length) { g.innerHTML = '<div class="empty">还没有入口，点“加一个”添加常用链接</div>'; return; }
    g.innerHTML = links.map(function (l, i) {
      return '<a class="link-item" href="' + esc(l.url) + '" target="_blank" rel="noopener">' +
        '<span class="li-ic">🔗</span><span class="li-label">' + esc(l.label) + '</span>' +
        '<span class="li-del" data-i="' + i + '" title="删除">✕</span></a>';
    }).join("");
    Array.prototype.forEach.call(g.querySelectorAll(".li-del"), function (b) {
      b.addEventListener("click", function (e) {
        e.preventDefault(); e.stopPropagation();
        delLink(parseInt(b.getAttribute("data-i"), 10));
      });
    });
  }
  function addLink() {
    var label = window.prompt("入口名称（如 抖音）：");
    if (!label) return;
    var url = window.prompt("链接地址（以 http 开头，可留空自动补 https://）：", "https://");
    if (url === null) return;
    if (!/^https?:\/\//i.test(url)) url = "https://" + url;
    var links = getLinks(); links.push({ label: label, url: url }); saveLinks(links); renderLinks();
    var h = document.getElementById("linksHint"); if (h) h.textContent = "✓ 已添加（仅存本浏览器）";
  }
  function delLink(i) {
    var links = getLinks(); if (i < 0 || i >= links.length) return;
    links.splice(i, 1); saveLinks(links); renderLinks();
  }
  window.addLink = addLink; window.delLink = delLink; window.renderLinks = renderLinks;

  window.selfCheck = selfCheck;
  applyTheme();
  renderNotes();
  renderSchedule();
  renderLinks();
  renderTodos();
  // 本地无课程表时，自动从云端拉取一次（换设备也能看到）
  if (!scheduleLoad().length) schedulePullCloud(true);
  var ni = document.getElementById("noteInput");
  if (ni) ni.addEventListener("keydown", function (e) { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); addNote(); } });
  var ti = document.getElementById("todoInput");
  if (ti) ti.addEventListener("keydown", function (e) { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); addTodo(); } });
  loadData().catch(function (e) {
    document.getElementById("col-cap").innerHTML = '<div class="card"><h2>⚠️ 数据加载失败</h2><div class="empty">无法读取 data.json：' + esc(e) + "。请确认已运行 export_data.py 生成数据。</div></div>";
  });

  // 后台自动刷新：每 30s 检测数据是否更新，有变化就自动重渲染（覆盖每小时自动同步）
  setInterval(maybeReload, 30000);

  if ("serviceWorker" in navigator) {
    window.addEventListener("load", function () {
      navigator.serviceWorker.register("sw.js").catch(function () {});
    });
  }
})();
