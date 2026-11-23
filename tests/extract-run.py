"""Print the run block of a workflow step: extract-run.py <workflow> <step id>."""
import pathlib
import sys

path, step_id = sys.argv[1:3]
lines = pathlib.Path(path).read_text().splitlines()
step = next(i for i, line in enumerate(lines) if line.strip() == f"- id: {step_id}")
step_indent = len(lines[step]) - len(lines[step].lstrip())
run = None
for i in range(step + 1, len(lines)):
    text = lines[i].strip()
    if text.startswith("- ") and len(lines[i]) - len(lines[i].lstrip()) <= step_indent:
        break
    if text == "run: |" or text.startswith("run: | #"):
        run = i
        break
if run is None:
    sys.exit(f"step {step_id} has no run block")
indent = len(lines[run]) - len(lines[run].lstrip()) + 2
body = []
for line in lines[run + 1:]:
    if line.strip() and len(line) - len(line.lstrip()) < indent:
        break
    body.append(line[indent:])
print("\n".join(body))
