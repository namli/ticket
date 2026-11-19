"""Step definitions for the ticket-web plugin (tk web)."""

import http.client
import os
import select
import subprocess
import threading
import time
import urllib.parse
from html.parser import HTMLParser
from pathlib import Path

from behave import given, when, then, use_step_matcher

use_step_matcher("re")

QUOTED = r'(?:[^"\\]|\\.)*'


def unquote(text):
    return text.replace('\\"', '"')


# ============================================================================
# Minimal DOM, enough to assert on the server's HTML
# ============================================================================

VOID = {'input', 'br', 'meta', 'link', 'hr', 'img'}


class Node:
    def __init__(self, tag, attrs, parent):
        self.tag = tag
        self.attrs = attrs
        self.parent = parent
        self.children = []

    def text(self):
        return ''.join(c if isinstance(c, str) else c.text() for c in self.children)

    def classes(self):
        return (self.attrs.get('class') or '').split()

    def walk(self):
        for child in self.children:
            if isinstance(child, Node):
                yield child
                yield from child.walk()

    def find_all(self, tag=None, cls=None, **attrs):
        return [n for n in self.walk()
                if (tag is None or n.tag == tag)
                and (cls is None or cls in n.classes())
                and all(n.attrs.get(k.replace('_', '-')) == v for k, v in attrs.items())]

    def find(self, tag=None, cls=None, **attrs):
        found = self.find_all(tag, cls, **attrs)
        return found[0] if found else None


class Dom(HTMLParser):
    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.root = Node('#root', {}, None)
        self.cur = self.root
        self.feed(html)
        self.close()

    def handle_starttag(self, tag, attrs):
        node = Node(tag, dict(attrs), self.cur)
        self.cur.children.append(node)
        if tag not in VOID:
            self.cur = node

    def handle_endtag(self, tag):
        node = self.cur
        while node is not self.root and node.tag != tag:
            node = node.parent
        if node is not self.root:
            self.cur = node.parent

    def handle_data(self, data):
        self.cur.children.append(data)


def dom(context):
    return Dom(context.web_body).root


def parse_form(html):
    """Return the edit form fields the way a browser would submit them."""
    root = Dom(html).root
    form = root.find('form')
    assert form is not None, f"No form in response:\n{html[:2000]}"
    fields = {}
    for node in form.find_all('input'):
        if node.attrs.get('name'):
            fields[node.attrs['name']] = node.attrs.get('value') or ''
    for node in form.find_all('textarea'):
        value = node.text()
        if value.startswith('\n'):          # a browser drops one leading line break
            value = value[1:]
        fields[node.attrs['name']] = value
    return fields


# ============================================================================
# Helpers
# ============================================================================

def ticket_script(context):
    return os.environ.get('TICKET_SCRIPT') or str(Path(context.project_dir) / 'ticket')


def project_dir(context, name):
    return Path(context.test_dir) / name


def ticket_file(context, ref):
    name, ticket_id = ref.split('/', 1)
    return project_dir(context, name) / '.tickets' / f'{ticket_id}.md'


def register_project(context, name):
    if not hasattr(context, 'web_projects'):
        context.web_projects = []
    context.web_projects.append(name)


def config_path(context):
    return Path(context.test_dir) / 'web.toml'


def write_config(context):
    lines = []
    for name in getattr(context, 'web_projects', []):
        lines += ['[[project]]', f'name = "{name}"', f'path = "{project_dir(context, name)}"', '']
    config_path(context).write_text('\n'.join(lines))


def web_env():
    env = os.environ.copy()
    env.pop('TK_WEB_CONFIG', None)
    env.pop('TICKETS_DIR', None)
    return env


def start_server(context, args, env):
    stderr_file = open(Path(context.test_dir) / 'web.stderr', 'w')
    proc = subprocess.Popen(
        [ticket_script(context), 'web'] + args,
        cwd=context.test_dir, env=env, text=True,
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=stderr_file,
    )
    context.web_proc = proc
    ready, _, _ = select.select([proc.stdout], [], [], 10)
    line = proc.stdout.readline().strip() if ready else ''
    if not line.startswith('tk web: http://127.0.0.1:'):
        proc.kill()
        stderr_file.close()
        err = (Path(context.test_dir) / 'web.stderr').read_text()
        raise AssertionError(f"Server did not start. First line: {line!r}\nstderr: {err}")
    context.web_base = line.split('tk web: ', 1)[1].rstrip('/')
    context.web_port = int(context.web_base.rsplit(':', 1)[1])


def request(context, method, path, body=None, headers=None):
    conn = http.client.HTTPConnection('127.0.0.1', context.web_port, timeout=10)
    hdrs = {}
    if body is not None:
        hdrs['Content-Type'] = 'application/x-www-form-urlencoded'
    for key, value in (headers or {}).items():
        hdrs[key] = value.replace('<port>', str(context.web_port))
    conn.request(method, path, body=body, headers=hdrs)
    resp = conn.getresponse()
    context.web_status = resp.status
    context.web_headers = {k.lower(): v for k, v in resp.getheaders()}
    context.web_body = resp.read().decode('utf-8')
    conn.close()


def parse_header(text):
    key, value = unquote(text).split(':', 1)
    return {key.strip(): value.strip()}


def cards_in(node):
    return [c for c in node.walk() if 'card' in c.classes()]


def id_list(text):
    return [part.strip() for part in text.split(',') if part.strip()]


def lane(context, name):
    found = dom(context).find(cls='lane', data_project=name)
    assert found is not None, f"No lane for project {name!r} in:\n{context.web_body[:3000]}"
    return found


# ============================================================================
# Given: projects, tickets, config, server
# ============================================================================

@given(r'a web project "(?P<name>[^"]+)" without a tickets directory')
def step_web_project_bare(context, name):
    project_dir(context, name).mkdir(parents=True)
    register_project(context, name)


@given(r'a web project "(?P<name>[^"]+)"')
def step_web_project(context, name):
    (project_dir(context, name) / '.tickets').mkdir(parents=True)
    register_project(context, name)


@given(r'web project "(?P<name>[^"]+)" has tickets:')
def step_web_tickets(context, name):
    headings = context.table.headings
    for row in context.table:
        def cell(key, default=''):
            return row[key].strip() if key in headings and row[key].strip() else default
        ticket_id = cell('id')
        lines = [
            '---',
            f'id: {ticket_id}',
            f'status: {cell("status", "open")}',
            f'deps: [{", ".join(cell("deps").split())}]',
            'links: []',
            'created: 2025-01-01T00:00:00Z',
            f'type: {cell("type", "task")}',
            f'priority: {cell("priority", "2")}',
        ]
        if cell('parent'):
            lines.append(f'parent: {cell("parent")}')
        if cell('tags'):
            lines.append(f'tags: [{", ".join(cell("tags").split())}]')
        lines += ['---', f'# {cell("title", ticket_id)}', '', f'Description of {ticket_id}', '']
        if cell('last_note'):
            lines += ['## Notes', '', f'**{cell("last_note")}**', '', 'Closed: done', '']
        ticket_file(context, f'{name}/{ticket_id}').write_text('\n'.join(lines), encoding='utf-8')


@given(r'web project "(?P<name>[^"]+)" has (?P<count>\d+) closed tickets')
def step_web_closed_tickets(context, name, count):
    for i in range(1, int(count) + 1):
        ticket_id = f'c-{i:04d}'
        text = '\n'.join([
            '---', f'id: {ticket_id}', 'status: closed', 'deps: []', 'links: []',
            'created: 2025-01-01T00:00:00Z', 'type: task', 'priority: 2', '---',
            f'# Closed {i}', '', 'Done.', '', '## Notes', '',
            f'**2026-01-01T00:{i // 60:02d}:{i % 60:02d}Z**', '', 'Closed: done', '',
        ])
        ticket_file(context, f'{name}/{ticket_id}').write_text(text)


@given(r'web ticket "(?P<ref>[^"]+)" has content:')
def step_web_ticket_content(context, ref):
    path = ticket_file(context, ref)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(context.text + '\n', encoding='utf-8')


@given(r'web ticket "(?P<ref>[^"]+)" has raw bytes "(?P<hexdata>[0-9a-fA-F]+)"')
def step_web_ticket_bytes(context, ref, hexdata):
    ticket_file(context, ref).write_bytes(bytes.fromhex(hexdata))


@given(r'a web config:')
def step_web_config(context):
    config_path(context).write_text(context.text.replace('{dir}', context.test_dir) + '\n')


@given(r'the web server is running with the config in TK_WEB_CONFIG')
def step_server_running_env(context):
    write_config(context)
    env = web_env()
    env['TK_WEB_CONFIG'] = str(config_path(context))
    start_server(context, ['--port', '0'], env)


@given(r'the web server is running')
def step_server_running(context):
    write_config(context)
    start_server(context, ['--port', '0', '--config', str(config_path(context))], web_env())


# ============================================================================
# When: HTTP, files
# ============================================================================

@when(r'I GET "(?P<path>[^"]+)" with header "(?P<header>' + QUOTED + r')"')
def step_get_with_header(context, path, header):
    request(context, 'GET', path, headers=parse_header(header))


@when(r'I GET "(?P<path>[^"]+)"')
def step_get(context, path):
    request(context, 'GET', path)


@when(r'I open the edit form of "(?P<ref>[^"]+)"')
def step_open_form(context, ref):
    name, ticket_id = ref.split('/', 1)
    context.web_form_path = f'/p/{name}/{ticket_id}/edit'
    request(context, 'GET', context.web_form_path)
    assert context.web_status == 200, f"Expected 200, got {context.web_status}\n{context.web_body[:2000]}"
    context.web_form = parse_form(context.web_body)
    context.web_file_before = ticket_file(context, ref).read_bytes()


@when(r'I take the form from the response')
def step_take_form(context):
    context.web_form = parse_form(context.web_body)


def submit(context, headers=None):
    fields = dict(context.web_form)
    if context.table is not None:
        for row in context.table:
            fields[row['field']] = row['value'].replace('\\r', '\r').replace('\\n', '\n')
    body = urllib.parse.urlencode(fields).encode('utf-8')
    request(context, 'POST', context.web_form_path, body=body, headers=headers)


@when(r'I submit the form with header "(?P<header>' + QUOTED + r')" and:')
def step_submit_header(context, header):
    submit(context, parse_header(header))


@when(r'I submit the form with:')
def step_submit_with(context):
    submit(context)


@when(r'I submit the form unchanged')
def step_submit_unchanged(context):
    context.table = None
    submit(context)


@when(r'web ticket "(?P<ref>[^"]+)" file has "(?P<old>[^"]+)" replaced by "(?P<new>[^"]*)"')
def step_file_replace(context, ref, old, new):
    path = ticket_file(context, ref)
    text = path.read_text(encoding='utf-8')
    assert old in text, f"{old!r} not in {path}"
    path.write_text(text.replace(old, new), encoding='utf-8')


@when(r'a note "(?P<text>[^"]+)" is appended to web ticket "(?P<ref>[^"]+)"')
def step_append_note(context, text, ref):
    path = ticket_file(context, ref)
    content = path.read_text(encoding='utf-8')
    if '## Notes' not in content:
        content += '\n## Notes\n'
    content += f'\n**2026-06-01T00:00:00Z**\n\n{text}\n'
    path.write_text(content, encoding='utf-8')


@when(r'web ticket "(?P<ref>[^"]+)" is deleted')
def step_delete_ticket(context, ref):
    ticket_file(context, ref).unlink()


@when(r'I start a second web server on the same port')
def step_second_server(context):
    result = subprocess.run(
        [ticket_script(context), 'web', '--port', str(context.web_port),
         '--config', str(config_path(context))],
        cwd=context.test_dir, env=web_env(), capture_output=True, text=True,
        stdin=subprocess.DEVNULL, timeout=10,
    )
    context.result = result
    context.stdout = result.stdout.strip()
    context.stderr = result.stderr.strip()
    context.returncode = result.returncode


@when(r'in web project "(?P<name>[^"]+)" I run "(?P<command>' + QUOTED + r')"')
def step_run_in_project(context, name, command):
    command = unquote(command).replace('ticket ', ticket_script(context) + ' ', 1)
    result = subprocess.run(
        command, shell=True, cwd=project_dir(context, name), env=web_env(),
        capture_output=True, text=True, stdin=subprocess.DEVNULL,
    )
    context.result = result
    context.stdout = result.stdout.strip()
    context.stderr = result.stderr.strip()
    context.returncode = result.returncode


# ============================================================================
# When/Then: server-sent events
# ============================================================================

@when(r'I listen to "(?P<path>[^"]+)"')
def step_listen(context, path):
    conn = http.client.HTTPConnection('127.0.0.1', context.web_port, timeout=30)
    conn.request('GET', path)
    resp = conn.getresponse()
    context.web_status = resp.status
    context.web_headers = {k.lower(): v for k, v in resp.getheaders()}
    context.web_events = []
    context.web_event_conn = conn
    context.web_event_resp = resp

    def reader(lines):
        try:
            while True:
                line = resp.fp.readline()
                if not line:
                    return
                lines.append(line.decode('utf-8').rstrip('\n'))
        except (OSError, ValueError, AttributeError):
            return

    threading.Thread(target=reader, args=(context.web_events,), daemon=True).start()
    deadline = time.time() + 5
    while not context.web_events and time.time() < deadline:
        time.sleep(0.05)
    assert context.web_events, "The event stream sent nothing within 5 seconds"


@when(r'I stop listening')
def step_stop_listening(context):
    try:
        context.web_event_resp.close()
        context.web_event_conn.close()
    except OSError:
        pass
    time.sleep(0.2)


def data_lines(context):
    return [line for line in context.web_events if line.startswith('data:')]


@then(r'an event "(?P<data>[^"]+)" should arrive within (?P<seconds>\d+) seconds')
def step_event_arrives(context, data, seconds):
    deadline = time.time() + int(seconds)
    while time.time() < deadline:
        if any(line == f'data: {data}' for line in data_lines(context)):
            return
        time.sleep(0.1)
    raise AssertionError(f"No event {data!r}. Lines: {context.web_events}")


@then(r'no event should arrive within (?P<seconds>\d+) seconds')
def step_no_event(context, seconds):
    time.sleep(int(seconds))
    assert not data_lines(context), f"Unexpected events: {context.web_events}"


@then(r'the first event line should be a comment')
def step_first_line_comment(context):
    assert context.web_events[0].startswith(':'), f"Lines: {context.web_events}"


# ============================================================================
# Then: responses
# ============================================================================

@then(r'the response status should be (?P<status>\d+)')
def step_status(context, status):
    assert context.web_status == int(status), \
        f"Expected status {status}, got {context.web_status}\n{context.web_body[:3000]}"


@then(r'the response should contain "(?P<text>' + QUOTED + r')"')
def step_response_contains(context, text):
    text = unquote(text)
    assert text in context.web_body, f"Expected {text!r} in response:\n{context.web_body[:4000]}"


@then(r'the response should not contain "(?P<text>' + QUOTED + r')"')
def step_response_not_contains(context, text):
    text = unquote(text)
    assert text not in context.web_body, f"Did not expect {text!r} in response:\n{context.web_body[:4000]}"


@then(r'the response header "(?P<key>[^"]+)" should be "(?P<value>[^"]*)"')
def step_header(context, key, value):
    actual = context.web_headers.get(key.lower())
    assert actual == value, f"Expected header {key}: {value!r}, got {actual!r}"


@then(r'the response header "(?P<key>[^"]+)" should contain "(?P<value>[^"]*)"')
def step_header_contains(context, key, value):
    actual = context.web_headers.get(key.lower()) or ''
    assert value in actual, f"Expected header {key} to contain {value!r}, got {actual!r}"


@then(r'project "(?P<name>[^"]+)" column "(?P<col>[^"]+)" should list "(?P<ids>[^"]*)"')
def step_column_lists(context, name, col, ids):
    column = lane(context, name).find(cls='col', data_col=col)
    assert column is not None, f"No column {col!r} in lane {name!r}"
    actual = [c.attrs.get('data-id') for c in cards_in(column) if c.attrs.get('data-id')]
    assert actual == id_list(ids), f"Expected {id_list(ids)}, got {actual}"


@then(r'column "(?P<col>[^"]+)" should list "(?P<refs>[^"]*)"')
def step_flat_column_lists(context, col, refs):
    column = dom(context).find(cls='col', data_col=col)
    assert column is not None, f"No column {col!r} in:\n{context.web_body[:3000]}"
    actual = [f"{c.attrs.get('data-project')}/{c.attrs.get('data-id')}"
              for c in cards_in(column) if c.attrs.get('data-id')]
    assert actual == id_list(refs), f"Expected {id_list(refs)}, got {actual}"


def find_card(context, ref):
    name, ticket_id = ref.split('/', 1)
    card = dom(context).find(cls='card', data_project=name, data_id=ticket_id)
    assert card is not None, f"No card {ref} in:\n{context.web_body[:3000]}"
    return card


@then(r'card "(?P<ref>[^"]+)" should have class "(?P<cls>[^"]+)"')
def step_card_has_class(context, ref, cls):
    card = find_card(context, ref)
    assert cls in card.classes(), f"Card {ref} classes: {card.classes()}"


@then(r'card "(?P<ref>[^"]+)" should not have class "(?P<cls>[^"]+)"')
def step_card_lacks_class(context, ref, cls):
    card = find_card(context, ref)
    assert cls not in card.classes(), f"Card {ref} classes: {card.classes()}"


@then(r'card "(?P<ref>[^"]+)" should contain "(?P<text>[^"]+)"')
def step_card_contains(context, ref, text):
    card = find_card(context, ref)
    assert text in card.text(), f"Card {ref} text: {card.text()!r}"


@then(r'every card should have a search text')
def step_cards_have_search(context):
    cards = [c for c in cards_in(dom(context)) if c.attrs.get('data-id')]
    assert cards, "No cards in the response"
    for card in cards:
        search = card.attrs.get('data-search') or ''
        assert card.attrs['data-id'].lower() in search, f"Card {card.attrs} has search {search!r}"
        assert search == search.lower(), f"Search text is not lower case: {search!r}"


@then(r'the lane of project "(?P<name>[^"]+)" should show "(?P<text>[^"]+)"')
def step_lane_shows(context, name, text):
    actual = lane(context, name).text()
    assert text in actual, f"Expected {text!r} in lane {name!r}: {actual!r}"


@then(r'the lane of project "(?P<name>[^"]+)" should show an error containing "(?P<text>[^"]+)"')
def step_lane_error(context, name, text):
    error = lane(context, name).find(cls='lane-error')
    assert error is not None, f"No lane-error in lane {name!r}"
    assert text in error.text(), f"Expected {text!r} in {error.text()!r}"


@then(r'the lane of project "(?P<name>[^"]+)" should show no error')
def step_lane_no_error(context, name):
    assert lane(context, name).find(cls='lane-error') is None, "Unexpected lane-error"


@then(r'relation "(?P<rel>[^"]+)" should list "(?P<ids>[^"]*)"')
def step_relation_lists(context, rel, ids):
    node = dom(context).find('ul', data_rel=rel)
    actual = [] if node is None else [li.attrs.get('data-id') for li in node.find_all('li')]
    assert actual == id_list(ids), f"Expected {id_list(ids)}, got {actual}"


@then(r'relation "(?P<rel>[^"]+)" should contain "(?P<text>[^"]+)"')
def step_relation_contains(context, rel, text):
    node = dom(context).find('ul', data_rel=rel)
    assert node is not None and text in node.text(), \
        f"Expected {text!r} in relation {rel!r}: {node.text() if node else None!r}"


@then(r'relation "(?P<rel>[^"]+)" should have no link to "(?P<ticket_id>[^"]+)"')
def step_relation_no_link(context, rel, ticket_id):
    node = dom(context).find('ul', data_rel=rel)
    assert node is not None, f"No relation {rel!r}"
    hrefs = [a.attrs.get('href', '') for a in node.find_all('a')]
    assert not any(h.endswith('/' + ticket_id) for h in hrefs), f"Links: {hrefs}"


@then(r'the form field "(?P<field>[^"]+)" should be "(?P<value>[^"]*)"')
def step_form_field(context, field, value):
    actual = context.web_form.get(field)
    assert actual == value, f"Expected {field} = {value!r}, got {actual!r}"


@then(r'the form field "(?P<field>[^"]+)" should match "(?P<pattern>[^"]+)"')
def step_form_field_matches(context, field, pattern):
    import re
    actual = context.web_form.get(field) or ''
    assert re.fullmatch(pattern, actual), f"{field} = {actual!r} does not match {pattern!r}"


@then(r'the disk text of field "(?P<field>[^"]+)" should contain "(?P<text>[^"]+)"')
def step_disk_text(context, field, text):
    node = dom(context).find('pre', cls='disk', data_field=field)
    assert node is not None, f"No disk text for {field!r} in:\n{context.web_body[:3000]}"
    assert text in node.text(), f"Expected {text!r} in {node.text()!r}"


@then(r'the main element should not contain the search box')
def step_search_outside_main(context):
    root = dom(context)
    assert root.find('input', id='q') is not None, "No search box"
    main = root.find('main')
    assert main is not None and main.find('input', id='q') is None, "Search box is inside <main>"


@then(r'GET "(?P<path>[^"]+)" should eventually contain "(?P<text>[^"]+)"')
def step_eventually(context, path, text):
    deadline = time.time() + 5
    while True:
        request(context, 'GET', path)
        if text in context.web_body:
            return
        if time.time() > deadline:
            raise AssertionError(f"{text!r} never appeared at {path}:\n{context.web_body[:3000]}")
        time.sleep(0.2)


# ============================================================================
# Then: files
# ============================================================================

@then(r'web ticket "(?P<ref>[^"]+)" file should contain "(?P<text>' + QUOTED + r')"')
def step_file_contains(context, ref, text):
    content = ticket_file(context, ref).read_text(encoding='utf-8')
    text = unquote(text).replace('\\n', '\n')
    assert text in content, f"Expected {text!r} in file:\n{content}"


@then(r'web ticket "(?P<ref>[^"]+)" file should not contain "(?P<text>' + QUOTED + r')"')
def step_file_not_contains(context, ref, text):
    content = ticket_file(context, ref).read_bytes().decode('utf-8')
    text = unquote(text).replace('\\r', '\r').replace('\\n', '\n')
    assert text not in content, f"Did not expect {text!r} in file:\n{content}"


@then(r'web ticket "(?P<ref>[^"]+)" file should be:')
def step_file_is(context, ref):
    content = ticket_file(context, ref).read_text(encoding='utf-8')
    expected = context.text + '\n'
    assert content == expected, f"Expected:\n{expected!r}\nGot:\n{content!r}"


@then(r'web ticket "(?P<ref>[^"]+)" file should be unchanged')
def step_file_unchanged(context, ref):
    assert ticket_file(context, ref).read_bytes() == context.web_file_before, \
        f"File changed:\n{ticket_file(context, ref).read_text(encoding='utf-8')}"


def front_matter_and_notes(data):
    text = data.decode('utf-8')
    lines = text.split('\n')
    second = [i for i, line in enumerate(lines) if line == '---'][1]
    front = '\n'.join(lines[:second + 1])
    notes = text[text.index('## Notes'):] if '## Notes' in text else ''
    return front, notes


@then(r'web ticket "(?P<ref>[^"]+)" front matter and notes should be unchanged')
def step_front_notes_unchanged(context, ref):
    before = front_matter_and_notes(context.web_file_before)
    after = front_matter_and_notes(ticket_file(context, ref).read_bytes())
    assert before == after, f"Before: {before!r}\nAfter: {after!r}"


@then(r'in web ticket "(?P<ref>[^"]+)" file "(?P<first>[^"]+)" should come before "(?P<second>[^"]+)"')
def step_file_order(context, ref, first, second):
    content = ticket_file(context, ref).read_text(encoding='utf-8')
    assert first in content and second in content, f"Missing text in:\n{content}"
    assert content.index(first) < content.index(second), f"Wrong order in:\n{content}"


@then(r'no temp file should remain in web project "(?P<name>[^"]+)"')
def step_no_temp(context, name):
    names = sorted(p.name for p in (project_dir(context, name) / '.tickets').iterdir())
    assert all(n.endswith('.md') for n in names), f"Leftover files: {names}"
