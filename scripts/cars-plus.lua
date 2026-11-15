script_name('Cars Plus')
script_author('ArzHub')
script_version('1.0.3')
script_url('https://arzhub.top/hub/cars-plus')

-- Script page (current version, changelog): https://arzhub.top/hub/cars-plus

local moonloader = require('moonloader') -- download_status for the update check.
local sampev = require('samp.events')
local encoding = require('encoding')
local inicfg = require('inicfg')
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local function cp(s) return u8:decode(s) end

local tag = '{FFA31A}[ArzHub] Cars Plus{FFFFFF}: '

local function notify(text)
    sampAddChatMessage(tag .. cp(text), -1)
end

local function readFile(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local content = f:read('*a')
    f:close()
    return content
end

-- ============================================================================
-- CONFIG: the chosen sort order
-- ============================================================================

local configPath = 'ArzHub/cars-plus/config.ini'

local config = inicfg.load({
    settings = {
        sort = 'default' -- One of SORT_KEYS.
    }
}, configPath)

-- One level at a time: config\ArzHub may not exist yet either. Returns config\ArzHub\cars-plus.
local function ensureConfigDir()
    local dir = getWorkingDirectory() .. '\\config'
    for part in configPath:match('(.+)/'):gmatch('[^/]+') do
        dir = dir .. '\\' .. part
        if not doesDirectoryExist(dir) then createDirectory(dir) end
    end
    return dir
end

local function saveConfig()
    ensureConfigDir()
    inicfg.save(config, configPath)
end

-- Keys are stored in the config, never rename them.
local SORT_KEYS = { default = true, name = true, name_desc = true, new = true, old = true, rating = true }

local function sortKey()
    local k = config.settings.sort
    return SORT_KEYS[k] and k or 'default'
end

-- ============================================================================
-- CEF: search and sort in the «Мои Т/С» window
-- ============================================================================

local MSG_PREFIX = 'ahCarsPlus|'

local BOOT_TEMPLATE = [==[
(() => {
    const VERSION = '__VERSION__';
    const SAVED_SORT = '__SORT__';
    const BAR_ID = 'ah-cars-plus-bar';
    const STYLE_ID = 'ah-cars-plus-style';
    const LIST_SEL = '.vehicle-menu-list';
    const HIDE = 'ah-hide';
    const FLEX = 'ah-flex';
    const CALL = 'ah-call';

    const prev = window.__ahCarsPlus;
    if (prev) {
        if (prev.version === VERSION) { prev.kick(); return; }
        try { prev.teardown(); } catch (e) {}
    }

    const T = {
        search: '\u041f\u043e\u0438\u0441\u043a \u043f\u043e \u043d\u0430\u0437\u0432\u0430\u043d\u0438\u044e', // Поиск по названию
        emptyTitle: '\u0443\u043f\u0441.. \u0430\u0432\u0442\u043e\u043c\u043e\u0431\u0438\u043b\u0435\u0439 \u043d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d\u043e', // упс.. автомобилей не найдено
        emptyCaption: '\u041f\u043e \u0432\u0430\u0448\u0435\u043c\u0443 \u0437\u0430\u043f\u0440\u043e\u0441\u0443 \u043d\u0438\u0447\u0435\u0433\u043e \u043d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d\u043e', // По вашему запросу ничего не найдено
        hOrder: '\u041f\u043e\u0440\u044f\u0434\u043e\u043a:', // Порядок:
        hName: '\u041d\u0430\u0437\u0432\u0430\u043d\u0438\u0435:', // Название:
        hAdded: '\u0414\u043e\u0431\u0430\u0432\u043b\u0435\u043d\u044b:', // Добавлены:
        hRating: '\u0420\u0435\u0439\u0442\u0438\u043d\u0433:', // Рейтинг:
        vDefault: '\u043f\u043e \u0443\u043c\u043e\u043b\u0447\u0430\u043d\u0438\u044e', // по умолчанию
        vName: '\u043e\u0442 \u0410 \u0434\u043e \u042f', // от А до Я
        vNameDesc: '\u043e\u0442 \u042f \u0434\u043e \u0410', // от Я до А
        vNew: '\u0441\u043d\u0430\u0447\u0430\u043b\u0430 \u043d\u043e\u0432\u044b\u0435', // сначала новые
        vOld: '\u0441\u043d\u0430\u0447\u0430\u043b\u0430 \u0441\u0442\u0430\u0440\u044b\u0435', // сначала старые
        vRating: '\u0441\u043d\u0430\u0447\u0430\u043b\u0430 \u043b\u0443\u0447\u0448\u0438\u0435', // сначала лучшие
        call: '\u0412\u044b\u0437\u0432\u0430\u0442\u044c', // Вызвать
        nativeCall: '\u0412\u044b\u0437\u0432\u0430\u0442\u044c \u0437\u0430', // Вызвать за
    };

    const MODES = [
        { k: 'default', t: T.hOrder, s: T.vDefault },
        { k: 'name', t: T.hName, s: T.vName },
        { k: 'name_desc', t: T.hName, s: T.vNameDesc },
        { k: 'new', t: T.hAdded, s: T.vNew },
        { k: 'old', t: T.hAdded, s: T.vOld },
        { k: 'rating', t: T.hRating, s: T.vRating },
    ];

    const state = { q: '', sort: 'default', open: false, byId: new Map(), seq: 0 };
    if (MODES.some((m) => m.k === SAVED_SORT)) state.sort = SAVED_SORT;
    // The choice is kept in the script's config: the page reports it to Lua.
    const save = () => {
        try { window.cef.SendMessage('__PREFIX__sort|' + state.sort, 0); } catch (e) {}
    };

    // Same fluid size formula Arizona's CSS uses.
    const gs = (n) => {
        const t = 'var(--global-scale)*' + n + '*var(--global-scale)';
        const d = '(var(--global-scale)*1920 - var(--global-scale)*800)';
        const e = 'calc((' + t + ' - ' + t + '*0.44)/' + d + ')*100vw + calc((' + t + '*0.44 - (' + t + ' - ' + t + '*0.44)/' + d + '*800*var(--global-scale))*1px)';
        return n < 0 ? 'min(' + e + ',-1px)' : 'max(' + e + ',1px)';
    };

    const el = (tag, cls, text) => {
        const e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text != null) e.textContent = text;
        return e;
    };
    const setText = (e, v) => { if (e.textContent !== v) e.textContent = v; };
    const setClass = (e, v) => { if (e.className !== v) e.className = v; };
    const toggle = (e, cls, on) => { if (e.classList.contains(cls) !== on) e.classList.toggle(cls, on); };

    // Case-insensitive, yo equals ye, runs of spaces collapse.
    const norm = (s) => String(s || '').toLowerCase().replace(/\u0451/g, '\u0435').replace(/\s+/g, ' ').trim();
    const ownText = (e) => {
        let s = '';
        e.childNodes.forEach((n) => { if (n.nodeType === 3) s += n.textContent; });
        return s.replace(/\s+/g, ' ').trim();
    };
    const num = (s) => {
        const m = String(s == null ? '' : s).replace(/[\s\u00a0]/g, '').match(/\d+/);
        return m ? parseInt(m[0], 10) : null;
    };

    //region EVENT HOOK - vehicle ids only travel in pushVehicleItem, the cards carry none
    const parseArgs = (a) => {
        if (Array.isArray(a)) return a;
        if (typeof a !== 'string') return null;
        const v = a.replace(/[\\]/g, '\\\\').replace(/[\/]/g, '\\/').replace(/[\b]/g, '\\b')
            .replace(/[\f]/g, '\\f').replace(/[\n]/g, '\\n').replace(/[\r]/g, '\\r').replace(/[\t]/g, '\\t');
        try { const d = JSON.parse(v); return Array.isArray(d) ? d : [d]; } catch (e) { return null; }
    };
    const put = (v) => {
        if (!v || typeof v.id !== 'number') return;
        const old = state.byId.get(v.id);
        state.byId.set(v.id, Object.assign(old || { _index: state.seq++ }, v));
    };
    const onEvent = (name, args) => {
        if (name === 'cef.modals.showModal') {
            if (String(args).indexOf('carMenu') !== -1) { state.byId.clear(); state.seq = 0; }
            return;
        }
        if (name.indexOf('event.vehicleMenu.') !== 0) return;
        const ev = name.slice(18);
        if (ev !== 'pushVehicleItem' && ev !== 'initializeVehicleList' && ev !== 'updateVehicleItem') return;
        const data = parseArgs(args);
        if (!data) return;
        if (ev === 'pushVehicleItem') put(data[0]);
        else if (ev === 'initializeVehicleList') (data[0] || []).forEach(put);
        else if (data[0]) state.byId.forEach((v) => { if (v._index === data[0].index) Object.assign(v, data[0]); });
        scheduleKick();
    };

    let origExec = null;
    let hookOn = true;
    const hooked = function (name, args) {
        if (hookOn) { try { onEvent(String(name), args); } catch (e) {} }
        return origExec.apply(this, arguments);
    };
    // Installed once: an inject can land before Arizona's deferred bundle defines executeEvent, so kick() retries.
    const installHook = () => {
        if (origExec || typeof window.executeEvent !== 'function') return;
        origExec = window.executeEvent;
        window.executeEvent = hooked;
    };
    installHook();
    //endregion

    //region CARDS - read from DOM, matched to packet data by title + quality score (the image falls back to -1.webp on load errors)
    const readCard = (it) => {
        const card = it.querySelector('.vehicle-menu-vehicle-item');
        if (!card) return null;
        const titleEl = card.querySelector('.vehicle-menu-vehicle-item__title');
        const rar = card.querySelector('.vehicle-menu-vehicle-item__item-rarity-title');
        const place = card.querySelector('.vehicle-menu-vehicle-item__item-rarity-placement-value');
        const sm = rar ? rar.textContent.match(/\((\d+)\)/) : null;
        return {
            it,
            title: titleEl ? ownText(titleEl) : '',
            fav: !!card.querySelector('.vehicle-menu-vehicle-item__favorite--active'),
            score: sm ? parseInt(sm[1], 10) : null,
            place: place ? num(place.textContent) : null,
            id: null,
        };
    };
    const keyOf = (title, score) => norm(title) + '|' + (score == null ? '' : score);
    const keyOfData = (v) => keyOf(String(v.title || '').replace(/:[a-z0-9_]+:/gi, ''), v.rarityLevel > 0 ? v.rarityLevel : null);
    // Arizona's own list order (sortItems): loaded first, starred first, then per-group rules, stable over arrival order.
    const arizonaOrder = () => {
        const all = [...state.byId.values()].sort((a, b) => a._index - b._index).map((v, i) => ({
            v, i, loaded: v.status !== 'notLoaded', fav: v.favorite || 0,
        }));
        const cmp = (a, b) => {
            if (a.loaded !== b.loaded) return a.loaded ? -1 : 1;
            const pa = a.fav > 0 ? 1 : 2;
            const pb = b.fav > 0 ? 1 : 2;
            if (pa !== pb) return pa - pb;
            if (a.loaded && a.fav > 0) return b.fav - a.fav;
            if (!a.loaded && a.fav === 0) return b.v.id - a.v.id;
            return 0;
        };
        return all.sort((a, b) => cmp(a, b) || a.i - b.i).map((x) => x.v);
    };
    // Cards follow Arizona's order in the DOM, so a full match by position is exact; otherwise twins stay unsure.
    const attachIds = (cards) => {
        cards.forEach((c) => { c.id = null; c.sure = false; });
        if (!state.byId.size) return 0;
        const seq = arizonaOrder();
        if (seq.length === cards.length && cards.every((c, i) => keyOf(c.title, c.score) === keyOfData(seq[i]))) {
            cards.forEach((c, i) => { c.id = seq[i].id; c.sure = true; });
            return cards.length;
        }
        const pool = new Map();
        seq.slice().sort((a, b) => a.id - b.id).forEach((v) => {
            const k = keyOfData(v);
            if (!pool.has(k)) pool.set(k, []);
            pool.get(k).push(v);
        });
        const twins = new Map();
        cards.forEach((c) => { const k = keyOf(c.title, c.score); twins.set(k, (twins.get(k) || 0) + 1); });
        let n = 0;
        cards.forEach((c) => {
            const k = keyOf(c.title, c.score);
            const arr = pool.get(k);
            const sure = !!arr && arr.length === 1 && twins.get(k) === 1;
            const v = arr && arr.shift();
            if (v) { c.id = v.id; c.sure = sure; n++; }
        });
        return n;
    };
    // Order of the phone's «Мой транспорт»: cars out in the world (a game id plate) by id, then the rest by id.
    // Not by status: besides loaded/notLoaded there are garages, impound, rent, stolen..., all listed by id below.
    const gameIdOf = (v) => {
        const l = (v.labels || []).find((x) => x && x.icon === 'icon-id');
        return l && /^\d+$/.test(String(l.title)) ? String(l.title) : null;
    };
    const isLoaded = (v) => gameIdOf(v) !== null;
    const phoneOrder = () => {
        const all = [...state.byId.values()];
        const byId = (a, b) => a.id - b.id;
        return all.filter(isLoaded).sort(byId).concat(all.filter((v) => !isLoaded(v)).sort(byId));
    };
    const phoneRow = (id) => {
        const order = phoneOrder();
        const row = order.findIndex((v) => v.id === id);
        if (row < 0) return null;
        const v = order[row];
        const gameId = gameIdOf(v) || '-';
        return { row, total: order.length, loaded: order.filter(isLoaded).length, gameId };
    };
    // Support trace for last-call.log: the clicked card and the list in the expected phone order, one car per line.
    const callTrace = (cards, c) => [
        'card: ' + (c ? JSON.stringify(c.title) + ' id=' + c.id + ' sure=' + c.sure : 'not found')
            + ', cards ' + cards.length + ', resolved ' + cards.filter((x) => x.sure).length,
        ...phoneOrder().map((v, i) => [i, 'id=' + v.id, v.status, 'fav=' + (v.favorite || 0), JSON.stringify(String(v.title || '')),
            (v.labels || []).map((l) => l && l.title).join(' / ')].join(' ')),
    ].join('\n');
    const readCards = (list) => [...list.children]
        .filter((x) => x.id !== BAR_ID && x.classList.contains('vehicle-menu-list__item'))
        .map(readCard).filter(Boolean);
    //endregion

    //region SORT & FILTER - order via CSS `order`, never move Svelte's nodes
    const cmpName = (a, b) => a.title.localeCompare(b.title, 'ru', { sensitivity: 'base', numeric: true });
    const nullLast = (x, y, dir) => ((x == null) - (y == null)) || (x == null ? 0 : dir * (x - y));
    const COMPARE = {
        name: cmpName,
        name_desc: (a, b) => cmpName(b, a),
        new: (a, b) => nullLast(a.id, b.id, -1),
        old: (a, b) => nullLast(a.id, b.id, 1),
        rating: (a, b) => nullLast(a.place, b.place, 1) || nullLast(a.score, b.score, -1),
    };
    const sortCards = (cards) => cards.slice().sort((a, b) => (b.fav - a.fav) || COMPARE[state.sort](a, b) || cmpName(a, b));

    const apply = (cards) => {
        const q = norm(state.q);
        let shown = 0;
        cards.forEach((c) => {
            const hide = !!q && norm(c.title).indexOf(q) === -1;
            toggle(c.it, HIDE, hide);
            if (!hide) shown++;
        });
        if (state.sort === 'default') {
            cards.forEach((c) => { if (c.it.style.order) c.it.style.removeProperty('order'); });
        } else {
            sortCards(cards).forEach((c, i) => { const o = String(i + 1); if (c.it.style.order !== o) c.it.style.order = o; });
        }
        return shown;
    };
    //endregion

    //region TOOLBAR - search field and sort filter from Arizona's car rating window, as the list's first block
    const R = 'transport-interaction-rating__sort';
    const E = 'transport-interaction-rating__side-left-empty';
    const EMPTY_ICON = './assets/b003bba07054c8272b10.webp';
    const ensureStyle = () => {
        if (document.getElementById(STYLE_ID)) return;
        const st = el('style');
        st.id = STYLE_ID;
        st.textContent = [
            '.' + FLEX + '{display:flex!important;flex-direction:column}',
            '.' + FLEX + '>*{flex-shrink:0}',
            '.' + HIDE + '{display:none!important}',
            '#' + BAR_ID + '{position:relative;z-index:3;order:-1;display:flex;flex-direction:column;gap:' + gs(10) + ';margin-bottom:' + gs(25) + '}',
            // The rating window sizes these for its full-screen layout; here the field stretches up to the filter button.
            '#' + BAR_ID + ' .' + R + '{margin-top:0}',
            '#' + BAR_ID + ' .' + R + '-input{flex:1 1 auto;margin-left:0}',
            '#' + BAR_ID + ' .' + R + '-input-field{width:100%}',
            '#' + BAR_ID + ' .' + R + '-filter{margin-left:' + gs(10) + ';flex-shrink:0}',
            '#' + BAR_ID + ' .' + R + '-filter-dropdown-item-title{width:' + gs(90) + '}',
            '#' + BAR_ID + ' .' + R + '-filter-dropdown{width:' + gs(342) + '}',
            '#' + BAR_ID + ' .' + R + '-input-field{padding-right:' + gs(48) + '}',
            // Native focus ring is solid white; with a single field the caret is enough.
            '#' + BAR_ID + ' .' + R + '-input-field:focus{outline:none;box-shadow:none}',
            '#' + BAR_ID + ' .ah-clear{position:absolute;right:0;top:50%;transform:translateY(-50%);z-index:1;min-height:' + gs(44) + ';cursor:pointer}',
            // Empty state of the rating window, unpinned from its full-screen centre and scaled down.
            '#' + BAR_ID + ' .' + E + '{position:static;transform:none;gap:' + gs(10) + ';padding:' + gs(20) + ' 0}',
            '#' + BAR_ID + ' .' + E + '-icon-wrapper{width:' + gs(64) + ';height:' + gs(64) + ';border-radius:' + gs(20) + '}',
            '#' + BAR_ID + ' .' + E + '-icon{height:' + gs(34) + '}',
            '#' + BAR_ID + ' .' + E + '-icon-wrapper i{font-size:' + gs(30) + ';color:hsla(0,0%,100%,.6)}',
            '#' + BAR_ID + ' .' + E + '-text{font-size:' + gs(20) + '}',
            '.vehicle-menu-vehicle-item__label.' + CALL + '{cursor:pointer}',
            '.vehicle-menu-vehicle-item__label.' + CALL + ':hover{background-color:hsla(0,0%,100%,.2)}',
        ].join('\n');
        document.head.appendChild(st);
    };

    let ui = null;
    let cards = [];

    // Which car a card shows is resolved at click time: Svelte reuses cards by position.
    const callFor = (it) => {
        const list = document.querySelector(LIST_SEL);
        let msg = 'unknown', trace = 'no list';
        if (list) {
            const all = readCards(list);
            attachIds(all);
            const c = all.find((x) => x.it === it);
            const r = c && c.sure ? phoneRow(c.id) : null;
            if (r) msg = [r.row, r.total, r.loaded, r.gameId, encodeURIComponent(c.title)].join('|');
            trace = callTrace(all, c);
        }
        msg += '|' + encodeURIComponent(trace);
        try { window.cef.SendMessage('__PREFIX__call|' + msg, 0); } catch (e) {}
    };
    // Arizona's own «Вызвать за ...» plate marks a car that cannot be called: it is hidden and gets no chip.
    // Rechecked on every kick, since Svelte reuses label nodes by position.
    const syncCall = (it) => {
        const labels = it.querySelector('.vehicle-menu-vehicle-item__labels');
        if (!labels) return;
        const nativeCall = norm(T.nativeCall);
        let native = false;
        [...labels.children].forEach((l) => {
            if (l.classList.contains(CALL)) return;
            const v = l.querySelector('.vehicle-menu-vehicle-item__label-value');
            const isNative = !!v && norm(v.textContent).indexOf(nativeCall) === 0;
            toggle(l, HIDE, isNative);
            if (isNative) native = true;
        });
        const old = labels.querySelector('.' + CALL);
        if (native) { if (old) old.remove(); return; }
        if (old) return;
        const chip = el('div', 'vehicle-menu-vehicle-item__label ' + CALL);
        chip.append(el('i', 'vehicle-menu-vehicle-item__label-icon icon-gps'), el('div', 'vehicle-menu-vehicle-item__label-value', T.call));
        chip.addEventListener('click', (e) => { e.stopPropagation(); callFor(it); });
        labels.appendChild(chip);
    };

    const setSort = (k) => {
        const changed = k !== state.sort;
        state.sort = k;
        state.open = false;
        if (changed) save();
        kick();
    };

    const buildBar = () => {
        const bar = el('div');
        bar.id = BAR_ID;

        const row = el('div', R);
        const box = el('div', R + '-input');
        const ico = el('i', R + '-input-icon icon-magnifier');
        const clear = el('i', 'inventory-search__search-close ui-close ah-clear');
        const input = el('input', R + '-input-field');
        input.type = 'text';
        input.spellcheck = false;
        input.placeholder = T.search;
        input.value = state.q;
        input.addEventListener('input', (e) => { state.q = e.target.value; kick(); });
        // Enter opens the car when the search leaves exactly one.
        input.addEventListener('keydown', (e) => {
            if (e.key !== 'Enter') return;
            const vis = cards.filter((c) => !c.it.classList.contains(HIDE));
            if (vis.length === 1) vis[0].it.click();
        });
        ico.addEventListener('click', () => input.focus());
        clear.addEventListener('click', () => { state.q = ''; input.value = ''; kick(); input.focus(); });
        box.append(ico, input, clear);

        const filter = el('div', R + '-filter');
        filter.appendChild(el('i', R + '-filter-icon icon-transport-filter'));
        filter.addEventListener('click', (e) => { e.stopPropagation(); state.open = !state.open; kick(); });
        let menu = null;

        row.append(box, filter);
        const empty = el('div', E);
        const emptyIco = el('div', E + '-icon-wrapper');
        const emptyImg = el('img', E + '-icon');
        emptyImg.src = EMPTY_ICON;
        emptyImg.alt = 'not-found';
        // The asset name is a build hash; if Arizona renames it, fall back to the icon font.
        emptyImg.addEventListener('error', () => { emptyImg.replaceWith(el('i', 'icon-magnifier')); });
        emptyIco.appendChild(emptyImg);
        empty.append(emptyIco, el('div', E + '-text', T.emptyTitle), el('div', E + '-caption', T.emptyCaption));
        bar.append(row, empty);

        const items = MODES.map((m) => {
            const it = el('div', R + '-filter-dropdown-item');
            it.append(el('p', R + '-filter-dropdown-item-title', m.t), el('p', R + '-filter-dropdown-item-subTitle', m.s), el('div', R + '-filter-dropdown-item-radio'));
            it.addEventListener('click', (e) => { e.stopPropagation(); setSort(m.k); });
            return { m, it };
        });

        ui = {
            bar,
            render: (shown) => {
                clear.style.display = state.q ? '' : 'none';
                if (input.value !== state.q && document.activeElement !== input) input.value = state.q;
                empty.style.display = state.q && !shown ? '' : 'none';
                toggle(filter, R + '-filter--active', state.open || state.sort !== 'default');
                if (state.open && !menu) {
                    menu = el('div', R + '-filter-dropdown');
                    items.forEach((x) => menu.appendChild(x.it));
                    filter.appendChild(menu);
                } else if (!state.open && menu) {
                    menu.remove();
                    menu = null;
                }
                items.forEach((x) => toggle(x.it, R + '-filter-dropdown-item--active', x.m.k === state.sort));
            },
        };
        return bar;
    };
    //endregion

    //region LOOP - observer on the live list, interval to catch the window opening
    let obs = null;
    let lastList = null;
    const kick = () => {
        installHook();
        const list = document.querySelector(LIST_SEL);
        if (!list) { state.open = false; return; }
        if (list !== lastList) {
            lastList = list;
            state.q = '';
            state.open = false;
            if (obs) obs.disconnect();
            obs = new MutationObserver(scheduleKick);
            obs.observe(list, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['class', 'src'] });
        }
        ensureStyle();
        toggle(list, FLEX, true);
        let bar = document.getElementById(BAR_ID);
        if (!bar || bar.parentNode !== list || !ui || ui.bar !== bar) {
            if (bar) bar.remove();
            bar = buildBar();
            list.insertBefore(bar, list.firstChild);
        }
        cards = readCards(list);
        cards.forEach((c) => syncCall(c.it));
        attachIds(cards);
        ui.render(apply(cards));
    };

    let kickPending = false;
    function scheduleKick() {
        if (kickPending) return;
        kickPending = true;
        setTimeout(() => { kickPending = false; kick(); }, 50);
    }

    const onWinClick = () => { if (state.open) { state.open = false; kick(); } };
    window.addEventListener('click', onWinClick);
    const iv = setInterval(kick, 400);

    const teardown = () => {
        hookOn = false;
        if (origExec && window.executeEvent === hooked) window.executeEvent = origExec;
        clearInterval(iv);
        window.removeEventListener('click', onWinClick);
        if (obs) obs.disconnect();
        const b = document.getElementById(BAR_ID);
        if (b) b.remove();
        const st = document.getElementById(STYLE_ID);
        if (st) st.remove();
        document.querySelectorAll('.' + FLEX).forEach((x) => x.classList.remove(FLEX));
        document.querySelectorAll('.' + CALL).forEach((x) => x.remove());
        document.querySelectorAll('.' + HIDE).forEach((x) => x.classList.remove(HIDE));
        document.querySelectorAll('.vehicle-menu-list__item').forEach((x) => x.style.removeProperty('order'));
        window.__ahCarsPlus = null;
    };

    window.__ahCarsPlus = { version: VERSION, kick, teardown, state };
    kick();
    //endregion
})();
]==]

local function bootJs()
    local js = BOOT_TEMPLATE:gsub('__VERSION__', thisScript().version)
    js = js:gsub('__PREFIX__', MSG_PREFIX)
    js = js:gsub('__SORT__', sortKey())
    return js
end

local TEARDOWN_JS = "(()=>{try{if(window.__ahCarsPlus)window.__ahCarsPlus.teardown();}catch(e){}})()"

local function evalcef(code)
    -- Code length is written as Int16 -> hard cap of 32767 bytes.
    if type(code) ~= 'string' or code == '' or #code > 32767 then return false end
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 17)
    raknetBitStreamWriteInt32(bs, 0)
    raknetBitStreamWriteInt16(bs, #code)
    raknetBitStreamWriteInt8(bs, 0)
    raknetBitStreamWriteString(bs, code)
    raknetEmulPacketReceiveBitStream(220, bs)
    raknetDeleteBitStream(bs)
    return true
end

-- ============================================================================
-- CALL: brings a car through the phone app by picking its row in «Мой транспорт»
-- ============================================================================

-- Matched by title, style and our own wait: dialog ids drift with server updates.
local PCARS_TITLE = cp('Мой транспорт')
local CALL_TIMEOUT = 5 -- seconds to wait for the phone dialog.
local DIALOG_REPLY_DELAY = 0.1 -- seconds; a dialog is never answered from inside its own hook.

-- nil, or { row, total, loaded, gameId, title, stage = 'start'|'wait', deadline }.
local call = nil
local dialogReply = { armed = false, at = 0 }

local function urlDecode(s)
    return (s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

-- Real outgoing CEF event (220/18), unlike evalcef which only emulates an incoming one.
local function sendCefEvent(str)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 18)
    raknetBitStreamWriteInt16(bs, #str)
    raknetBitStreamWriteString(bs, str)
    raknetBitStreamWriteInt32(bs, 0)
    raknetSendBitStream(bs)
    raknetDeleteBitStream(bs)
end

-- Support trace of the last call: config\ArzHub\cars-plus\last-call.log, rewritten on every call and
-- only read when a player sends it in. Hooks only append; the file is written from the main loop.
local CALL_LOG_NAME = 'last-call.log'
local CALL_LOG_WINDOW = 25 -- seconds after the click that dialogs, answers and server lines still go in.
local callLog = nil -- nil, or { lines, untilAt, dirty }.

local function trace(line)
    if not callLog or os.clock() > callLog.untilAt then return end
    callLog.lines[#callLog.lines + 1] = os.date('%H:%M:%S ') .. line
    callLog.dirty = true
end

local function traceStart()
    callLog = { lines = {}, untilAt = os.clock() + CALL_LOG_WINDOW, dirty = true }
    trace('Cars Plus v' .. thisScript().version)
end

local function flushTrace()
    if not callLog or not callLog.dirty then return end
    callLog.dirty = false
    local f = io.open(ensureConfigDir() .. '\\' .. CALL_LOG_NAME, 'wb')
    if not f then return end
    f:write(table.concat(callLog.lines, '\r\n'), '\r\n')
    f:close()
end

-- Dialog and chat text come in CP1251, the log is UTF-8 like the page lines.
local function utf(s) return u8(tostring(s or '')) end

local function replyToDialog(id, button, item, input)
    dialogReply.armed = true
    dialogReply.at = os.clock() + DIALOG_REPLY_DELAY
    dialogReply.id, dialogReply.button, dialogReply.item, dialogReply.input = id, button, item, input
end

local function flushDialogReply()
    if not dialogReply.armed or os.clock() < dialogReply.at then return end
    dialogReply.armed = false
    -- The onSendDialogResponse hook does not see answers sent from Lua, so ours is traced here.
    trace(('answer (script) id=%s button=%s row=%s'):format(tostring(dialogReply.id), tostring(dialogReply.button), tostring(dialogReply.item)))
    sampSendDialogResponse(dialogReply.id, dialogReply.button, dialogReply.item, dialogReply.input)
end

-- The page's call message; a call already in progress wins.
local function handleCall(body)
    if call then return end
    -- The trace is the last field; a bootstrap from 1.0.1 still alive in CEF sends none.
    local head, pageTrace = body:match('^(unknown)|(.*)$')
    if not head then head, pageTrace = body:match('^(%d+|%d+|%d+|[%d%-]+|[^|]*)|(.*)$') end
    if not head then head, pageTrace = body, '' end
    traceStart()
    trace('page: ' .. head)
    for line in (urlDecode(pageTrace) .. '\n'):gmatch('([^\n]*)\n') do
        if line ~= '' then trace('  ' .. line) end
    end
    if head == 'unknown' then
        trace('result: card not resolved')
        notify('Не удалось определить машину. Откройте /cars заново.')
        return
    end
    local row, total, loaded, gameId, title = head:match('^(%d+)|(%d+)|(%d+)|([%d%-]+)|(.*)$')
    if not row then trace('result: bad page message') return end
    call = {
        row = tonumber(row), total = tonumber(total), loaded = tonumber(loaded),
        gameId = gameId ~= '-' and gameId or nil, title = urlDecode(title), stage = 'start',
    }
end

-- One main-loop step: opens the phone app, then gives up if its dialog never comes.
local function stepCall()
    if not call then return end
    if call.stage == 'start' then
        call.stage = 'wait'
        call.deadline = os.clock() + CALL_TIMEOUT
        sampSendChat('/phone')
        sendCefEvent('launchedApp|29')
        sampSendChat('/phone')
        trace('sent /phone, launchedApp|29, /phone')
        notify('Вызываю {FFB48A}' .. call.title .. '{FFFFFF}...')
    elseif os.clock() >= call.deadline then
        call = nil
        trace('result: no «Мой транспорт» dialog in ' .. CALL_TIMEOUT .. ' s')
        notify('Телефон не открыл список машин. Попробуйте ещё раз.')
    end
end

-- Picks the row only when the dialog matches what the page counted; otherwise the player sees it as is.
function sampev.onShowDialog(id, style, title, button1, button2, text)
    trace(('dialog id=%s style=%s title=%s buttons=%s / %s'):format(tostring(id), tostring(style), utf(title), utf(button1), utf(button2)))
    for line in (utf(text) .. '\n'):gmatch('([^\n]*)\n') do trace('  | ' .. line) end
    if not call or call.stage ~= 'wait' or style ~= 4 or not (title or ''):find(PCARS_TITLE, 1, true) then return end
    local c = call
    call = nil
    -- Empty rows count as rows (the server's listitem does), only the trailing ones are dropped.
    local rows = {}
    for line in ((text or '') .. '\n'):gmatch('([^\n]*)\n') do rows[#rows + 1] = line end
    while #rows > 0 and rows[#rows] == '' do rows[#rows] = nil end
    -- Whole shape, not counts: rows with a game id «Name(714)» on top, rows without one below, whatever their mark
    -- («[Не загружено]», «[Гараж дома №745]», ...).
    local ok = #rows == c.total and c.row < c.total
    for i = 1, ok and #rows or 0 do
        if (rows[i]:find('%(%d+%)') ~= nil) ~= (i <= c.loaded) then ok = false break end
    end
    local target = rows[c.row + 1]
    if ok and c.gameId then
        ok = c.row < c.loaded and target:find('(' .. c.gameId .. ')', 1, true) ~= nil
    elseif ok then
        ok = c.row >= c.loaded
    end
    if not ok then
        trace(('result: mismatch - %d rows, expected %d with %d loaded, row %d, game id %s')
            :format(#rows, c.total, c.loaded, c.row, tostring(c.gameId)))
        notify('Список в телефоне не совпал с «Мои Т/С» - выберите машину сами.')
        return
    end
    trace(('result: picked row %d: %s'):format(c.row, utf(target)))
    replyToDialog(id, 1, c.row, '')
    return false
end

-- Who answered which dialog and what the server said, for the trace window only.
function sampev.onSendDialogResponse(id, button, item, input)
    trace(('answer id=%s button=%s item=%s input=%s'):format(tostring(id), tostring(button), tostring(item), utf(input)))
end

-- The server refuses a call in chat (green zone, in a car...): no dialog will come, its own line says why.
local SERVER_ERROR = cp('[Ошибка]')

function sampev.onServerMessage(color, text)
    trace('chat: ' .. utf(text))
    if call and call.stage == 'wait' and tostring(text or ''):find(SERVER_ERROR, 1, true) then
        call = nil
        trace('result: server refused')
    end
end

-- Our page messages never reach the server; returns false for them.
local function handleOutgoing(str)
    if str:sub(1, #MSG_PREFIX) ~= MSG_PREFIX then return end
    local body = str:sub(#MSG_PREFIX + 1)
    local callBody = body:match('^call|(.*)$')
    if callBody then
        handleCall(callBody)
        return false
    end
    local key = body:match('^sort|([%w_]+)$')
    if key and SORT_KEYS[key] and key ~= config.settings.sort then
        config.settings.sort = key
        saveConfig()
    end
    return false
end

local function readOutgoing(bs)
    raknetBitStreamIgnoreBits(bs, 8)
    if raknetBitStreamReadInt8(bs) ~= 18 then return end
    local length = raknetBitStreamReadInt16(bs)
    return handleOutgoing(raknetBitStreamReadString(bs, length))
end

-- return false only outside pcall: from inside it would not reach the game.
function onSendPacket(id, bs)
    if id ~= 220 then return end
    raknetBitStreamResetReadPointer(bs)
    local ok, result = pcall(readOutgoing, bs)
    raknetBitStreamResetReadPointer(bs)
    if not ok then print('onSendPacket: ' .. tostring(result)) return end
    if result == false then return false end
end

-- ============================================================================
-- UPDATES (/cpupdate): only through the ArzHub manager, the script just says where to get them
-- ============================================================================

local UPDATE_MANIFEST_URL = 'https://arzhub.top/hub/manifest.json'
local UPDATE_SCRIPT_ID = 'cars-plus'
local UPDATE_MANIFEST_TIMEOUT = 10 -- seconds.
local MANAGER_URL = 'https://arzhub.top/hub'
local VIA_MANAGER = 'Обновления - через менеджер ArzHub: {FFB48A}' .. MANAGER_URL

-- "2.10.0" -> 2010000, so versions compare numerically.
local function versionNum(v)
    local a, b, c = tostring(v or ''):match('^(%d+)%.(%d+)%.(%d+)$')
    if not a then return nil end
    return tonumber(a) * 1000000 + tonumber(b) * 1000 + tonumber(c)
end

-- Unguarded on purpose: removing a missing file is a harmless no-op.
local function removeIfExists(path)
    return os.remove(path)
end

-- Whichever of {callback, timeout} fires first wins, the other one is a no-op.
local function withTimeout(seconds, onTimeout)
    local done = false
    lua_thread.create(function()
        wait(seconds * 1000)
        if not done then
            done = true
            onTimeout()
        end
    end)
    return function()
        if done then return false end
        done = true
        return true
    end
end

-- Asked right before a line goes out, not at load: by then every script is loaded.
local function managerRunning()
    return script.find('ArzHub') ~= nil
end

-- Exactly one of onEntry(entry) / onError() fires.
local function fetchManifestEntry(onEntry, onError)
    local manifestPath = thisScript().path .. '.manifest.tmp'
    removeIfExists(manifestPath)
    local dl_status = moonloader.download_status
    local claim = withTimeout(UPDATE_MANIFEST_TIMEOUT, function()
        removeIfExists(manifestPath)
        onError()
    end)

    -- Only the final status: at STATUS_ENDDOWNLOADDATA the file may not be in place yet, and decodeJson('') is logged as an exception even under pcall.
    downloadUrlToFile(UPDATE_MANIFEST_URL, manifestPath, function(_, status)
        if status ~= dl_status.STATUSEX_ENDDOWNLOAD or not claim() then return end
        local content = readFile(manifestPath)
        removeIfExists(manifestPath)
        if not content or content == '' then
            onError()
            return
        end
        local ok, data = pcall(decodeJson, content)
        if not ok or type(data) ~= 'table' or not data.scripts then
            onError()
            return
        end
        for _, item in ipairs(data.scripts) do
            if item.id == UPDATE_SCRIPT_ID then
                onEntry(item)
                return
            end
        end
        onError()
    end)
end

-- Strictly "remote > local": a newer local build is never offered an older one.
local function isNewer(entry)
    local remote, current = versionNum(entry.version), versionNum(thisScript().version)
    return remote and current and remote > current
end

local function newVersionText(entry)
    return 'Вышла {FFB48A}v' .. entry.version .. '{FFFFFF}. Обновить можно через менеджер ArzHub: {FFB48A}' .. MANAGER_URL
end

local function checkForUpdate()
    if managerRunning() then
        notify('Обновления - через менеджер: {FFB48A}/hub')
        return
    end
    fetchManifestEntry(
        function(entry)
            if isNewer(entry) then
                notify(newVersionText(entry))
            else
                notify('У вас последняя версия {FFB48A}v' .. thisScript().version .. '{FFFFFF}. ' .. VIA_MANAGER)
            end
        end,
        function()
            notify('Не удалось проверить обновления. ' .. VIA_MANAGER)
        end
    )
end

-- Once at load, and only without the manager: silent unless a new version is out.
local function checkForUpdateSilently()
    if managerRunning() then return end
    fetchManifestEntry(
        function(entry)
            if isNewer(entry) and not managerRunning() then notify(newVersionText(entry)) end
        end,
        function() end
    )
end

function onScriptTerminate(s)
    if s == thisScript() then evalcef(TEARDOWN_JS) end
end

function main()
    while not isSampAvailable() do wait(0) end
    -- Leftovers of an interrupted update by an older build; .old stays as the way back.
    removeIfExists(thisScript().path .. '.tmp')
    removeIfExists(thisScript().path .. '.manifest.tmp')
    wait(1500)

    notify('Загружен {FFB48A}v' .. thisScript().version .. '{FFFFFF}. Список машин в /cars стал удобнее.')
    sampRegisterChatCommand('cpupdate', checkForUpdate)
    checkForUpdateSilently()

    -- CEF starts asynchronously; re-inject forever to catch a recreated context, the version guard makes it a no-op otherwise.
    wait(2000)
    local nextInject = 0
    while true do
        flushDialogReply()
        stepCall()
        flushTrace()
        if os.clock() >= nextInject then
            evalcef(bootJs())
            nextInject = os.clock() + 5
        end
        wait(100)
    end
end
