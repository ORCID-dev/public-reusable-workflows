"""Print the run block of the `version` step from version.yml."""
import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
step = next(i for i, line in enumerate(lines) if line.strip() == "- id: version")
run = next(i for i in range(step, len(lines)) if lines[i].strip() == "run: |")
indent = len(lines[run]) - len(lines[run].lstrip()) + 2
body = []
for line in lines[run + 1:]:
    if line.strip() and len(line) - len(line.lstrip()) < indent:
        break
    body.append(line[indent:])
print("\n".join(body))
