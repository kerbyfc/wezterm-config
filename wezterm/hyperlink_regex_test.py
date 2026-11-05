"""Тесты регулярки правила ссылок из file_links.lua.

WezTerm исполняет её движком fancy-regex, из Lua его не вызвать. Python `re` для этого
шаблона ведёт себя так же: lookbehind фиксированной ширины, ленивые повторы, lookahead.

    python3 scripts/dev/wezterm/hyperlink_regex_test.py
"""

import pathlib
import re
import sys

SOURCE = pathlib.Path(__file__).with_name("file_links.lua").read_text(encoding="utf-8")
REGEX = re.compile(re.search(r"M\.hyperlink_regex = \[==\[(.*?)\]==\]", SOURCE).group(1))

# строка вывода терминала -> ссылки, которые в ней должны найтись
CASES = [
    ("Правка в obsidian/Игра/Карты/Огненный шар.md:12 готова",
     ["obsidian/Игра/Карты/Огненный шар.md:12"]),
    ("- `obsidian/Внедрение механизма консистентности.md`",
     ["obsidian/Внедрение механизма консистентности.md"]),
    ("apps/game/x.go:12 — см. obsidian/a b.md", ["apps/game/x.go:12", "obsidian/a b.md"]),
    ("a/b.go и c/d e.md", ["a/b.go", "c/d e.md"]),
    ("см. README.md, debt.md и main.go.", ["README.md", "debt.md", "main.go"]),
    (r"C:\Users\u\project\obsidian\Игра\a b.md", [r"C:\Users\u\project\obsidian\Игра\a b.md"]),
    (r"C:\Users\u\app\main.go", [r"C:\Users\u\app\main.go"]),
    ("/c/Users/u/project/obsidian/x.md", ["/c/Users/u/project/obsidian/x.md"]),
    ("[Заметка](obsidian/Foo%20Bar.md)", ["obsidian/Foo%20Bar.md"]),
    ("~/notes/a.png и ./scripts/dev/wezterm/smoke.lua:14", ["~/notes/a.png", "./scripts/dev/wezterm/smoke.lua:14"]),
    ("archive.tar.gz apps/.golangci.yml", ["archive.tar.gz", "apps/.golangci.yml"]),
    # позиция в файле: так печатают компилятор Go, линтеры и агент
    ("card.go:358:5: undefined: x", ["card.go:358:5"]),
    ("    /Users/a/apps/game/card.go:358 +0x24", ["/Users/a/apps/game/card.go:358"]),
    ("хвост не цифры — только путь: x.go:abc", ["x.go"]),
    # не ссылки: URL и почта — встроенные правила WezTerm; числа; файлы без расширения
    ("https://example.com/docs/a.md и file:///Users/a/x.md", []),
    ("0.577 v1.2 a@b.com .gitignore Makefile", []),
]


# Правило голого URL из wezterm.lua: завершающая `)` в адрес не входит, иначе
# закрывающая скобка markdown-ссылки уезжает в URL и ломает последний параметр.
URL_SOURCE = pathlib.Path(__file__).with_name("wezterm.lua").read_text(encoding="utf-8")
URL_REGEX = re.compile(re.search(r"regex = \[==\[(.+?)\]==\], format = '\$0'", URL_SOURCE).group(1))

URL_CASES = [
    ("[Заметка](obsidian://adv-uri?uid=b34fc653-1a43-4f26-b904-c70d2d6b843a&vault=obsidian)",
     ["obsidian://adv-uri?uid=b34fc653-1a43-4f26-b904-c70d2d6b843a&vault=obsidian"]),
    ("[!271](https://gitlab.com/kerbyfc/project/-/merge_requests/271)",
     ["https://gitlab.com/kerbyfc/project/-/merge_requests/271"]),
    ("обычный obsidian://adv-uri?uid=abc&vault=obsidian без скобок",
     ["obsidian://adv-uri?uid=abc&vault=obsidian"]),
]


def main() -> int:
    failed = 0
    for line, want in CASES:
        got = [m.group(0) for m in REGEX.finditer(line)]
        if got != want:
            failed += 1
            print(f"FAIL {line!r}\n  ожидание: {want}\n  получено: {got}")
    for line, want in URL_CASES:
        got = [m.group(0) for m in URL_REGEX.finditer(line)]
        if got != want:
            failed += 1
            print(f"FAIL URL {line!r}\n  ожидание: {want}\n  получено: {got}")
    total = len(CASES) + len(URL_CASES)
    print(f"{total - failed} из {total}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
