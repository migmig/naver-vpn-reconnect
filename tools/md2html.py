#!/usr/bin/env python3
"""tools/md2html.py — 의존성 없는 최소 Markdown→HTML 변환기 ('make doc').

pandoc / python-markdown 이 없을 때 README.md 를 보기 좋은 단일 HTML 로 만든다.
지원: 헤딩, ``` 코드펜스, - / 1. 목록, 표(|), **굵게**, `코드`, [링크](url), 인용(>), 수평선.
"""
import html
import re
import sys

CSS = """
:root{color-scheme:light dark}
body{max-width:860px;margin:40px auto;padding:0 20px;
 font:16px/1.7 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Apple SD Gothic Neo",sans-serif;
 color:#24292f;background:#fff}
@media(prefers-color-scheme:dark){body{color:#c9d1d9;background:#0d1117}
 code,pre{background:#161b22 !important}a{color:#58a6ff}th{background:#161b22}}
h1,h2,h3{font-weight:700;line-height:1.25;margin:1.4em 0 .6em;border-bottom:1px solid #d8dee4;padding-bottom:.3em}
h1{font-size:2em}h2{font-size:1.5em}h3{font-size:1.2em;border-bottom:none}
code{background:#f3f4f6;padding:.15em .4em;border-radius:6px;font:14px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace}
pre{background:#f6f8fa;padding:14px 16px;border-radius:8px;overflow:auto}
pre code{background:none;padding:0}
table{border-collapse:collapse;margin:1em 0;width:100%}
th,td{border:1px solid #d0d7de;padding:6px 12px;text-align:left}
th{background:#f6f8fa}
blockquote{margin:1em 0;padding:.4em 1em;border-left:4px solid #d0d7de;color:#57606a}
hr{border:none;border-top:1px solid #d0d7de;margin:2em 0}
a{color:#0969da;text-decoration:none}a:hover{text-decoration:underline}
"""

def inline(t):
    t = html.escape(t)
    t = re.sub(r'`([^`]+)`', r'<code>\1</code>', t)
    t = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', t)
    t = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', t)
    return t

def convert(md):
    out, i, lines = [], 0, md.split('\n')
    while i < len(lines):
        line = lines[i]
        if line.startswith('```'):
            i += 1; buf = []
            while i < len(lines) and not lines[i].startswith('```'):
                buf.append(html.escape(lines[i])); i += 1
            i += 1
            out.append('<pre><code>' + '\n'.join(buf) + '</code></pre>')
            continue
        m = re.match(r'(#{1,6})\s+(.*)', line)
        if m:
            n = len(m.group(1)); out.append(f'<h{n}>{inline(m.group(2))}</h{n}>'); i += 1; continue
        if re.match(r'\s*([-*_])\s*\1\s*\1[\s\1]*$', line):
            out.append('<hr>'); i += 1; continue
        if line.startswith('>'):
            buf = []
            while i < len(lines) and lines[i].startswith('>'):
                buf.append(inline(lines[i][1:].strip())); i += 1
            out.append('<blockquote>' + '<br>'.join(buf) + '</blockquote>'); continue
        if '|' in line and i + 1 < len(lines) and re.match(r'^\s*\|?[\s:|-]+\|?\s*$', lines[i+1]):
            def cells(r): return [c.strip() for c in r.strip().strip('|').split('|')]
            head = cells(line); i += 2; rows = []
            while i < len(lines) and '|' in lines[i]:
                rows.append(cells(lines[i])); i += 1
            t = ['<table><thead><tr>'] + [f'<th>{inline(c)}</th>' for c in head] + ['</tr></thead><tbody>']
            for r in rows:
                t.append('<tr>' + ''.join(f'<td>{inline(c)}</td>' for c in r) + '</tr>')
            t.append('</tbody></table>'); out.append(''.join(t)); continue
        m = re.match(r'\s*(?:[-*]|\d+\.)\s+', line)
        if m:
            ordered = bool(re.match(r'\s*\d+\.', line)); tag = 'ol' if ordered else 'ul'
            buf = []
            while i < len(lines) and re.match(r'\s*(?:[-*]|\d+\.)\s+', lines[i]):
                buf.append('<li>' + inline(re.sub(r'\s*(?:[-*]|\d+\.)\s+', '', lines[i], count=1)) + '</li>')
                i += 1
            out.append(f'<{tag}>' + ''.join(buf) + f'</{tag}>'); continue
        if line.strip() == '':
            i += 1; continue
        buf = []
        while i < len(lines) and lines[i].strip() != '' and not lines[i].startswith(('#', '```', '>')) \
              and not re.match(r'\s*(?:[-*]|\d+\.)\s+', lines[i]):
            buf.append(inline(lines[i])); i += 1
        out.append('<p>' + '<br>'.join(buf) + '</p>')
    return '\n'.join(out)

def main():
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, encoding='utf-8') as f:
        body = convert(f.read())
    doc = (f'<!doctype html><html lang="ko"><head><meta charset="utf-8">'
           f'<meta name="viewport" content="width=device-width,initial-scale=1">'
           f'<title>NAVER VPN Reconnect</title><style>{CSS}</style></head><body>\n{body}\n</body></html>')
    with open(dst, 'w', encoding='utf-8') as f:
        f.write(doc)

if __name__ == '__main__':
    main()
