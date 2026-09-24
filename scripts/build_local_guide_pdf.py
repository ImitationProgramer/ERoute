#!/usr/bin/env python3
"""Render the maintained, explicitly paginated local environment guide."""
import html
import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle,
    Preformatted, KeepTogether,
)

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/operations/local-development-guide-2026-09-21.md'
OUTPUT = ROOT / 'output/pdf/ERoute_개발환경_실행종료_가이드.pdf'
pdfmetrics.registerFont(TTFont('Korean', '/System/Library/Fonts/Supplemental/AppleGothic.ttf'))
pdfmetrics.registerFont(TTFont('Code', '/System/Library/Fonts/Monaco.ttf'))
pdfmetrics.registerFontFamily('Korean', normal='Korean', bold='Korean', italic='Korean', boldItalic='Korean')
INK = colors.HexColor('#1C3049')
MUTED = colors.HexColor('#506985')
BLUE = colors.HexColor('#315B85')
PALE = colors.HexColor('#EEF4FA')
LINE = colors.HexColor('#CEDCEB')
WIDTH = A4[0] - 84
styles = {
    'title': ParagraphStyle('title', fontName='Korean', fontSize=22, leading=29, textColor=INK, spaceAfter=13),
    'heading': ParagraphStyle('heading', fontName='Korean', fontSize=12.4, leading=18, textColor=INK, spaceBefore=9, spaceAfter=6, keepWithNext=True),
    'body': ParagraphStyle('body', fontName='Korean', fontSize=9.5, leading=14.5, textColor=INK, spaceAfter=6, wordWrap='CJK'),
    'table': ParagraphStyle('table', fontName='Korean', fontSize=8.8, leading=13.3, textColor=INK, wordWrap='CJK'),
    'note': ParagraphStyle('note', fontName='Korean', fontSize=9, leading=14, textColor=MUTED, wordWrap='CJK'),
    'bullet': ParagraphStyle('bullet', fontName='Korean', fontSize=9.5, leading=14.5, textColor=INK, leftIndent=10, firstLineIndent=-10, spaceAfter=4, wordWrap='CJK'),
    'code': ParagraphStyle('code', fontName='Code', fontSize=8.2, leading=11.5, textColor=INK),
}

def markup(text):
    text = html.escape(text).replace('&lt;br/&gt;', '<br/>')
    text = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', text)
    return re.sub(r'\[([^\]]+)\]\((https://[^)]+)\)', r'<link href="\2" color="#315B85"><u>\1</u></link>', text)

def para(text, kind='body'):
    return Paragraph(markup(text), styles[kind])

def box(content, background=PALE):
    t = Table([[content]], colWidths=[WIDTH])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), background),
        ('LEFTPADDING', (0, 0), (-1, -1), 12),
        ('RIGHTPADDING', (0, 0), (-1, -1), 12),
        ('TOPPADDING', (0, 0), (-1, -1), 8),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
    ]))
    return t

pages = SOURCE.read_text().split('<!-- page -->')
story = []
for page_index, page in enumerate(pages):
    if page_index:
        story.append(PageBreak())
    lines = page.strip().splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if line.startswith('```'):
            code = []
            i += 1
            while not lines[i].startswith('```'):
                code.append(lines[i])
                i += 1
            max_width = max(pdfmetrics.stringWidth(s, 'Code', 8.2) for s in code)
            assert max_width <= WIDTH - 24, (max_width, code)
            story.extend([box(Preformatted('\n'.join(code), styles['code'])), Spacer(1, 8)])
        elif line.startswith('|'):
            rows = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                rows.append([para(x.strip(), 'table') for x in lines[i].strip().strip('|').split('|')])
                i += 1
            table = Table(rows, colWidths=[112, WIDTH - 112], hAlign='LEFT')
            table.setStyle(TableStyle([
                ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                ('BACKGROUND', (0, 0), (0, -1), PALE),
                ('LINEBELOW', (0, 0), (-1, -1), 0.4, LINE),
                ('LEFTPADDING', (0, 0), (-1, -1), 9),
                ('RIGHTPADDING', (0, 0), (-1, -1), 9),
                ('TOPPADDING', (0, 0), (-1, -1), 6),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
            ]))
            story.extend([table, Spacer(1, 8)])
            continue
        elif line.startswith('# '):
            story.append(para(line[2:], 'title'))
        elif line.startswith('## '):
            story.append(para(line[3:], 'heading'))
        elif line.startswith('> '):
            story.extend([Spacer(1, 3), box(para(line[2:], 'note')), Spacer(1, 7)])
        elif line.startswith('- '):
            story.append(para('• ' + line[2:], 'bullet'))
        else:
            story.append(para(line))
        i += 1

def decorate(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(BLUE)
    canvas.rect(0, A4[1] - 7, A4[0], 7, fill=1, stroke=0)
    canvas.setFont('Code', 8)
    canvas.drawString(42, A4[1] - 34, 'EROUTE / LOCAL DEVELOPMENT / 2026.09.21')
    canvas.setStrokeColor(LINE)
    canvas.line(42, 38, A4[0] - 42, 38)
    canvas.setFillColor(MUTED)
    canvas.setFont('Korean', 8)
    canvas.drawString(42, 24, 'Mac 개발환경 · 기존 데이터와 일반 앱 유지')
    canvas.drawRightString(A4[0] - 42, 24, f'{doc.page} / {len(pages)}')
    canvas.restoreState()

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
doc = SimpleDocTemplate(str(OUTPUT), pagesize=A4, leftMargin=42, rightMargin=42,
                       topMargin=57, bottomMargin=49, title='ERoute 개발환경 실행·종료 가이드 | 2026-09-21',
                       author='ERoute', subject='일반 앱 연결, 비밀번호 인증, 개발환경 실행·업데이트·종료')
doc.build(story, onFirstPage=decorate, onLaterPages=decorate)
from pypdf import PdfReader
reader = PdfReader(OUTPUT)
assert len(reader.pages) == len(pages), f'Unexpected page overflow: {len(reader.pages)} vs {len(pages)}'
print(f'Created {OUTPUT} ({len(reader.pages)} pages)')
