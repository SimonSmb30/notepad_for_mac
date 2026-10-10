// Rendert die Vorschau einer Datei. Die App ruft die Seite mit ?kind=…&doc=… auf:
// `kind` ist die Art der Darstellung, `doc` die Adresse des Textes.
(function () {
    'use strict';

    var app = new URL('.', document.currentScript.src).href;
    var params = new URLSearchParams(location.search);
    var kind = params.get('kind');
    var docURL = new URL(params.get('doc'), location.href).href;
    var extension = (params.get('ext') || '').toLowerCase();
    var content = document.getElementById('content');
    document.documentElement.lang = params.get('lang') || 'en';
    var style = getComputedStyle(document.documentElement);
    var dark = style.getPropertyValue('--dark').trim() === '1';

    // Relative Bilder und Links beziehen sich auf den Ordner der Datei.
    var base = document.createElement('base');
    base.href = docURL;
    document.head.appendChild(base);

    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined) node.textContent = text;
        return node;
    }

    var loading = {};
    function load(name) {
        loading[name] = loading[name] || new Promise(function (resolve, reject) {
            var node;
            if (/\.css$/.test(name)) {
                node = el('link');
                node.rel = 'stylesheet';
                node.href = app + name;
            } else {
                node = el('script');
                node.src = app + name;
            }
            node.onload = resolve;
            node.onerror = function () { reject(new Error(name)); };
            document.head.appendChild(node);
        });
        return loading[name];
    }
    function loadAll(names) {
        return names.reduce(function (chain, name) {
            return chain.then(function () { return load(name); });
        }, Promise.resolve());
    }

    function fail(error) {
        content.textContent = '';
        var box = el('div', 'error');
        box.appendChild(el('strong', '', document.documentElement.lang === 'de'
            ? 'Die Vorschau kann nicht angezeigt werden.' : 'The preview cannot be shown.'));
        box.appendChild(el('pre', '', String(error && error.message || error)));
        content.appendChild(box);
    }

    /// Rohes HTML aus der Datei, ohne alles, was Code ausführen oder nachladen könnte.
    function sanitize(html) {
        var parsed = new DOMParser().parseFromString(html, 'text/html');
        parsed.querySelectorAll('script, iframe, object, embed, base, meta, link, form').forEach(function (node) {
            node.remove();
        });
        parsed.querySelectorAll('*').forEach(function (node) {
            Array.prototype.slice.call(node.attributes).forEach(function (attribute) {
                var name = attribute.name.toLowerCase();
                var value = attribute.value.replace(/\s+/g, '').toLowerCase();
                if (name.indexOf('on') === 0 || value.indexOf('javascript:') === 0) node.removeAttribute(attribute.name);
            });
        });
        var fragment = document.createDocumentFragment();
        while (parsed.body.firstChild) fragment.appendChild(document.adoptNode(parsed.body.firstChild));
        return fragment;
    }

    function highlight(code, language) {
        if (language && window.hljs && hljs.getLanguage(language)) {
            try {
                return hljs.highlight(code, { language: language, ignoreIllegals: true }).value;
            } catch (error) { /* bleibt einfarbig */ }
        }
        return '';
    }

    // MARK: Markdown

    /// Formeln zwischen $…$ und $$…$$, bevor Markdown Unterstriche und Sterne darin deutet.
    function mathPlugin(md) {
        md.inline.ruler.before('escape', 'math', function (state, silent) {
            var source = state.src, start = state.pos;
            if (source.charCodeAt(start) !== 0x24) return false;
            var block = source.charCodeAt(start + 1) === 0x24;
            var open = start + (block ? 2 : 1);
            var marker = block ? '$$' : '$';
            if (!block && /\s/.test(source.charAt(open))) return false;
            var close = open;
            for (;;) {
                close = source.indexOf(marker, close);
                if (close < 0) return false;
                if (source.charAt(close - 1) !== '\\') break;
                close += 1;
            }
            if (close === open) return false;
            if (!block && (/\s/.test(source.charAt(close - 1)) || /\d/.test(source.charAt(close + 1)))) return false;
            if (!silent) {
                var token = state.push(block ? 'math_block' : 'math_inline', 'span', 0);
                token.content = source.slice(open, close);
            }
            state.pos = close + marker.length;
            return true;
        });
        md.renderer.rules.math_inline = function (tokens, index) {
            return '<span class="math">' + md.utils.escapeHtml(tokens[index].content) + '</span>';
        };
        md.renderer.rules.math_block = function (tokens, index) {
            return '<span class="math math-block">' + md.utils.escapeHtml(tokens[index].content) + '</span>';
        };
    }

    var markdown;
    function markdownLibraries() {
        return loadAll(['highlight.min.js', 'markdown-it.min.js']).then(function () {
            markdown = markdown || window.markdownit({ html: true, linkify: true, highlight: highlight }).use(mathPlugin);
        });
    }

    /// Wie GitHub: Kleinbuchstaben, Leerzeichen zu Bindestrichen, Satzzeichen weg.
    function slug(text, used) {
        var id = text.trim().toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s/g, '-');
        var unique = id, count = 0;
        while (used[unique]) unique = id + '-' + (++count);
        used[unique] = true;
        return unique;
    }

    /// Rendert Markdown nach `target` und gibt zurück, was danach noch geladen werden muss.
    function renderMarkdown(text, target) {
        target.appendChild(sanitize(markdown.render(text)));
        var used = {};
        target.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(function (heading) {
            if (!heading.id) heading.id = slug(heading.textContent, used);
        });
        target.querySelectorAll('li').forEach(function (item) {
            var first = item.firstChild;
            if (first && first.nodeName === 'P') first = first.firstChild;
            var match = first && first.nodeType === 3 && /^\[([ xX])\]\s+/.exec(first.nodeValue);
            if (!match) return;
            first.nodeValue = first.nodeValue.slice(match[0].length);
            var box = el('input');
            box.type = 'checkbox';
            box.disabled = true;
            box.checked = match[1] !== ' ';
            first.parentNode.insertBefore(box, first);
            item.classList.add('task');
        });
        target.querySelectorAll('pre > code.language-mermaid').forEach(function (code) {
            code.parentNode.replaceWith(el('div', 'mermaid', code.textContent));
        });
    }

    function finishMath(target) {
        var nodes = target.querySelectorAll('.math');
        if (!nodes.length) return Promise.resolve();
        return loadAll(['katex.min.css', 'katex.min.js']).then(function () {
            nodes.forEach(function (node) {
                katex.render(node.textContent, node, {
                    displayMode: node.classList.contains('math-block'), throwOnError: false,
                });
            });
        });
    }

    function finishMermaid(target) {
        var nodes = target.querySelectorAll('.mermaid');
        if (!nodes.length) return Promise.resolve();
        return load('mermaid.min.js').then(function () {
            mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: dark ? 'dark' : 'default' });
            return mermaid.run({ nodes: Array.prototype.slice.call(nodes), suppressErrors: false });
        });
    }

    // MARK: Tabelle

    function parseTable(text, delimiter) {
        var rows = [], row = [], field = '', quoted = false, index = 0, length = text.length;
        while (index < length) {
            var c = text.charAt(index);
            if (quoted) {
                if (c === '"') {
                    if (text.charAt(index + 1) === '"') { field += '"'; index += 1; } else quoted = false;
                } else field += c;
            } else if (c === '"' && field === '') {
                quoted = true;
            } else if (c === delimiter) {
                row.push(field); field = '';
            } else if (c === '\n' || c === '\r') {
                if (c === '\r' && text.charAt(index + 1) === '\n') index += 1;
                row.push(field); field = '';
                rows.push(row); row = [];
            } else field += c;
            index += 1;
        }
        if (field !== '' || row.length) { row.push(field); rows.push(row); }
        return rows.filter(function (cells) { return cells.length > 1 || cells[0] !== ''; });
    }

    function renderTable(text) {
        var firstLine = text.split(/\r?\n/, 1)[0] || '';
        var delimiter = extension === 'tsv' ? '\t' : [',', ';', '\t', '|'].map(function (candidate) {
            return [candidate, firstLine.split(candidate).length];
        }).sort(function (a, b) { return b[1] - a[1]; })[0][0];
        var rows = parseTable(text.replace(/^﻿/, ''), delimiter);
        if (!rows.length) return;

        var limit = 5000, total = rows.length - 1;
        var table = el('table', 'sheet'), head = el('thead'), body = el('tbody');
        var header = el('tr');
        header.appendChild(el('th', 'row', ''));
        rows[0].forEach(function (cell) { header.appendChild(el('th', '', cell)); });
        head.appendChild(header);
        rows.slice(1, limit + 1).forEach(function (cells, index) {
            var line = el('tr');
            line.appendChild(el('td', 'row', String(index + 1)));
            cells.forEach(function (cell) {
                line.appendChild(el('td', /^\s*-?[\d.,]+\s*%?$/.test(cell) && /\d/.test(cell) ? 'n' : '', cell));
            });
            body.appendChild(line);
        });
        table.appendChild(head);
        table.appendChild(body);
        document.body.classList.add('wide');
        content.appendChild(table);
        if (total > limit) {
            content.appendChild(el('p', 'note', document.documentElement.lang === 'de'
                ? 'Die ersten ' + limit + ' von ' + total + ' Zeilen.' : 'First ' + limit + ' of ' + total + ' rows.'));
        }
    }

    // MARK: Baum

    function scalar(value) {
        if (value === null || value === undefined) return el('span', 'literal', 'null');
        if (typeof value === 'string') return el('span', 'string', JSON.stringify(value));
        if (typeof value === 'number' || typeof value === 'bigint') return el('span', 'number', String(value));
        if (typeof value === 'boolean') return el('span', 'literal', String(value));
        return el('span', 'string', value instanceof Date && !isNaN(value) ? value.toISOString() : String(value));
    }

    function label(key) {
        var fragment = document.createDocumentFragment();
        if (key !== null) {
            fragment.appendChild(el('span', 'key', String(key)));
            fragment.appendChild(document.createTextNode(': '));
        }
        return fragment;
    }

    /// Äste füllen sich erst beim Aufklappen, damit auch große Dateien sofort erscheinen.
    function branch(summary, open, fill) {
        var details = el('details'), filled = false;
        details.appendChild(summary);
        function populate() {
            if (filled) return;
            filled = true;
            fill(details);
        }
        details.addEventListener('toggle', function () { if (details.open) populate(); });
        if (open) { details.open = true; populate(); }
        return details;
    }

    function valueNode(key, value, depth) {
        var isArray = Array.isArray(value);
        var isObject = value && typeof value === 'object' && !isArray && !(value instanceof Date);
        if (!isArray && !isObject) {
            var leaf = el('div', 'leaf');
            leaf.appendChild(label(key));
            leaf.appendChild(scalar(value));
            return leaf;
        }
        var keys = isArray ? null : Object.keys(value);
        var count = isArray ? value.length : keys.length;
        var summary = el('summary');
        summary.appendChild(label(key));
        summary.appendChild(el('span', 'count', isArray ? '[' + count + ']' : '{' + count + '}'));
        return branch(summary, depth < 2, function (details) {
            var limit = 1000;
            for (var index = 0; index < Math.min(count, limit); index++) {
                var childKey = isArray ? index : keys[index];
                details.appendChild(valueNode(childKey, value[childKey], depth + 1));
            }
            if (count > limit) details.appendChild(el('div', 'leaf count', '… +' + (count - limit)));
        });
    }

    function renderValue(value) {
        var tree = el('div', 'tree');
        tree.appendChild(valueNode(null, value, 0));
        content.appendChild(tree);
    }

    function elementNode(element, depth) {
        var children = Array.prototype.filter.call(element.childNodes, function (node) {
            return node.nodeType === 1 || ((node.nodeType === 3 || node.nodeType === 4) && node.nodeValue.trim() !== '');
        });
        var head = document.createDocumentFragment();
        head.appendChild(el('span', 'tag', '<' + element.nodeName));
        Array.prototype.forEach.call(element.attributes, function (attribute) {
            head.appendChild(document.createTextNode(' '));
            head.appendChild(el('span', 'key', attribute.name));
            head.appendChild(document.createTextNode('='));
            head.appendChild(el('span', 'string', '"' + attribute.value + '"'));
        });
        head.appendChild(el('span', 'tag', '>'));
        if (!children.length || (children.length === 1 && children[0].nodeType !== 1)) {
            var leaf = el('div', 'leaf');
            leaf.appendChild(head);
            if (children.length) leaf.appendChild(document.createTextNode(' ' + children[0].nodeValue.trim()));
            return leaf;
        }
        var summary = el('summary');
        summary.appendChild(head);
        return branch(summary, depth < 3, function (details) {
            children.forEach(function (child) {
                details.appendChild(child.nodeType === 1 ? elementNode(child, depth + 1) : el('div', 'leaf', child.nodeValue.trim()));
            });
        });
    }

    /// Eine Property List als gewöhnliche Werte, damit sie wie JSON erscheint.
    function plistValue(node) {
        var children = Array.prototype.slice.call(node.children);
        switch (node.nodeName) {
        case 'dict':
            var result = {};
            for (var index = 0; index + 1 < children.length; index += 2) {
                result[children[index].textContent] = plistValue(children[index + 1]);
            }
            return result;
        case 'array': return children.map(plistValue);
        case 'integer': case 'real': return Number(node.textContent);
        case 'true': return true;
        case 'false': return false;
        default: return node.textContent;
        }
    }

    function renderXML(text) {
        var parsed = new DOMParser().parseFromString(text, 'application/xml');
        var problem = parsed.querySelector('parsererror');
        if (problem) throw new Error(problem.textContent.trim());
        var root = parsed.documentElement;
        if (root.nodeName === 'plist' && root.firstElementChild) {
            renderValue(plistValue(root.firstElementChild));
            return;
        }
        var tree = el('div', 'tree');
        tree.appendChild(elementNode(root, 0));
        content.appendChild(tree);
    }

    // MARK: Notebook

    function joined(source) {
        return Array.isArray(source) ? source.join('') : String(source === undefined ? '' : source);
    }

    function renderNotebook(text) {
        var notebook = JSON.parse(text);
        var info = notebook.metadata || {};
        var language = (info.language_info && info.language_info.name) || (info.kernelspec && info.kernelspec.language) || 'python';
        var page = el('div', 'prose');
        content.appendChild(page);
        (notebook.cells || []).forEach(function (cell) {
            var box = el('div', 'cell');
            page.appendChild(box);
            var source = joined(cell.source);
            if (cell.cell_type === 'markdown') {
                renderMarkdown(source, box);
                return;
            }
            if (cell.cell_type !== 'code') {
                box.appendChild(el('pre', '', source));
                return;
            }
            box.appendChild(el('div', 'label', 'In [' + (cell.execution_count == null ? ' ' : cell.execution_count) + ']:'));
            var pre = el('pre'), code = el('code');
            var colored = highlight(source, language);
            if (colored) code.innerHTML = colored; else code.textContent = source;
            pre.appendChild(code);
            box.appendChild(pre);
            (cell.outputs || []).forEach(function (output) {
                var out = el('div', 'output');
                var data = output.data || {};
                if (output.output_type === 'stream') {
                    out.appendChild(el('pre', '', joined(output.text)));
                } else if (output.output_type === 'error') {
                    out.classList.add('failed');
                    out.appendChild(el('pre', '', (output.traceback || [output.ename + ': ' + output.evalue]).join('\n').replace(/\u001b\[[0-9;]*m/g, '')));
                } else if (data['image/png'] || data['image/jpeg']) {
                    var type = data['image/png'] ? 'image/png' : 'image/jpeg';
                    var image = el('img');
                    image.src = 'data:' + type + ';base64,' + joined(data[type]).replace(/\s/g, '');
                    out.appendChild(image);
                } else if (data['image/svg+xml']) {
                    var picture = el('img');
                    picture.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(joined(data['image/svg+xml']));
                    out.appendChild(picture);
                } else if (data['text/html']) {
                    out.appendChild(sanitize(joined(data['text/html'])));
                } else if (data['text/markdown']) {
                    renderMarkdown(joined(data['text/markdown']), out);
                } else if (data['text/latex']) {
                    out.appendChild(el('span', 'math math-block', joined(data['text/latex']).replace(/^\s*\$\$?|\$\$?\s*$/g, '')));
                } else if (data['text/plain']) {
                    out.appendChild(el('pre', '', joined(data['text/plain'])));
                }
                if (out.firstChild) box.appendChild(out);
            });
        });
        return page;
    }

    // MARK: Diff

    function renderDiff(text) {
        var view = el('div', 'diff');
        text.split(/\r?\n/).forEach(function (line) {
            var kind = '';
            if (/^(diff |index |--- |\+\+\+ |new file|deleted file|rename |similarity |Index: |={10,})/.test(line)) kind = 'meta';
            else if (line.indexOf('@@') === 0) kind = 'hunk';
            else if (line.charAt(0) === '+') kind = 'add';
            else if (line.charAt(0) === '-') kind = 'del';
            view.appendChild(el('div', kind, line));
        });
        document.body.classList.add('wide');
        content.appendChild(view);
    }

    // MARK: Diagramme

    function renderGraph(text) {
        return load('viz-global.js').then(function () {
            return Viz.instance();
        }).then(function (viz) {
            var color = style.getPropertyValue('--text').trim();
            var graph = el('div', 'graph');
            graph.appendChild(viz.renderSVGElement(text, {
                graphAttributes: { bgcolor: 'transparent' },
                nodeAttributes: { color: color, fontcolor: color },
                edgeAttributes: { color: color, fontcolor: color },
            }));
            content.appendChild(graph);
        });
    }

    // MARK: Ablauf

    function render(text) {
        switch (kind) {
        case 'markdown':
            return markdownLibraries().then(function () {
                var page = el('div', 'prose');
                content.appendChild(page);
                renderMarkdown(text, page);
                return finishMath(page).then(function () { return finishMermaid(page); });
            });
        case 'notebook':
            return markdownLibraries().then(function () {
                var page = renderNotebook(text);
                return finishMath(page).then(function () { return finishMermaid(page); });
            });
        case 'svg':
            return new Promise(function (resolve, reject) {
                var canvas = el('div', 'canvas'), image = el('img');
                image.onload = resolve;
                image.onerror = function () { reject(new Error('SVG')); };
                image.src = docURL;
                canvas.appendChild(image);
                content.appendChild(canvas);
            });
        case 'table':
            return renderTable(text);
        case 'json':
            return renderValue(JSON.parse(text));
        case 'yaml':
            return load('js-yaml.min.js').then(function () {
                var documents = jsyaml.loadAll(text);
                renderValue(documents.length === 1 ? documents[0] : documents);
            });
        case 'toml':
            return loadAll(['preview-cjs.js', 'smol-toml.cjs']).then(function () {
                renderValue(window.exports.parse(text));
            });
        case 'xml':
            return renderXML(text);
        case 'mermaid':
            content.appendChild(el('div', 'mermaid', text));
            return finishMermaid(content);
        case 'graphviz':
            return renderGraph(text);
        case 'diff':
            return renderDiff(text);
        default:
            throw new Error(kind);
        }
    }

    // Sprungmarken wie [Text](#abschnitt) würden wegen <base> die Seite verlassen.
    document.addEventListener('click', function (event) {
        var link = event.target.closest && event.target.closest('a[href^="#"]');
        if (!link) return;
        event.preventDefault();
        var target = document.getElementById(decodeURIComponent(link.getAttribute('href').slice(1)));
        if (target) target.scrollIntoView();
    });

    fetch(docURL).then(function (response) {
        if (!response.ok) throw new Error(String(response.status));
        return response.text();
    }).then(render).catch(fail).then(function () {
        // Für die App: fertig, auch wenn nur eine Fehlermeldung zu sehen ist.
        document.documentElement.dataset.ready = '1';
    });
})();
