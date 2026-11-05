#!/usr/bin/env python3
"""Стенограмма субагента Claude Code — по-человечески.

    python3 scripts/dev/wezterm/agent_transcript.py <agent-<id>.jsonl>

Записи стенограммы — JSONL, по объекту на строку; читать это редактором
бесполезно. Скрипт печатает переписку: реплики человека и агента, вызовы
инструментов и их результаты, размышления — коротко, чтобы страницу можно было
читать глазами. Раскладка `~/.claude/projects/<ключ>/<сессия>/subagents/` не
документирована; скрипт её знает ровно настолько, чтобы разобрать строки.
Незнакомую раскладку он не прячет: пустая переписка у живого агента и
неразобранная стенограмма — разные состояния, и о втором скрипт говорит прямо.

Ссылку на стенограмму ставит кубик агента в полосе статусной строки
(`agent:claude-subagent:…`, разбор — `scripts/dev/wezterm/agent_links.lua`);
открывается она этим скриптом в пейджере. Живого субагента снаружи не открыть,
и это именно переписка, а не вход в агента.
"""

import json
import os
import sys

# Пейджер (`less`) закрывается раньше, чем скрипт допишет вывод; без этого
# Python печатает «BrokenPipeError» поверх стенограммы. На Windows такого сигнала
# нет — там ветка просто не сработает.
try:
    import signal

    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except (AttributeError, ImportError, ValueError):
    pass

# Пределы вывода: стенограмма растёт до мегабайтов, а читать её владелец будет
# в пейджере. Реплики и мысли режутся по символам, результаты инструментов —
# по строкам: иначе один `git diff` вытесняет всю переписку.
MAX_THINKING_CHARS = 400
MAX_TOOL_LINES = 12
MAX_TOOL_CHARS = 4000


def blocks(message):
    """Содержимое сообщения списком блоков.

    В живых данных `content` бывает и строкой, и списком блоков; неожиданная
    форма — пустой список, а не падение на всём файле.
    """
    content = message.get("content")
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    if isinstance(content, list):
        return [block for block in content if isinstance(block, dict)]
    return []


def clip(text, limit):
    text = (text or "").strip()
    if len(text) <= limit:
        return text
    return text[:limit].rstrip() + " …"


def clip_lines(text, limit):
    lines = (text or "").rstrip().splitlines()
    if len(lines) <= limit:
        return "\n".join(lines)
    return "\n".join(lines[:limit]) + "\n… ещё %d строк" % (len(lines) - limit)


def stamp_of(record):
    """Дата и время записи коротко: `09-28 21:30`. Нет метки — её нет."""
    moment = record.get("timestamp") or ""
    if len(moment) >= 16 and moment[4] == "-" and moment[10] == "T":
        return moment[5:16].replace("T", " ")
    return ""


def tool_use(block):
    """Строка вызова инструмента: имя и самая говорящая часть входа."""
    name = block.get("name") or "?"
    data = block.get("input")
    if not isinstance(data, dict):
        return name
    for key in ("command", "file_path", "path", "pattern", "url", "description", "prompt"):
        if data.get(key):
            return "%s  %s" % (name, clip(str(data[key]), 240))
    return name


def tool_result(block):
    """Результат инструмента строками. Ошибка помечается явно."""
    content = block.get("content")
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(item.get("text") or "")
        content = "\n".join(parts)
    if not isinstance(content, str):
        content = json.dumps(content, ensure_ascii=False)
    content = clip_lines(content, MAX_TOOL_LINES)
    content = clip(content, MAX_TOOL_CHARS)
    if block.get("is_error"):
        return "ОШИБКА: " + content
    return content


def head(title, stamp):
    return "── %s%s ──" % (title, "  " + stamp if stamp else "")


def indented(text, prefix="  "):
    return [prefix + line if line else line for line in text.splitlines()]


def render(records):
    """Строки стенограммы, готовые к печати."""
    out = []
    for record in records:
        kind = record.get("type")
        message = record.get("message")
        if not isinstance(message, dict):
            continue
        stamp = stamp_of(record)

        if kind == "user":
            texts, results = [], []
            for block in blocks(message):
                if block.get("type") == "tool_result":
                    results.append(block)
                elif block.get("type") == "text" and (block.get("text") or "").strip():
                    texts.append(block.get("text"))
            for text in texts:
                out.append("")
                out.append(head("Пользователь", stamp))
                out.extend(indented(text))
            for block in results:
                out.extend(indented(tool_result(block), "  ← "))

        elif kind == "assistant":
            pieces = blocks(message)
            model = message.get("model") or ""
            out.append("")
            out.append(head("Агент" + (" " + model if model else ""), stamp))
            for block in pieces:
                sort = block.get("type")
                if sort == "text" and (block.get("text") or "").strip():
                    out.extend(indented(block["text"]))
                elif sort == "thinking" and (block.get("thinking") or "").strip():
                    out.extend(indented("(мысль) " + clip(block["thinking"], MAX_THINKING_CHARS)))
                elif sort == "tool_use":
                    out.extend(indented("⚙ " + tool_use(block)))
    return out


def read(path):
    """Записи стенограммы по одной строке; битую строку пропускаем, а не падаем.

    Стенограмма пишется дописыванием, и последняя строка в момент чтения может
    быть недописанной. Молча пропустить её — единственный способ не потерять
    весь файл из-за одной строки.
    """
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except ValueError:
                continue


def main(argv):
    if len(argv) != 2:
        sys.stderr.write(__doc__.strip().splitlines()[0] + "\n")
        return 2
    path = argv[1]
    try:
        records = list(read(path))
        size = os.path.getsize(path)
    except OSError as error:
        print("Стенограмма не читается: %s" % error)
        return 1

    turns = sum(1 for record in records
                if record.get("type") in ("user", "assistant")
                and isinstance(record.get("message"), dict))
    # Раскладка не документирована: непустой файл без единой реплики означает, что
    # поля переименованы или `content` иной формы. Пустая переписка на экране
    # читалась бы как «агент молчит», хотя стенограмма на диске есть, — поэтому
    # неразобранное состояние называется прямо, а не пустым выводом с кодом 0.
    if size and not turns:
        kinds = sorted({str(record.get("type")) for record in records})
        print("Стенограмма не разобрана: %d байт, записей %d, реплик 0" % (size, len(records)))
        print("Виды записей: %s" % (", ".join(kinds) if kinds else "ни одна строка не разобрана"))
        print("Раскладка стенограммы другая — переписки в этом файле показать нечем.")
        return 1
    if not size:
        print("Стенограмма пуста: записей нет.")
        return 0

    print("Переписка субагента")
    print("Файл: %s" % path)
    print("Записей: %d, из них реплик: %d" % (len(records), turns))
    for line in render(records):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
