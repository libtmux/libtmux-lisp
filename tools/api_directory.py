"""Read a class docstring's capability directory the way the documentation site does.

The site folds three or more bold-led paragraphs, each followed by a paragraph
that holds only references, into a table of task groups. Text that misses the
shape stays ordinary prose, so a malformed directory fails silently there.
"""
import re

LEAD = re.compile(r"^\*\*([^*]+?)\*\*\s*(.*)$")
REFERENCE = re.compile(r"`([a-z][\w.]*:[^\s`]+)`")
MIN_ROWS = 3


def references_only(text):
    """Return the references of a paragraph made of nothing else, or None."""
    references = REFERENCE.findall(text)
    rest = re.sub(r"\band\b", "", REFERENCE.sub("", text))
    return references if references and not re.sub(r"[\s,;.]", "", rest) else None


def fold(body):
    """Return the folded directories and the bold-led titles left as prose.

    Each directory is a run of at least MIN_ROWS rows of (title, references).
    """
    blocks = [" ".join(block.split()) for block in body.split("\n\n") if block.strip()]
    runs, run, strays = [], [], []

    def flush():
        nonlocal run
        if len(run) >= MIN_ROWS:
            runs.append(run)
        else:
            strays.extend(title for title, _ in run)
        run = []

    index = 0
    while index < len(blocks):
        lead = LEAD.match(blocks[index])
        references = references_only(blocks[index + 1]) if lead and index + 1 < len(blocks) else None
        if references:
            run.append((lead.group(1).rstrip(".:"), references))
            index += 2
            continue
        flush()
        if lead:
            strays.append(lead.group(1).rstrip(".:"))
        index += 1
    flush()
    return runs, strays
