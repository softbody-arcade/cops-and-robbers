import importlib.machinery
import importlib.util
import os
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "scripts", "privacy-check")
loader = importlib.machinery.SourceFileLoader("privacy_check", SCRIPT)
spec = importlib.util.spec_from_loader("privacy_check", loader)
pc = importlib.util.module_from_spec(spec)
loader.exec_module(pc)

DENY = pc.compile_deny(["secret-host", "re:\\bcontainer-x\\d\\b"])

MUST_FLAG = [
    "ssh ops@gamebox:/games",
    "Admin@box",
    "run: ssh deploy@gamebox",
    "HOST=user@10.1.2.3",
    "ping 10.1.2.3",
    "fe80::1",
    "x 2001:4860:4860::8888 y",
    "1:2:3:4:5:6:7:8",
    "::1 2606::a",
    "see /home/bob/notes",
    "/home/alice",
    "/home/alice.smith/file",
    "C:\\Users\\bob\\file",
    "/Users/bob/x",
    "/Users/Alice",
    "/opt/game/bin",
    "/opt/Game",
    "/srv/data",
    "/srv/2box",
    "/srv/.cache/private",
    "/opt/_service/bin",
    "git clone git+ssh://user@host/repo",
    "see https://user@host/",
    "https://user:pw@example.org/x",
    "mail someone@example.org",
    "deploys to Secret-Host now",
    "restart container-x1",
]

MUST_PASS = [
    "127.0.0.1",
    "127.0.1.2",
    "0.0.0.0",
    "deploy@203.0.113.10",
    "192.0.2.7 is a documentation address",
    "2001:0db8::1",
    "2001:db8::42",
    "85369967+ReinderN@users.noreply.github.com",
    "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>",
    "Co-Authored-By: Codex <noreply@openai.com>",
    "GitHub <noreply@github.com>",
    "Signed-off-by: dependabot[bot] <support@github.com>",
    "dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>",
    "git@github.com:softbody-arcade/cops-and-robbers.git",
    "ssh://git@github.com/softbody-arcade/cops-and-robbers.git",
    "ssh://git@github.com:22#@topic",
    "https://github.com/softbody-arcade/cops-and-robbers",
    "@update:model-value",
    "uses: actions/checkout@v7",
    "uses: owner/some-action@0123456789abcdef0123456789abcdef01234567",
    '"@vue/compiler-sfc"',
    "local x = a.b:c()",
    "time 12:30:45",
    "~/.local/bin/tool",
    "<repo>/.testserver",
    "version 999.1.2.3 has a part over 255",
    "version 1.2.3.4.5",
    "a container div",
]

failures = []
checks = 0


def check(ok, message):
    global checks
    checks += 1
    if not ok:
        failures.append(message)


def unit_tests():
    for text in MUST_FLAG:
        kinds, _ = pc.findings(text, DENY)
        check(bool(kinds), f"not flagged: {text}")
    for text in MUST_PASS:
        kinds, _ = pc.findings(text, DENY)
        check(not kinds, f"wrongly flagged {kinds}: {text}")
    allow = ["docs/x.md:0.40.5.0"]
    check(not pc.findings("BeamNG 0.40.5.0", DENY, "docs/x.md", allow)[0], "allow entry did not apply to its own file")
    check(bool(pc.findings("BeamNG 0.40.5.0", DENY, "docs/y.md", allow)[0]), "allow entry applied to another file")
    check(bool(pc.findings("BeamNG 0.40.5.0 mail a@b.org", DENY, "docs/x.md", allow)[0]),
          "allow entry hid an unrelated email on the same line")
    check(bool(pc.findings("1.2.3.4", DENY, "docs/x.md", ["*:1.2.3.4"])[0]), "wildcard allow path was honoured")
    check(bool(pc.findings("C:/Users/...example", DENY, "s.sh", ["s.sh:C:/Users/..."])[0]),
          "an allow entry hid a longer value that merely starts with it")
    check(not pc.findings("print C:/Users/... rather", DENY, "s.sh", ["s.sh:C:/Users/..."])[0],
          "an exact allow entry did not apply")
    out = []
    pc.report(out, "c", "f.md", "clone https://bob:hunter2@example.org/x", DENY, [])
    check(len(out) == 1 and "hunter2" not in out[0][3] and "bob" not in out[0][3], "a URL credential was printed")
    out = []
    pc.report(out, "c", "f.md", "clone https://bob@corp:hunt@er2@example.org/x", DENY, [])
    check(len(out) == 1 and "hunt" not in out[0][3] and "er2" not in out[0][3], "a URL credential containing @ was printed")
    check(bool(pc.findings("host 10.40.5.0", DENY, "docs/x.md", ["docs/x.md:0.40.5.0"])[0]),
          "an allow entry hid part of a different IP address")
    check(not pc.findings("BeamNG 0.40.5.0", DENY, "docs/x.md", ["docs/x.md:0.40.5.0"])[0],
          "an allow entry covering a whole finding did not apply")
    out = []
    pc.report(out, "c", "f.md", "secret-host mail a@b.org", DENY, [])
    check(len(out) == 1 and "secret" not in out[0][3].lower() and "a@b.org" not in out[0][3],
          "a line with a private term was printed")
    out = []
    pc.report(out, "c", "secret-host.md", "mail a@b.org", DENY, [])
    check(len(out) == 1 and "secret" not in out[0][1].lower(), "a file name with a private term was printed")
    out = []
    pc.report(out, "c", "f.md", "secret-host and mail a@b.org", DENY, ["f.md:secret-host"])
    check(len(out) == 1 and "secret" not in out[0][3].lower(), "an allow-listed private term was printed with another finding")
    check(pc.unquote('"b/\\344\\270\\255\\"x.txt"') == 'b/\u4e2d"x.txt', "octal-escaped unicode name not decoded")
    check(pc.unquote('"b/\u4e2d\\"x.txt"') == 'b/\u4e2d"x.txt', "raw unicode name with a quote not decoded")
    try:
        pc.compile_deny(["re:(?P<leaky>"])
        check(False, "an invalid private regex was accepted")
    except pc.CheckError as e:
        check("leaky" not in str(e), "an invalid private regex leaked its text")


def git(repo, *args, check_rc=True):
    env = dict(os.environ, GIT_AUTHOR_NAME="T", GIT_AUTHOR_EMAIL="1+t@users.noreply.github.com",
               GIT_COMMITTER_NAME="T", GIT_COMMITTER_EMAIL="1+t@users.noreply.github.com",
               GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, env=env)
    if check_rc and r.returncode != 0:
        raise RuntimeError(r.stderr)
    return r.stdout


def run_check(repo, *args):
    env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
    return subprocess.run([sys.executable, "-I", SCRIPT, *args], cwd=repo, capture_output=True, text=True, env=env)


def write(repo, name, text):
    with open(os.path.join(repo, name), "w") as f:
        f.write(text)


def history_tests():
    with tempfile.TemporaryDirectory() as repo:
        git(repo, "init", "-q", "-b", "main")
        git(repo, "config", "diff.noprefix", "true")
        git(repo, "config", "commit.gpgsign", "false")
        write(repo, "a.txt", "start\n")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "-m", "start")
        write(repo, "a.txt", "start\n++ looks like a header\nmail one@example.org\n")
        git(repo, "commit", "-q", "-am", "plus-plus line")
        r = run_check(repo, "history", "--", "HEAD")
        check(r.returncode == 1 and "one@example.org" in r.stdout, "an added '++ ' line hid a later finding, or noprefix broke parsing")

        write(repo, 'we"ird name.txt', "mail two@example.org\n")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "-m", "quoted name")
        r = run_check(repo, "history", "--", "HEAD")
        check("two@example.org" in r.stdout, "a finding in a quoted filename was missed")

        git(repo, "checkout", "-q", "-b", "side")
        write(repo, "c.txt", "side\n")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "-m", "side")
        git(repo, "checkout", "-q", "main")
        write(repo, "c.txt", "main\n")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "-m", "main")
        git(repo, "merge", "-q", "side", check_rc=False)
        write(repo, "c.txt", "resolved by three@example.org\n")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "--no-edit")
        r = run_check(repo, "history", "--", "HEAD")
        check("three@example.org" in r.stdout, "a finding added while resolving a merge was missed")

        with open(os.path.join(repo, "cr.txt"), "wb") as f:
            f.write(b"one\rmail four@example.org\n")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "-m", "carriage return")
        r = run_check(repo, "history", "--", "HEAD")
        check("four@example.org" in r.stdout, "a finding after a bare carriage return was missed")

        write(repo, "\u4e2d\"q.txt", "mail five@example.org\n")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "-m", "unicode name")
        r = run_check(repo, "history", "--", "HEAD")
        check(r.returncode == 1 and "five@example.org" in r.stdout, "a unicode file name with a quote crashed or was missed")

        write(repo, "gone.txt", "mail six@example.org\n")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "-m", "add six")
        os.remove(os.path.join(repo, "gone.txt"))
        git(repo, "add", "-A")
        with open(os.path.join(repo, ".git", "MSG"), "wb") as f:
            f.write(b"no final newline")
        git(repo, "commit", "-q", "--cleanup=verbatim", "-F", os.path.join(repo, ".git", "MSG"))
        raw = git(repo, "cat-file", "commit", "HEAD")
        check(not raw.endswith("\n"), "test setup: the message still ends in a newline")
        r = run_check(repo, "history", "--", "HEAD~1..HEAD")
        check(r.returncode == 0, "a deleted line was reported after a message without a final newline")

        git(repo, "update-index", "--add", "--cacheinfo", "160000,1234567890123456789012345678901234567890,sub")
        git(repo, "commit", "-q", "-m", "submodule")
        r = run_check(repo, "tree", "HEAD")
        check(r.returncode == 1 and "five@example.org" in r.stdout, "a submodule entry broke the tree scan")

        write(repo, ".gitattributes", "nodiff.txt -diff\n")
        write(repo, "nodiff.txt", "mail seven@example.org\n")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "-m", "attributes")
        r = run_check(repo, "history", "--", "HEAD")
        check("seven@example.org" in r.stdout, "a file marked -diff hid its content from the history scan")

        deny_file = os.path.join(repo, ".git", "info", "privacy-deny")
        os.makedirs(os.path.dirname(deny_file), exist_ok=True)
        with open(deny_file, "w") as f:
            f.write("re:secretname\\.txt$\nsecrettag\n")
        write(repo, "secretname.txt", "mail eight@example.org\n")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "-m", "private name")
        git(repo, "tag", "secrettag")
        r = run_check(repo, "tree", "secrettag")
        check(r.returncode == 1 and "secret" not in r.stdout.lower() and "eight@example.org" in r.stdout,
              "tree mode printed a private file name or revision name")
        r = run_check(repo, "--bogus-secrettag", "tree", "HEAD")
        check(r.returncode == 2 and "secrettag" not in r.stderr, "an argument error echoed its input")
        os.remove(deny_file)

        r = run_check(repo, "history", "--", "no-such-rev")
        check(r.returncode == 2 and "no-such-rev" not in r.stderr, "a git failure did not exit 2 cleanly")
        r = run_check(repo, "tree", "HEAD^{tree}")
        check(r.returncode == 1, "tree mode rejected a tree object")
        os.makedirs(os.path.join(repo, "sub"), exist_ok=True)
        write(repo, "sub/x.txt", "mail nine@example.org\n")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "-m", "sub")
        r = run_check(repo, "tree", "HEAD:sub")
        check(r.returncode == 1 and "nine@example.org" in r.stdout, "tree mode rejected a path-qualified tree")
        check("sub/x.txt" in r.stdout, "tree mode reported a subtree path relative to the subtree")
        r = run_check(repo, "tree", "no-such-rev")
        check(r.returncode == 2, "a tree read failure did not exit 2")


def main():
    unit_tests()
    history_tests()
    for f in failures:
        print("FAIL", f)
    print(f"privacy-check: {checks - len(failures)} passed, {len(failures)} failed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
