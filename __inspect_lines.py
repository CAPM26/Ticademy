from pathlib import Path
text = Path('lib/module_page.dart').read_text().splitlines()
for idx, line in enumerate(text, 1):
    if 'quizStatus' in line:
        print(idx, line)
