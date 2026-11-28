#!/usr/bin/env python3
"""Builds assets/fuzzy/char_readings.txt, the table behind lib/sound_table.dart.

For every Han character it lists how the character is read, without tones, in
Taiwanese and in Mandarin, so the app can tell that 阿銘 and 阿明 sound alike.

    pip install pypinyin opencc-python-reimplemented
    python3 tool/build_char_readings.py

Taiwanese readings come from assets/taigi/reminder_readings.json: a word of n
characters read as n syllables gives each character that syllable, which
collects the literary and the everyday reading of a character (名: bêng, miâ).
A reading counts when the character's own entry has it or two words do, or
when it is the only one on record.
Mandarin readings come from pypinyin: the first reading of each character,
plus any other reading that at least 5% of the phrases with the character use
(樂: le, yue), which leaves out the rare ones (是: ti).
"""

import collections
import json
import re
import unicodedata
from pathlib import Path

import opencc
from pypinyin import Style
from pypinyin.phrases_dict import phrases_dict
from pypinyin.pinyin_dict import pinyin_dict
from pypinyin.style import convert

ROOT = Path(__file__).resolve().parent.parent
TAIGI = ROOT / "assets/taigi/reminder_readings.json"
OUT = ROOT / "assets/fuzzy/char_readings.txt"

TONE_MARKS = "\u0300\u0301\u0302\u0304\u030b\u030c\u030d"
HAN = re.compile("[\u4e00-\u9fff]")


def taigi_syllable(text):
    """POJ without its tone, in ASCII: N for a nasal vowel (ⁿ), O for o͘."""
    plain = "".join(
        c for c in unicodedata.normalize("NFD", text.lower()) if c not in TONE_MARKS
    )
    plain = plain.replace("o\u0358", "O").replace("\u207f", "N")
    return plain if re.fullmatch(r"[a-zNO]+", plain) else None


def taigi_readings():
    # How many words read the character this way; its own entry settles it.
    used = collections.defaultdict(collections.Counter)
    for word, reading in json.loads(TAIGI.read_text(encoding="utf-8")).items():
        syllables = [s for s in re.split(r"[-\s]+", reading) if s]
        if len(syllables) != len(word):
            continue
        for char, syllable in zip(word, syllables):
            plain = taigi_syllable(syllable)
            if plain and HAN.fullmatch(char):
                used[char][plain] += 2 if len(word) == 1 else 1
    # A reading found in one longer word only is often that word's own
    # (明 as mê in 明年) and would make unrelated names sound alike. It is
    # kept when it is all there is for the character.
    return {
        char: {plain for plain, count in counts.items() if count >= 2}
        or set(counts)
        for char, counts in used.items()
    }


def toneless(pinyin):
    plain = convert(pinyin, Style.NORMAL, strict=False).replace("ü", "v")
    return plain if re.fullmatch(r"[a-z]+", plain) else None


def mandarin_readings():
    # How often each reading of a character is used, counted over phrases.
    used = collections.defaultdict(collections.Counter)
    for phrase, syllables in phrases_dict.items():
        if len(phrase) != len(syllables):
            continue
        for char, options in zip(phrase, syllables):
            plain = toneless(options[0])
            if plain:
                used[char][plain] += 1

    # The phrases are mostly in Simplified characters, so a Traditional
    # character also takes the counts of its Simplified forms.
    simplified = collections.defaultdict(set)
    to_simplified = opencc.OpenCC("t2s")
    for config in ("s2t", "s2tw"):
        converter = opencc.OpenCC(config)
        for char in used:
            simplified[converter.convert(char)].add(char)

    readings = collections.defaultdict(set)
    for code in range(0x4E00, 0xA000):
        listed = pinyin_dict.get(code)
        if not listed:
            continue
        char = chr(code)
        first = toneless(listed.split(",")[0])
        if first:
            readings[char].add(first)
        counts = collections.Counter()
        for form in {char, to_simplified.convert(char), *simplified[char]}:
            counts.update(used.get(form, {}))
        total = sum(counts.values())
        for plain, count in counts.items():
            if count >= 3 and count >= 0.05 * total:
                readings[char].add(plain)
    return readings


def lines(tag, readings):
    by_syllable = collections.defaultdict(list)
    for char, syllables in readings.items():
        for syllable in syllables:
            by_syllable[syllable].append(char)
    for syllable in sorted(by_syllable):
        yield f"{tag} {syllable} {''.join(sorted(by_syllable[syllable]))}"


def main():
    taigi = taigi_readings()
    mandarin = mandarin_readings()
    header = [
        "# How Han characters are read, without tones. Made by",
        "# tool/build_char_readings.py; do not edit by hand. See NOTICE.txt.",
        "# T: Taiwanese in POJ (N is a nasal vowel, O is the open o).",
        "# M: Mandarin in Hanyu Pinyin (v is the u with two dots).",
    ]
    body = [*lines("T", taigi), *lines("M", mandarin)]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(header + body) + "\n", encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {OUT.stat().st_size} bytes,")
    print(f"{len(taigi)} characters read in Taiwanese, {len(mandarin)} in Mandarin")


if __name__ == "__main__":
    main()
