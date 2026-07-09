import json, glob, os, collections

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
CORPUS = os.path.join(ROOT, 'v0', 'data', 'corpus.json')
PHRASING = os.path.join(ROOT, 'planning', 'phrasing')

REMINDER_SKILLS = {'set-daily-reminder', 'set-weekly-reminder', 'set-biweekly-reminder',
                   'set-monthly-reminder', 'set-reminder'}

def dump_corpus(entries, path):
    lines = ['[']
    for i, e in enumerate(entries):
        comma = ',' if i < len(entries) - 1 else ''
        lines.append('  { "skillId": %s, "template": %s }%s' % (
            json.dumps(e['skillId']), json.dumps(e['template'], ensure_ascii=False), comma))
    lines.append(']')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')

corpus = json.load(open(CORPUS, encoding='utf-8'))
seen = {e['template'] for e in corpus}

reminder_adds, meal_adds, other_adds = [], [], []
template_adds = collections.defaultdict(list)  # targetFile -> [entry]
report = collections.Counter()

for f in sorted(glob.glob(os.path.join(PHRASING, '*.json'))):
    j = json.load(open(f, encoding='utf-8'))
    for a in j.get('additions', []):
        tf = a.get('targetFile', 'corpus.json')
        t = a['template']
        e = {'skillId': a['skillId'], 'template': t}
        if tf != 'corpus.json':
            template_adds[tf].append(e)
            continue
        if t in seen:
            report['dup'] += 1
            continue
        seen.add(t)
        if a['skillId'] in REMINDER_SKILLS:
            reminder_adds.append(e)
        elif a['skillId'] == 'log-meal':
            meal_adds.append(e)
        else:
            other_adds.append(e)

# insert new reminder templates BEFORE the first existing one-off set-reminder (recurring must win)
idx = next((i for i, e in enumerate(corpus) if e['skillId'] == 'set-reminder'), len(corpus))
new_corpus = corpus[:idx] + reminder_adds + corpus[idx:] + other_adds + meal_adds
dump_corpus(new_corpus, CORPUS)
report['corpus_reminders'] = len(reminder_adds)
report['corpus_other'] = len(other_adds)
report['corpus_meal_last'] = len(meal_adds)

# tracker template files: append to each template's own corpus array (dedup vs it)
for tf, adds in template_adds.items():
    path = os.path.join(ROOT, 'v0', 'data', tf.replace('/', os.sep))
    tj = json.load(open(path, encoding='utf-8'))
    have = {c['template'] for c in tj.get('corpus', [])}
    added = 0
    for e in adds:
        if e['template'] in have:
            continue
        have.add(e['template'])
        tj.setdefault('corpus', []).append(e)
        added += 1
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        json.dump(tj, fh, ensure_ascii=False, indent=2)
        fh.write('\n')
    report['tmpl:' + tf] = added

print('corpus total now:', len(new_corpus))
for k, v in sorted(report.items()):
    print(f'  {k}: {v}')
