# Confluence REST API 8.5.6: полное руководство по интеграции

Confluence Data Center/Server 8.5.6 предоставляет мощный REST API v1, позволяющий создавать страницы из мобильных приложений, реализовать двустороннюю синхронизацию с Obsidian и управлять версиями контента. Ключевые особенности: авторизация через Basic Auth с AD-креденциалами, контент в формате Confluence Storage Format (XHTML), обязательное версионирование при обновлениях и CQL для поиска. Ниже — полная техническая документация с примерами кода.

---

## Авторизация и базовая конфигурация API

Все запросы к REST API требуют авторизации. Confluence Server/Data Center поддерживает **Basic Authentication** — идеально для интеграции с AD-креденциалами.

### Структура запроса

```bash
# Базовый URL
http://{host}:{port}/{context}/rest/api/{resource}

# Пример
http://confluence.company.local:8080/confluence/rest/api/content
```

### HTTP-заголовки

| Заголовок | Значение | Когда требуется |
|-----------|----------|-----------------|
| `Authorization` | `Basic base64(username:password)` | Всегда |
| `Content-Type` | `application/json` | POST/PUT запросы |
| `Accept` | `application/json` | Рекомендуется |
| `X-Atlassian-Token` | `no-check` | Загрузка вложений |

### Python-клиент с Basic Auth

```python
import requests
from requests.auth import HTTPBasicAuth
import json

class ConfluenceClient:
    def __init__(self, base_url, username, password):
        self.base_url = base_url.rstrip('/')
        self.auth = HTTPBasicAuth(username, password)
        self.headers = {"Content-Type": "application/json", "Accept": "application/json"}
    
    def _request(self, method, endpoint, **kwargs):
        url = f"{self.base_url}/rest/api/{endpoint}"
        response = requests.request(method, url, auth=self.auth, headers=self.headers, **kwargs)
        response.raise_for_status()
        return response.json() if response.content else None

# Инициализация с AD-креденциалами
client = ConfluenceClient(
    "http://confluence.company.local:8080/confluence",
    "ad_username",
    "ad_password"
)
```

**Рекомендации по безопасности**: всегда используйте HTTPS, храните креденциалы в secrets management, рассмотрите Personal Access Tokens (доступны с Confluence 7.9+).

---

## Часть 1: Vanta Speech — создание страниц из meeting summaries

### Создание страницы — POST /rest/api/content

Эндпоинт для создания новой страницы в указанном пространстве с опциональной родительской страницей.

```bash
curl -u ad_user:password -X POST \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "page",
    "title": "Meeting Summary - 2026-01-19",
    "space": {"key": "TEAM"},
    "ancestors": [{"id": "123456"}],
    "body": {
      "storage": {
        "value": "<h1>Weekly Sync</h1><p>Agenda and notes...</p>",
        "representation": "storage"
      }
    }
  }' \
  "http://confluence:8080/confluence/rest/api/content/"
```

**Обязательные параметры:**
- `type`: `"page"` для страниц
- `title`: уникальное название в пределах space
- `space.key`: ключ пространства (например, `"TEAM"`)
- `body.storage.value`: контент в Storage Format
- `body.storage.representation`: всегда `"storage"`

**Опциональные параметры:**
- `ancestors`: массив `[{"id": parentPageId}]` для создания дочерней страницы

### Confluence Storage Format для meeting summaries

Confluence **не поддерживает Markdown напрямую** — контент передаётся в XHTML-подобном Storage Format.

```python
def create_meeting_summary(title, date, attendees, notes, action_items):
    """Генерация Storage Format для саммари встречи"""
    
    attendees_html = ''.join([f'<li>{a}</li>' for a in attendees])
    
    tasks_html = ''
    for item in action_items:
        tasks_html += f'''
        <ac:task>
            <ac:task-status>incomplete</ac:task-status>
            <ac:task-body>{item["task"]} — {item["owner"]}</ac:task-body>
        </ac:task>'''
    
    return f'''
    <h1>{title}</h1>
    <p><strong>Дата:</strong> {date}</p>
    
    <h2>Участники</h2>
    <ul>{attendees_html}</ul>
    
    <h2>Заметки</h2>
    <p>{notes}</p>
    
    <h2>Action Items</h2>
    <ac:task-list>{tasks_html}</ac:task-list>
    '''
```

### Конвертация Markdown в Storage Format

```python
import re

def markdown_to_storage(md_text):
    """Базовый конвертер Markdown → Confluence Storage Format"""
    text = md_text
    
    # Заголовки
    text = re.sub(r'^### (.+)$', r'<h3>\1</h3>', text, flags=re.MULTILINE)
    text = re.sub(r'^## (.+)$', r'<h2>\1</h2>', text, flags=re.MULTILINE)
    text = re.sub(r'^# (.+)$', r'<h1>\1</h1>', text, flags=re.MULTILINE)
    
    # Форматирование
    text = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', text)
    text = re.sub(r'\*(.+?)\*', r'<em>\1</em>', text)
    
    # Списки
    text = re.sub(r'^- (.+)$', r'<li>\1</li>', text, flags=re.MULTILINE)
    
    # Параграфы
    lines = text.split('\n')
    result = []
    for line in lines:
        if line.strip() and not line.startswith('<'):
            result.append(f'<p>{line}</p>')
        else:
            result.append(line)
    
    return '\n'.join(result)
```

**Для production рекомендуется библиотека md2cf** (Python) с полноценным Mistune-рендерером.

### Выбор пространства — GET /rest/api/space

```python
def get_spaces(self, limit=100, space_type='global'):
    """Получить список доступных пространств"""
    params = {'limit': limit, 'type': space_type, 'expand': 'description'}
    return self._request('GET', 'space', params=params)

# Использование
spaces = client.get_spaces()
for space in spaces['results']:
    print(f"{space['key']}: {space['name']}")
```

### Работа с вложениями

**Загрузка файла к странице:**

```python
def upload_attachment(self, page_id, file_path, comment=""):
    """Загрузить вложение к странице"""
    url = f"{self.base_url}/rest/api/content/{page_id}/child/attachment"
    
    headers = {"X-Atlassian-Token": "no-check"}  # Обязательно!
    
    with open(file_path, 'rb') as f:
        files = {'file': (file_path.split('/')[-1], f)}
        response = requests.post(url, auth=self.auth, headers=headers, 
                                files=files, data={'comment': comment})
    return response.json()
```

**Ссылка на вложение в контенте:**

```xml
<!-- Изображение -->
<ac:image><ri:attachment ri:filename="screenshot.png"/></ac:image>

<!-- Файл-ссылка -->
<ac:link>
  <ri:attachment ri:filename="recording.mp3"/>
  <ac:plain-text-link-body><![CDATA[Запись встречи]]></ac:plain-text-link-body>
</ac:link>
```

---

## Часть 2: Obsidian-плагин — двусторонняя синхронизация

### Существующие плагины Obsidian ↔ Confluence

| Плагин | GitHub | Направление | Server/Cloud |
|--------|--------|-------------|--------------|
| **Confluence Integration** | github.com/markdown-confluence/obsidian-integration | Push only | Cloud only |
| **Confluence Space Sync** | github.com/pwnyprod/obsidian-confluence-space-sync-plugin | Pull only | Both |
| **obsidian-confluence-sync** (kerry) | github.com/kerry/obsidian-confluence-sync | Push only | Both |

**Критический вывод**: ни один существующий плагин не реализует полноценную двустороннюю синхронизацию. Для self-hosted Confluence Data Center потребуется собственная реализация.

### API-эндпоинты для синхронизации

**Чтение страниц (Pull):**
```bash
# По ID с контентом
GET /rest/api/content/{pageId}?expand=body.storage,version,ancestors

# По названию в пространстве
GET /rest/api/content?title={title}&spaceKey={key}&expand=body.storage

# Все страницы пространства
GET /rest/api/space/{spaceKey}/content/page?expand=body.storage,version
```

**Обновление страниц (Push):**
```bash
PUT /rest/api/content/{pageId}
# Тело запроса должно включать version.number = текущая версия + 1
```

**Удаление:**
```bash
DELETE /rest/api/content/{pageId}
# Возвращает HTTP 204 при успехе
```

### Архитектура двусторонней синхронизации

```
┌─────────────────┐         ┌─────────────────┐
│   Obsidian      │ ◄─────► │   Confluence    │
│   Vault         │         │   Space         │
├─────────────────┤         ├─────────────────┤
│ folder/         │ ═══════ │ Parent Page     │
│   note.md       │ ═══════ │   Child Page    │
│   sub/          │ ═══════ │     Grandchild  │
│     deep.md     │         │                 │
└─────────────────┘         └─────────────────┘
```

### Механизм синхронизации через frontmatter

Каждый Markdown-файл хранит метаданные синхронизации:

```yaml
---
confluence-id: "12345"
confluence-version: 5
confluence-space: "PROJ"
confluence-parent-id: "12340"
last-sync: "2026-01-19T10:30:00Z"
---

# Page Content
Regular markdown content here...
```

### Алгоритм определения направления синхронизации

```python
def detect_sync_direction(local_file, remote_page_id, confluence_client):
    """Определить: PUSH, PULL, CONFLICT или SYNCED"""
    
    # Получить удалённую версию
    remote = confluence_client.get_page(remote_page_id, expand='version')
    
    # Прочитать локальные метаданные
    local_meta = parse_frontmatter(local_file)
    local_mtime = os.path.getmtime(local_file)
    
    local_changed = local_meta.get('last_sync', 0) < local_mtime
    remote_changed = local_meta.get('confluence_version', 0) < remote['version']['number']
    
    if local_changed and remote_changed:
        return 'CONFLICT'  # Изменения с обеих сторон
    elif local_changed:
        return 'PUSH'      # Локальные изменения → Confluence
    elif remote_changed:
        return 'PULL'      # Confluence → локальный файл
    return 'SYNCED'        # Нет изменений
```

### Конвертация форматов — собственные парсеры

Confluence API **не принимает Markdown** — только Storage Format (XHTML с `<ac:*>` тегами). Готовые библиотеки (`md2cf`, `Turndown`) покрывают базовые случаи, но для полного контроля нужны собственные парсеры.

---

#### Obsidian-плагин: двусторонняя конвертация

**MD → Confluence Storage Format (Push):**

```typescript
// obsidian-confluence-sync/src/converters/md-to-confluence.ts

import { marked } from 'marked';

interface ConfluenceRenderer {
  heading(text: string, level: number): string;
  paragraph(text: string): string;
  list(body: string, ordered: boolean): string;
  listitem(text: string): string;
  code(code: string, language?: string): string;
  codespan(code: string): string;
  blockquote(quote: string): string;
  table(header: string, body: string): string;
  tablerow(content: string): string;
  tablecell(content: string, flags: { header: boolean; align: string | null }): string;
  link(href: string, title: string | null, text: string): string;
  image(href: string, title: string | null, text: string): string;
  strong(text: string): string;
  em(text: string): string;
  del(text: string): string;
  hr(): string;
  checkbox(checked: boolean): string;
}

const confluenceRenderer: ConfluenceRenderer = {
  // Заголовки
  heading(text: string, level: number): string {
    return `<h${level}>${text}</h${level}>\n`;
  },

  // Параграфы
  paragraph(text: string): string {
    // Обработка task items внутри параграфа
    if (text.includes('confluence-task-item')) {
      return text; // Уже обработано в checkbox
    }
    return `<p>${text}</p>\n`;
  },

  // Списки
  list(body: string, ordered: boolean): string {
    // Проверка на task list
    if (body.includes('<ac:task>')) {
      return `<ac:task-list>\n${body}</ac:task-list>\n`;
    }
    const tag = ordered ? 'ol' : 'ul';
    return `<${tag}>\n${body}</${tag}>\n`;
  },

  listitem(text: string): string {
    // Task items обрабатываются отдельно
    if (text.includes('<ac:task>')) {
      return text;
    }
    return `<li>${text.trim()}</li>\n`;
  },

  // Чекбоксы (task lists)
  checkbox(checked: boolean): string {
    const status = checked ? 'complete' : 'incomplete';
    return `<ac:task><ac:task-status>${status}</ac:task-status><ac:task-body>`;
  },

  // Code blocks → Confluence code macro
  code(code: string, language?: string): string {
    const lang = language || 'none';
    const escapedCode = code
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
    
    return `
<ac:structured-macro ac:name="code">
  <ac:parameter ac:name="language">${lang}</ac:parameter>
  <ac:parameter ac:name="theme">Confluence</ac:parameter>
  <ac:plain-text-body><![CDATA[${code}]]></ac:plain-text-body>
</ac:structured-macro>\n`;
  },

  // Inline code
  codespan(code: string): string {
    return `<code>${code}</code>`;
  },

  // Blockquotes → Info panel
  blockquote(quote: string): string {
    // Обработка Obsidian callouts: > [!info], > [!warning], etc.
    const calloutMatch = quote.match(/^\[!(info|warning|note|tip|danger)\]\s*(.*)/i);
    if (calloutMatch) {
      const [, type, content] = calloutMatch;
      const macroName = type.toLowerCase() === 'danger' ? 'warning' : type.toLowerCase();
      return `
<ac:structured-macro ac:name="${macroName}">
  <ac:rich-text-body>${content}</ac:rich-text-body>
</ac:structured-macro>\n`;
    }
    return `<blockquote>${quote}</blockquote>\n`;
  },

  // Таблицы
  table(header: string, body: string): string {
    return `<table class="confluenceTable">\n<thead>\n${header}</thead>\n<tbody>\n${body}</tbody>\n</table>\n`;
  },

  tablerow(content: string): string {
    return `<tr>\n${content}</tr>\n`;
  },

  tablecell(content: string, flags: { header: boolean; align: string | null }): string {
    const tag = flags.header ? 'th' : 'td';
    const className = flags.header ? 'confluenceTh' : 'confluenceTd';
    const style = flags.align ? ` style="text-align: ${flags.align}"` : '';
    return `<${tag} class="${className}"${style}>${content}</${tag}>\n`;
  },

  // Ссылки
  link(href: string, title: string | null, text: string): string {
    // Внутренние ссылки Obsidian [[Page Name]]
    if (href.startsWith('obsidian://')) {
      // Конвертируем в Confluence page link (требует резолвинга page ID)
      return `<ac:link><ri:page ri:content-title="${text}"/></ac:link>`;
    }
    return `<a href="${href}"${title ? ` title="${title}"` : ''}>${text}</a>`;
  },

  // Изображения
  image(href: string, title: string | null, text: string): string {
    // Локальные изображения → attachment reference
    if (!href.startsWith('http')) {
      const filename = href.split('/').pop() || href;
      return `<ac:image ac:alt="${text || ''}"><ri:attachment ri:filename="${filename}"/></ac:image>`;
    }
    // Внешние изображения
    return `<ac:image ac:alt="${text || ''}"><ri:url ri:value="${href}"/></ac:image>`;
  },

  // Форматирование
  strong(text: string): string {
    return `<strong>${text}</strong>`;
  },

  em(text: string): string {
    return `<em>${text}</em>`;
  },

  del(text: string): string {
    return `<span style="text-decoration: line-through;">${text}</span>`;
  },

  hr(): string {
    return '<hr/>\n';
  }
};

// Препроцессор для Obsidian-специфичных элементов
function preprocessObsidianMarkdown(md: string): string {
  let processed = md;

  // Wiki-links: [[Page Name]] или [[Page Name|Display Text]]
  processed = processed.replace(
    /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g,
    (_, page, display) => `[${display || page}](obsidian://${encodeURIComponent(page)})`
  );

  // Obsidian embeds: ![[filename.png]]
  processed = processed.replace(
    /!\[\[([^\]]+)\]\]/g,
    (_, filename) => `![${filename}](${filename})`
  );

  // Task list items: - [ ] или - [x]
  processed = processed.replace(
    /^(\s*)- \[([ xX])\] (.+)$/gm,
    (_, indent, checked, text) => {
      const status = checked.toLowerCase() === 'x' ? 'complete' : 'incomplete';
      return `${indent}<ac:task><ac:task-status>${status}</ac:task-status><ac:task-body>${text}</ac:task-body></ac:task>`;
    }
  );

  return processed;
}

// Главная функция конвертации
export function markdownToConfluence(markdown: string): string {
  const preprocessed = preprocessObsidianMarkdown(markdown);
  
  marked.use({ renderer: confluenceRenderer as any });
  
  return marked.parse(preprocessed) as string;
}
```

**Confluence Storage Format → MD (Pull):**

```typescript
// obsidian-confluence-sync/src/converters/confluence-to-md.ts

import { JSDOM } from 'jsdom';

interface ConversionContext {
  attachments: Map<string, string>; // filename → local path
  pageLinks: Map<string, string>;   // page title → obsidian link
}

export function confluenceToMarkdown(
  storageFormat: string, 
  context: ConversionContext = { attachments: new Map(), pageLinks: new Map() }
): string {
  const dom = new JSDOM(`<body>${storageFormat}</body>`);
  const doc = dom.window.document;
  
  return processNode(doc.body, context).trim();
}

function processNode(node: Node, ctx: ConversionContext): string {
  if (node.nodeType === 3) { // Text node
    return node.textContent || '';
  }
  
  if (node.nodeType !== 1) return '';
  
  const el = node as Element;
  const tag = el.tagName.toLowerCase();
  const children = () => Array.from(el.childNodes).map(n => processNode(n, ctx)).join('');

  // Заголовки
  if (/^h[1-6]$/.test(tag)) {
    const level = parseInt(tag[1]);
    return `${'#'.repeat(level)} ${children()}\n\n`;
  }

  // Параграфы
  if (tag === 'p') {
    const content = children().trim();
    return content ? `${content}\n\n` : '';
  }

  // Списки
  if (tag === 'ul') {
    return Array.from(el.children)
      .map(li => `- ${processNode(li, ctx).trim()}`)
      .join('\n') + '\n\n';
  }
  
  if (tag === 'ol') {
    return Array.from(el.children)
      .map((li, i) => `${i + 1}. ${processNode(li, ctx).trim()}`)
      .join('\n') + '\n\n';
  }
  
  if (tag === 'li') {
    return children();
  }

  // Таблицы
  if (tag === 'table') {
    return processTable(el, ctx);
  }

  // Форматирование
  if (tag === 'strong' || tag === 'b') return `**${children()}**`;
  if (tag === 'em' || tag === 'i') return `*${children()}*`;
  if (tag === 'code') return `\`${children()}\``;
  if (tag === 'a') {
    const href = el.getAttribute('href') || '';
    return `[${children()}](${href})`;
  }

  // Confluence-специфичные элементы
  if (tag === 'ac:structured-macro') {
    return processConfluenceMacro(el, ctx);
  }
  
  if (tag === 'ac:task-list') {
    return processTaskList(el, ctx);
  }
  
  if (tag === 'ac:task') {
    return processTask(el, ctx);
  }
  
  if (tag === 'ac:link') {
    return processConfluenceLink(el, ctx);
  }
  
  if (tag === 'ac:image') {
    return processConfluenceImage(el, ctx);
  }

  // Blockquote
  if (tag === 'blockquote') {
    return children().split('\n').map(line => `> ${line}`).join('\n') + '\n\n';
  }

  // HR
  if (tag === 'hr') return '---\n\n';

  // Default: process children
  return children();
}

function processConfluenceMacro(el: Element, ctx: ConversionContext): string {
  const macroName = el.getAttribute('ac:name');
  
  switch (macroName) {
    case 'code': {
      const lang = el.querySelector('ac:parameter[ac:name="language"]')?.textContent || '';
      const code = el.querySelector('ac:plain-text-body')?.textContent || '';
      return `\`\`\`${lang}\n${code}\n\`\`\`\n\n`;
    }
    
    case 'info':
    case 'note':
    case 'tip':
    case 'warning': {
      const body = el.querySelector('ac:rich-text-body');
      const content = body ? processNode(body, ctx).trim() : '';
      // Obsidian callout format
      return `> [!${macroName}]\n> ${content.split('\n').join('\n> ')}\n\n`;
    }
    
    case 'expand': {
      const title = el.querySelector('ac:parameter[ac:name="title"]')?.textContent || 'Details';
      const body = el.querySelector('ac:rich-text-body');
      const content = body ? processNode(body, ctx).trim() : '';
      // Нет прямого аналога в MD, используем детали
      return `<details>\n<summary>${title}</summary>\n\n${content}\n</details>\n\n`;
    }
    
    case 'toc': {
      // Table of contents — нет аналога, пропускаем или добавляем комментарий
      return `<!-- Table of Contents -->\n\n`;
    }
    
    default:
      // Неизвестный макрос — извлекаем текст
      const body = el.querySelector('ac:rich-text-body, ac:plain-text-body');
      return body ? processNode(body, ctx) : '';
  }
}

function processTaskList(el: Element, ctx: ConversionContext): string {
  const tasks = Array.from(el.querySelectorAll('ac:task'));
  return tasks.map(task => processTask(task as Element, ctx)).join('\n') + '\n\n';
}

function processTask(el: Element, ctx: ConversionContext): string {
  const status = el.querySelector('ac:task-status')?.textContent || 'incomplete';
  const body = el.querySelector('ac:task-body');
  const content = body ? processNode(body, ctx).trim() : '';
  const checkbox = status === 'complete' ? '[x]' : '[ ]';
  return `- ${checkbox} ${content}`;
}

function processConfluenceLink(el: Element, ctx: ConversionContext): string {
  const pageRef = el.querySelector('ri:page');
  if (pageRef) {
    const pageTitle = pageRef.getAttribute('ri:content-title') || '';
    // Obsidian wiki-link
    return `[[${pageTitle}]]`;
  }
  
  const attachmentRef = el.querySelector('ri:attachment');
  if (attachmentRef) {
    const filename = attachmentRef.getAttribute('ri:filename') || '';
    const linkBody = el.querySelector('ac:plain-text-link-body')?.textContent || filename;
    return `[${linkBody}](${filename})`;
  }
  
  return '';
}

function processConfluenceImage(el: Element, ctx: ConversionContext): string {
  const alt = el.getAttribute('ac:alt') || '';
  
  const attachmentRef = el.querySelector('ri:attachment');
  if (attachmentRef) {
    const filename = attachmentRef.getAttribute('ri:filename') || '';
    // Obsidian embed
    return `![[${filename}]]`;
  }
  
  const urlRef = el.querySelector('ri:url');
  if (urlRef) {
    const url = urlRef.getAttribute('ri:value') || '';
    return `![${alt}](${url})`;
  }
  
  return '';
}

function processTable(el: Element, ctx: ConversionContext): string {
  const rows = Array.from(el.querySelectorAll('tr'));
  if (rows.length === 0) return '';
  
  const result: string[] = [];
  
  rows.forEach((row, rowIndex) => {
    const cells = Array.from(row.querySelectorAll('th, td'));
    const cellContents = cells.map(cell => processNode(cell, ctx).trim().replace(/\|/g, '\\|'));
    result.push(`| ${cellContents.join(' | ')} |`);
    
    // Separator после header row
    if (rowIndex === 0) {
      result.push(`| ${cells.map(() => '---').join(' | ')} |`);
    }
  });
  
  return result.join('\n') + '\n\n';
}
```

**Утилиты для frontmatter и метаданных:**

```typescript
// obsidian-confluence-sync/src/utils/frontmatter.ts

import * as yaml from 'yaml';

export interface SyncMetadata {
  'confluence-id'?: string;
  'confluence-version'?: number;
  'confluence-space'?: string;
  'confluence-parent-id'?: string;
  'last-sync'?: string;
}

export function parseFrontmatter(content: string): { metadata: SyncMetadata; body: string } {
  const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  
  if (!match) {
    return { metadata: {}, body: content };
  }
  
  try {
    const metadata = yaml.parse(match[1]) as SyncMetadata;
    return { metadata, body: match[2] };
  } catch {
    return { metadata: {}, body: content };
  }
}

export function serializeFrontmatter(metadata: SyncMetadata, body: string): string {
  const yamlContent = yaml.stringify(metadata).trim();
  return `---\n${yamlContent}\n---\n${body}`;
}

export function updateSyncMetadata(
  content: string, 
  updates: Partial<SyncMetadata>
): string {
  const { metadata, body } = parseFrontmatter(content);
  const updated = { ...metadata, ...updates, 'last-sync': new Date().toISOString() };
  return serializeFrontmatter(updated, body);
}
```

---

#### Vanta Speech: односторонняя конвертация (App → Confluence)

Для Vanta Speech структура саммари фиксированная — проще генерировать Storage Format напрямую без промежуточного Markdown.

```python
# vanta_speech/confluence/meeting_formatter.py

from dataclasses import dataclass
from typing import List, Optional
from datetime import datetime
import html

@dataclass
class ActionItem:
    task: str
    owner: str
    due_date: Optional[str] = None
    completed: bool = False

@dataclass
class MeetingSummary:
    title: str
    date: datetime
    duration_minutes: int
    attendees: List[str]
    summary: str           # Краткое резюме от LLM
    key_points: List[str]  # Основные тезисы
    decisions: List[str]   # Принятые решения
    action_items: List[ActionItem]
    transcript_excerpt: Optional[str] = None  # Опционально: фрагмент транскрипта
    recording_url: Optional[str] = None

class MeetingToConfluenceFormatter:
    """Форматтер meeting summary в Confluence Storage Format"""
    
    def format(self, meeting: MeetingSummary) -> str:
        """Генерация полной страницы в Storage Format"""
        
        sections = [
            self._format_header(meeting),
            self._format_metadata_panel(meeting),
            self._format_summary(meeting),
            self._format_key_points(meeting),
            self._format_decisions(meeting),
            self._format_action_items(meeting),
        ]
        
        if meeting.transcript_excerpt:
            sections.append(self._format_transcript(meeting))
        
        return '\n'.join(sections)
    
    def _escape(self, text: str) -> str:
        """Экранирование HTML-спецсимволов"""
        return html.escape(text)
    
    def _format_header(self, meeting: MeetingSummary) -> str:
        """Заголовок страницы"""
        date_str = meeting.date.strftime('%d.%m.%Y')
        return f'<h1>📋 {self._escape(meeting.title)}</h1>'
    
    def _format_metadata_panel(self, meeting: MeetingSummary) -> str:
        """Панель с метаданными встречи"""
        
        date_str = meeting.date.strftime('%d %B %Y, %H:%M')
        duration = f'{meeting.duration_minutes} мин'
        attendees = ', '.join(self._escape(a) for a in meeting.attendees)
        
        recording_link = ''
        if meeting.recording_url:
            recording_link = f'''
            <tr>
                <th>Запись</th>
                <td><a href="{self._escape(meeting.recording_url)}">🎙️ Открыть запись</a></td>
            </tr>'''
        
        return f'''
<ac:structured-macro ac:name="panel">
  <ac:parameter ac:name="title">Информация о встрече</ac:parameter>
  <ac:rich-text-body>
    <table class="confluenceTable">
      <tr><th style="width:120px">Дата</th><td>{date_str}</td></tr>
      <tr><th>Длительность</th><td>{duration}</td></tr>
      <tr><th>Участники</th><td>{attendees}</td></tr>
      {recording_link}
    </table>
  </ac:rich-text-body>
</ac:structured-macro>
'''
    
    def _format_summary(self, meeting: MeetingSummary) -> str:
        """Блок с кратким резюме"""
        
        return f'''
<h2>📝 Резюме</h2>
<ac:structured-macro ac:name="info">
  <ac:rich-text-body>
    <p>{self._escape(meeting.summary)}</p>
  </ac:rich-text-body>
</ac:structured-macro>
'''
    
    def _format_key_points(self, meeting: MeetingSummary) -> str:
        """Ключевые тезисы"""
        
        if not meeting.key_points:
            return ''
        
        items = '\n'.join(f'<li>{self._escape(point)}</li>' for point in meeting.key_points)
        
        return f'''
<h2>💡 Ключевые тезисы</h2>
<ul>
{items}
</ul>
'''
    
    def _format_decisions(self, meeting: MeetingSummary) -> str:
        """Принятые решения"""
        
        if not meeting.decisions:
            return ''
        
        items = '\n'.join(f'<li>{self._escape(decision)}</li>' for decision in meeting.decisions)
        
        return f'''
<h2>✅ Принятые решения</h2>
<ac:structured-macro ac:name="tip">
  <ac:rich-text-body>
    <ul>
    {items}
    </ul>
  </ac:rich-text-body>
</ac:structured-macro>
'''
    
    def _format_action_items(self, meeting: MeetingSummary) -> str:
        """Action items как Confluence tasks"""
        
        if not meeting.action_items:
            return ''
        
        tasks = []
        for item in meeting.action_items:
            status = 'complete' if item.completed else 'incomplete'
            due = f' (до {item.due_date})' if item.due_date else ''
            task_text = f'{self._escape(item.task)}{due} — <strong>{self._escape(item.owner)}</strong>'
            
            tasks.append(f'''
<ac:task>
  <ac:task-status>{status}</ac:task-status>
  <ac:task-body>{task_text}</ac:task-body>
</ac:task>''')
        
        return f'''
<h2>📌 Action Items</h2>
<ac:task-list>
{''.join(tasks)}
</ac:task-list>
'''
    
    def _format_transcript(self, meeting: MeetingSummary) -> str:
        """Фрагмент транскрипта в сворачиваемом блоке"""
        
        return f'''
<h2>🎤 Фрагмент транскрипта</h2>
<ac:structured-macro ac:name="expand">
  <ac:parameter ac:name="title">Показать транскрипт</ac:parameter>
  <ac:rich-text-body>
    <ac:structured-macro ac:name="code">
      <ac:parameter ac:name="language">none</ac:parameter>
      <ac:plain-text-body><![CDATA[{meeting.transcript_excerpt}]]></ac:plain-text-body>
    </ac:structured-macro>
  </ac:rich-text-body>
</ac:structured-macro>
'''


# ═══════════════════════════════════════════════════════════════════
# Интеграция с Confluence Client
# ═══════════════════════════════════════════════════════════════════

class VantaSpeechConfluencePublisher:
    """Публикатор meeting summaries в Confluence"""
    
    def __init__(self, confluence_client, default_space: str, parent_page_id: str):
        self.client = confluence_client
        self.default_space = default_space
        self.parent_page_id = parent_page_id
        self.formatter = MeetingToConfluenceFormatter()
    
    def publish_meeting(
        self, 
        meeting: MeetingSummary,
        space_key: Optional[str] = None,
        parent_id: Optional[str] = None,
        attachments: Optional[List[str]] = None  # Пути к файлам
    ) -> dict:
        """
        Опубликовать meeting summary в Confluence
        
        Returns:
            dict с id, title, url созданной страницы
        """
        
        space = space_key or self.default_space
        parent = parent_id or self.parent_page_id
        
        # Форматирование контента
        content = self.formatter.format(meeting)
        
        # Генерация title с датой для уникальности
        date_str = meeting.date.strftime('%Y-%m-%d %H:%M')
        title = f"{meeting.title} — {date_str}"
        
        # Создание страницы
        page = self.client.create_page(
            space_key=space,
            title=title,
            content=content,
            parent_id=parent
        )
        
        # Загрузка вложений (аудио, изображения и т.д.)
        if attachments:
            for file_path in attachments:
                self.client.upload_attachment(page['id'], file_path)
        
        return {
            'id': page['id'],
            'title': page['title'],
            'url': page['_links']['webui']
        }
    
    def update_meeting(self, page_id: str, meeting: MeetingSummary) -> dict:
        """Обновить существующую страницу meeting summary"""
        
        content = self.formatter.format(meeting)
        date_str = meeting.date.strftime('%Y-%m-%d %H:%M')
        title = f"{meeting.title} — {date_str}"
        
        return self.client.update_page(page_id, title, content)


# ═══════════════════════════════════════════════════════════════════
# Пример использования
# ═══════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    from confluence_client import ConfluenceClient
    
    # Инициализация (AD-креды как в основной системе)
    client = ConfluenceClient(
        base_url="http://confluence.company.local:8080/confluence",
        username="ad_username",  # AD credentials
        password="ad_password"
    )
    
    publisher = VantaSpeechConfluencePublisher(
        confluence_client=client,
        default_space="MEETINGS",
        parent_page_id="123456"  # Родительская страница для всех саммари
    )
    
    # Данные от LLM-саммаризатора
    meeting = MeetingSummary(
        title="Weekly Team Sync",
        date=datetime(2026, 1, 19, 10, 0),
        duration_minutes=45,
        attendees=["Тимофей", "Иван", "Мария"],
        summary="Обсудили прогресс по Vanta Speech, запланировали релиз на конец месяца.",
        key_points=[
            "iOS-версия готова к бета-тестированию",
            "Нужна интеграция с Confluence для автопубликации",
            "Android-версия отложена до Q2"
        ],
        decisions=[
            "Запускаем бету для внутренних пользователей с 25 января",
            "Приоритет — стабильность над новыми фичами"
        ],
        action_items=[
            ActionItem(task="Настроить CI/CD для TestFlight", owner="Тимофей", due_date="22.01"),
            ActionItem(task="Подготовить документацию API", owner="Иван", due_date="24.01"),
            ActionItem(task="Собрать фидбек от первых тестеров", owner="Мария", due_date="31.01")
        ],
        recording_url="https://storage.company.local/recordings/2026-01-19-sync.m4a"
    )
    
    # Публикация
    result = publisher.publish_meeting(meeting)
    print(f"✅ Опубликовано: {result['url']}")
```

**Структура саммари на выходе:**

```
┌────────────────────────────────────────────┐
│ 📋 Weekly Team Sync                         │
├────────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐    │
│ │ Информация о встрече                │    │
│ │ Дата: 19 января 2026, 10:00         │    │
│ │ Длительность: 45 мин                │    │
│ │ Участники: Тимофей, Иван, Мария     │    │
│ │ Запись: 🎙️ Открыть запись           │    │
│ └─────────────────────────────────────┘    │
│                                            │
│ 📝 Резюме                                  │
│ ┌─────────────────────────────────────┐    │
│ │ ℹ️ Обсудили прогресс по Vanta...    │    │
│ └─────────────────────────────────────┘    │
│                                            │
│ 💡 Ключевые тезисы                         │
│ • iOS-версия готова к бета-тестированию   │
│ • Нужна интеграция с Confluence           │
│ • Android-версия отложена до Q2           │
│                                            │
│ ✅ Принятые решения                        │
│ ┌─────────────────────────────────────┐    │
│ │ 💡 • Запускаем бету с 25 января     │    │
│ │    • Приоритет — стабильность       │    │
│ └─────────────────────────────────────┘    │
│                                            │
│ 📌 Action Items                            │
│ ☐ Настроить CI/CD (до 22.01) — Тимофей   │
│ ☐ Подготовить документацию — Иван        │
│ ☐ Собрать фидбек — Мария                 │
│                                            │
│ 🎤 Фрагмент транскрипта              [▶]  │
└────────────────────────────────────────────┘
```

### Mapping папок Obsidian → иерархия Confluence

```python
async def sync_folder_to_confluence(folder_path, space_key, parent_id=None):
    """Рекурсивная синхронизация папки в иерархию страниц"""
    
    for item in os.listdir(folder_path):
        full_path = os.path.join(folder_path, item)
        
        if os.path.isdir(full_path):
            # Папка → страница-контейнер
            container_page = create_or_update_page(
                space_key, 
                title=item, 
                content="<p>Index page</p>",
                parent_id=parent_id
            )
            # Рекурсия для содержимого
            await sync_folder_to_confluence(full_path, space_key, container_page['id'])
            
        elif item.endswith('.md'):
            # Markdown-файл → дочерняя страница
            content = read_and_convert(full_path)
            create_or_update_page(
                space_key,
                title=item.replace('.md', ''),
                content=content,
                parent_id=parent_id
            )
```

---

## Часть 3: версионирование и разрешение конфликтов

### Как работает версионирование в Confluence

Каждое сохранение создаёт новую версию с инкрементным номером. При обновлении через API **обязательно указывать** `version.number = текущая + 1`.

```json
{
  "version": {
    "number": 5,
    "by": {"username": "admin", "displayName": "Administrator"},
    "when": "2026-01-19T10:30:00.000Z",
    "message": "Updated via API",
    "minorEdit": false
  }
}
```

### Получение истории версий

```bash
# Текущая версия с метаданными
GET /rest/api/content/{id}?expand=version,history

# Все версии (experimental endpoint)
GET /rest/experimental/content/{id}/version

# Конкретная историческая версия
GET /rest/api/content/{id}?status=historical&version=3&expand=body.storage
```

### Обновление с правильным номером версии

```python
def update_page(self, page_id, title, content):
    """Обновить страницу с корректной обработкой версии"""
    
    # 1. Получить текущую версию
    current = self._request('GET', f'content/{page_id}', params={'expand': 'version'})
    current_version = current['version']['number']
    
    # 2. Подготовить данные с инкрементом версии
    update_data = {
        "id": page_id,
        "type": "page",
        "title": title,
        "body": {
            "storage": {"value": content, "representation": "storage"}
        },
        "version": {
            "number": current_version + 1,  # Обязательно +1
            "message": "Updated via sync"
        }
    }
    
    # 3. Выполнить обновление
    return self._request('PUT', f'content/{page_id}', json=update_data)
```

### Обработка HTTP 409 Conflict

При одновременном редактировании Confluence возвращает **409 Conflict**:

```json
{
  "statusCode": 409,
  "message": "Version must be incremented on update. Current version is: 15",
  "reason": "Conflict"
}
```

### Стратегии разрешения конфликтов

**1. Last-Write-Wins (автоматический retry):**

```python
def update_with_retry(self, page_id, content, max_retries=3):
    """Retry при конфликте с получением свежей версии"""
    
    for attempt in range(max_retries):
        try:
            return self.update_page(page_id, content)
        except requests.HTTPError as e:
            if e.response.status_code == 409:
                print(f"Конфликт версий, попытка {attempt + 1}...")
                continue
            raise
    
    raise Exception("Превышено количество попыток из-за конфликтов")
```

**2. Merge с маркерами конфликта:**

```python
def merge_with_conflict_markers(remote_content, local_content):
    """Создать страницу с маркерами конфликта для ручного разрешения"""
    
    return f'''
    <ac:structured-macro ac:name="warning">
      <ac:rich-text-body><p>⚠️ Обнаружен конфликт — требуется ручное разрешение</p></ac:rich-text-body>
    </ac:structured-macro>
    
    <h2>Версия из Confluence:</h2>
    {remote_content}
    
    <h2>Локальная версия:</h2>
    {local_content}
    '''
```

**3. Уведомление пользователя:**
- При 409 сохранить локальные изменения в `.conflict` файл
- Показать уведомление в UI Obsidian-плагина
- Предложить выбор: перезаписать, объединить или отменить

### Откат к предыдущей версии

В Confluence Server/DC нет прямого API для revert — нужно вручную скопировать контент:

```python
def revert_to_version(self, page_id, target_version):
    """Откатить страницу к указанной версии"""
    
    # Получить историческую версию
    historical = self._request('GET', f'content/{page_id}',
        params={'status': 'historical', 'version': target_version, 'expand': 'body.storage'})
    
    # Создать новую версию с этим контентом
    return self.update_page(
        page_id,
        historical['title'],
        historical['body']['storage']['value']
    )
```

---

## Часть 4: иерархия Confluence и навигация по структуре

### Структура данных Confluence

```
Space (TST)
├── Homepage (корневая страница)
│   ├── Child Page 1
│   │   ├── Grandchild 1.1
│   │   └── Grandchild 1.2
│   └── Child Page 2
└── Another Root Page
```

### Навигация по дереву страниц

**Дочерние страницы:**
```bash
GET /rest/api/content/{pageId}/child/page?limit=50
```

**Все вложенные страницы (descendants):**
```bash
GET /rest/api/content/{pageId}/descendant/page
```

**Родительские страницы (ancestors):**
```bash
GET /rest/api/content/{pageId}?expand=ancestors
```

### Поиск страниц через CQL

Confluence Query Language (CQL) — мощный инструмент для поиска:

```bash
# По названию (точное)
GET /rest/api/content/search?cql=title='Meeting Notes'

# По названию (частичное)
GET /rest/api/content/search?cql=title~'meeting'

# В конкретном пространстве
GET /rest/api/content/search?cql=space=TEAM AND type=page

# По метке
GET /rest/api/content/search?cql=label=documentation

# Потомки страницы
GET /rest/api/content/search?cql=ancestor=123456

# Полнотекстовый поиск
GET /rest/api/content/search?cql=text~'confluence api'

# По дате изменения
GET /rest/api/content/search?cql=lastmodified>=2026-01-01 AND space=PROJ
```

### Работа с метаданными

**Labels (метки):**
```python
# Добавить метку
client._request('POST', f'content/{page_id}/label',
    json=[{"prefix": "global", "name": "meeting-notes"}])

# Получить метки
labels = client._request('GET', f'content/{page_id}/label')

# Удалить метку
client._request('DELETE', f'content/{page_id}/label/meeting-notes')
```

**Content Properties (кастомные метаданные):**
```python
# Установить property
client._request('POST', f'content/{page_id}/property',
    json={
        "key": "sync-metadata",
        "value": {
            "obsidian_path": "/folder/note.md",
            "last_sync": "2026-01-19T10:30:00Z",
            "sync_version": 1
        }
    })

# Получить property
prop = client._request('GET', f'content/{page_id}/property/sync-metadata')
```

### Пагинация больших результатов

```python
def get_all_pages_in_space(self, space_key):
    """Итеративная загрузка всех страниц с пагинацией"""
    
    all_pages = []
    start = 0
    limit = 100
    
    while True:
        result = self._request('GET', f'space/{space_key}/content/page',
            params={'start': start, 'limit': limit, 'expand': 'version,ancestors'})
        
        all_pages.extend(result.get('results', []))
        
        # Проверяем наличие следующей страницы
        if '_links' not in result or 'next' not in result['_links']:
            break
        
        start += limit
    
    return all_pages
```

**Ограничения пагинации:**
- Максимум **500 результатов** за запрос (настраивается на сервере)
- CQL-поиск с `expand=body.export_view`: максимум **25 результатов**
- Для больших объёмов используйте **Scan API** (Confluence 7.18+): `GET /rest/api/content/scan`

---

## Полный Python-клиент для обеих интеграций

```python
"""
ConfluenceClient — универсальный клиент для Vanta Speech и Obsidian Sync
Confluence Server/Data Center 8.5.6
"""

import requests
from requests.auth import HTTPBasicAuth
import json
import os
import re
from datetime import datetime

class ConfluenceClient:
    def __init__(self, base_url, username, password):
        self.base_url = base_url.rstrip('/')
        self.auth = HTTPBasicAuth(username, password)
        self.headers = {"Content-Type": "application/json", "Accept": "application/json"}
    
    def _request(self, method, endpoint, **kwargs):
        url = f"{self.base_url}/rest/api/{endpoint}"
        response = requests.request(method, url, auth=self.auth, 
                                   headers=self.headers, **kwargs)
        if response.status_code == 409:
            raise ConflictError(response.json().get('message', 'Version conflict'))
        response.raise_for_status()
        return response.json() if response.content else None

    # ═══════════════════════════════════════════════════════════════
    # ЧАСТЬ 1: Vanta Speech — создание страниц
    # ═══════════════════════════════════════════════════════════════
    
    def create_meeting_page(self, space_key, title, date, attendees, 
                           notes, action_items, parent_id=None):
        """Создать страницу с саммари встречи"""
        
        content = self._format_meeting_summary(title, date, attendees, notes, action_items)
        return self.create_page(space_key, title, content, parent_id)
    
    def create_page(self, space_key, title, content, parent_id=None):
        """Создать страницу в Confluence"""
        
        data = {
            "type": "page",
            "title": title,
            "space": {"key": space_key},
            "body": {"storage": {"value": content, "representation": "storage"}}
        }
        if parent_id:
            data["ancestors"] = [{"id": str(parent_id)}]
        
        return self._request('POST', 'content', json=data)
    
    def upload_attachment(self, page_id, file_path, comment=""):
        """Загрузить вложение к странице"""
        
        url = f"{self.base_url}/rest/api/content/{page_id}/child/attachment"
        headers = {"X-Atlassian-Token": "no-check"}
        
        with open(file_path, 'rb') as f:
            files = {'file': (os.path.basename(file_path), f)}
            response = requests.post(url, auth=self.auth, headers=headers,
                                    files=files, data={'comment': comment})
        response.raise_for_status()
        return response.json()

    # ═══════════════════════════════════════════════════════════════
    # ЧАСТЬ 2: Obsidian Sync — CRUD операции
    # ═══════════════════════════════════════════════════════════════
    
    def get_page(self, page_id, expand='body.storage,version,ancestors'):
        """Получить страницу по ID"""
        return self._request('GET', f'content/{page_id}', params={'expand': expand})
    
    def update_page(self, page_id, title, content, message="Updated via sync"):
        """Обновить страницу с автоматическим инкрементом версии"""
        
        current = self.get_page(page_id, expand='version')
        
        data = {
            "id": str(page_id),
            "type": "page",
            "title": title,
            "body": {"storage": {"value": content, "representation": "storage"}},
            "version": {"number": current['version']['number'] + 1, "message": message}
        }
        return self._request('PUT', f'content/{page_id}', json=data)
    
    def delete_page(self, page_id):
        """Удалить страницу"""
        return self._request('DELETE', f'content/{page_id}')
    
    def update_with_retry(self, page_id, title, content, max_retries=3):
        """Обновить с retry при конфликте версий"""
        
        for attempt in range(max_retries):
            try:
                return self.update_page(page_id, title, content)
            except ConflictError:
                if attempt == max_retries - 1:
                    raise
                continue

    # ═══════════════════════════════════════════════════════════════
    # ЧАСТЬ 3: Версионирование
    # ═══════════════════════════════════════════════════════════════
    
    def get_version_history(self, page_id):
        """Получить историю версий (experimental API)"""
        url = f"{self.base_url}/rest/experimental/content/{page_id}/version"
        response = requests.get(url, auth=self.auth)
        return response.json() if response.ok else None
    
    def get_historical_version(self, page_id, version_number):
        """Получить конкретную версию страницы"""
        return self._request('GET', f'content/{page_id}',
            params={'status': 'historical', 'version': version_number, 
                   'expand': 'body.storage'})
    
    def revert_to_version(self, page_id, version_number):
        """Откатить к указанной версии"""
        historical = self.get_historical_version(page_id, version_number)
        return self.update_page(page_id, historical['title'], 
                               historical['body']['storage']['value'])

    # ═══════════════════════════════════════════════════════════════
    # ЧАСТЬ 4: Навигация по иерархии
    # ═══════════════════════════════════════════════════════════════
    
    def get_spaces(self, limit=100):
        """Получить список пространств"""
        return self._request('GET', 'space', params={'limit': limit, 'expand': 'description'})
    
    def get_children(self, page_id, limit=100):
        """Получить дочерние страницы"""
        return self._request('GET', f'content/{page_id}/child/page', params={'limit': limit})
    
    def get_descendants(self, page_id, limit=200):
        """Получить все вложенные страницы"""
        return self._request('GET', f'content/{page_id}/descendant/page', params={'limit': limit})
    
    def search_cql(self, cql, limit=25, expand=None):
        """Поиск через CQL"""
        params = {'cql': cql, 'limit': limit}
        if expand:
            params['expand'] = expand
        return self._request('GET', 'content/search', params=params)
    
    def find_page_by_title(self, space_key, title):
        """Найти страницу по названию"""
        results = self.search_cql(f'space={space_key} AND title="{title}"')
        return results['results'][0] if results['results'] else None

    # ═══════════════════════════════════════════════════════════════
    # Вспомогательные методы
    # ═══════════════════════════════════════════════════════════════
    
    def _format_meeting_summary(self, title, date, attendees, notes, action_items):
        attendees_html = ''.join([f'<li>{a}</li>' for a in attendees])
        tasks_html = ''.join([
            f'<ac:task><ac:task-status>incomplete</ac:task-status>'
            f'<ac:task-body>{item["task"]} — {item["owner"]}</ac:task-body></ac:task>'
            for item in action_items
        ])
        
        return f'''
        <h1>{title}</h1>
        <p><strong>Дата:</strong> {date}</p>
        <h2>Участники</h2><ul>{attendees_html}</ul>
        <h2>Заметки</h2><p>{notes}</p>
        <h2>Action Items</h2><ac:task-list>{tasks_html}</ac:task-list>
        '''

class ConflictError(Exception):
    """Исключение для HTTP 409 Conflict"""
    pass


# ═══════════════════════════════════════════════════════════════════
# Примеры использования
# ═══════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    client = ConfluenceClient(
        "http://confluence.company.local:8080/confluence",
        "ad_username",
        "ad_password"
    )
    
    # Vanta Speech: создание meeting summary
    page = client.create_meeting_page(
        space_key="TEAM",
        title="Weekly Sync - 2026-01-19",
        date="19 января 2026",
        attendees=["Иван Петров", "Мария Сидорова"],
        notes="Обсудили прогресс по проекту...",
        action_items=[
            {"task": "Подготовить отчёт", "owner": "Иван"},
            {"task": "Обновить документацию", "owner": "Мария"}
        ],
        parent_id="123456"
    )
    print(f"Создана страница: {page['_links']['webui']}")
    
    # Obsidian Sync: обновление с обработкой конфликта
    try:
        client.update_with_retry(page['id'], "Updated Title", "<p>New content</p>")
    except ConflictError:
        print("Не удалось разрешить конфликт после 3 попыток")
```

---

## Ключевые ограничения и рекомендации

**Rate limits**: Confluence Server/DC не имеет жёстких rate limits, но рекомендуется **не более 100 запросов/минуту** для стабильности.

**Пагинация**: максимум **500 результатов** за запрос; для CQL с body expansion — **25 результатов**.

**Формат контента**: API работает **только** с Confluence Storage Format (XHTML). Markdown требует конвертации на клиенте.

**Версионирование**: при любом PUT-запросе **обязательно** указывать `version.number = current + 1`.

**Вложения**: заголовок `X-Atlassian-Token: no-check` **обязателен** для предотвращения XSRF.

**Официальная документация**: developer.atlassian.com/server/confluence/confluence-server-rest-api/