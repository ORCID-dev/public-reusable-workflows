"""Print the run block of a workflow step: extract-run.py <workflow> <step id>."""
import pathlib
import sys

path, step_id = sys.argv[1:3]
lines = pathlib.Path(path).read_text().splitlines()
step = next(i for i, line in enumerate(lines) if line.strip() == f"- id: {step_id}")
run = next(i for i in range(step, len(lines)) if lines[i].strip() == "run: |")
indent = len(lines[run]) - len(lines[run].lstrip()) + 2
body = []
for line in lines[run + 1:]:
    if line.strip() and len(line) - len(line.lstrip()) < indent:
        break
    body.append(line[indent:])
print("\n".join(body))
