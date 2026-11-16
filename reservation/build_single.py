#!/usr/bin/env python3
"""Code.gs + Index.html 을 합쳐 붙여넣기 한 번으로 끝나는 '올인원_Code.gs' 를 만든다."""
import json, os
d = os.path.dirname(os.path.abspath(__file__))
code = open(os.path.join(d, 'Code.gs'), encoding='utf-8').read()
html = open(os.path.join(d, 'Index.html'), encoding='utf-8').read()
old = "return HtmlService.createHtmlOutputFromFile('Index')"
assert old in code
code = code.replace(old, "return HtmlService.createHtmlOutput(INDEX_HTML)")
code += "\n\n// ===== 화면(HTML) — 아래는 고치지 마세요 =====\nvar INDEX_HTML = " + json.dumps(html, ensure_ascii=False) + ";\n"
open(os.path.join(d, '올인원_Code.gs'), 'w', encoding='utf-8').write(code)
print('ok', len(code))
