"""Build the GitHub Pages download site from the repository's releases.

Reads the JSON of `gh api repos/{owner}/{repo}/releases` on stdin and writes
<out>/index.html and <out>/latest.json with the newest stable release and the
newest dev prerelease (tag dev-<n>).

Usage: python3 build_pages.py <out dir> <owner/repo> < releases.json
"""

import html
import json
import pathlib
import sys

PLATFORMS = [
    ("android.apk", "Android", "APK, signed with a debug key"),
    ("linux-x64.tar.gz", "Linux", "x64 bundle, unpack and run ./app"),
    ("ios-unsigned.ipa", "iOS", "unsigned, must be re-signed before installing"),
    ("SHA256SUMS.txt", "Checksums", "SHA-256 of all files"),
]


def pick(releases):
    published = [r for r in releases if not r["draft"]]
    published.sort(key=lambda r: r["published_at"] or "", reverse=True)
    stable = next((r for r in published if not r["prerelease"]), None)
    dev = next(
        (r for r in published if r["prerelease"] and r["tag_name"].startswith("dev-")),
        None,
    )
    return stable, dev


def summary(release):
    if release is None:
        return None
    return {
        "tag": release["tag_name"],
        "name": release["name"] or release["tag_name"],
        "url": release["html_url"],
        "published_at": release["published_at"],
        "assets": [
            {"name": a["name"], "url": a["browser_download_url"], "size": a["size"]}
            for a in release["assets"]
        ],
    }


def size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024


def section(title, kind, release):
    e = html.escape
    if release is None:
        return f'<section><h2>{e(title)}</h2><p class="none">No {e(kind)} yet.</p></section>'
    rows = []
    for suffix, label, hint in PLATFORMS:
        asset = next((a for a in release["assets"] if a["name"].endswith(suffix)), None)
        if asset:
            rows.append(
                f'<li><a href="{e(asset["url"])}"><strong>{e(label)}</strong>'
                f'<span>{e(asset["name"])} &middot; {size(asset["size"])}</span></a>'
                f'<small>{e(hint)}</small></li>'
            )
    others = [
        a for a in release["assets"] if not any(a["name"].endswith(s) for s, _, _ in PLATFORMS)
    ]
    for asset in others:
        rows.append(
            f'<li><a href="{e(asset["url"])}"><strong>{e(asset["name"])}</strong>'
            f'<span>{size(asset["size"])}</span></a></li>'
        )
    date = (release["published_at"] or "")[:10]
    return (
        f"<section><h2>{e(title)}</h2>"
        f'<p class="meta"><a href="{e(release["url"])}">{e(release["name"])}</a>'
        f" &middot; <code>{e(release['tag'])}</code> &middot; {e(date)}</p>"
        f'<ul>{"".join(rows) or "<li>No files attached.</li>"}</ul></section>'
    )


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Stonerspots Downloads</title>
<style>
:root {{ --bg: #f6f7f4; --fg: #1d2318; --muted: #5d6656; --card: #fff; --line: #dfe3d9; --accent: #3f7d20; }}
@media (prefers-color-scheme: dark) {{
  :root {{ --bg: #12150f; --fg: #e6eadf; --muted: #9aa392; --card: #1b2017; --line: #2c3326; --accent: #8fd164; }}
}}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.5 system-ui, sans-serif; }}
main {{ max-width: 720px; margin: 0 auto; padding: 40px 16px; }}
h1 {{ margin: 0 0 4px; }}
h2 {{ margin: 0 0 4px; font-size: 1.2rem; }}
a {{ color: var(--accent); }}
.lead, .meta, .none, footer {{ color: var(--muted); }}
section {{ background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 20px; margin-top: 24px; }}
ul {{ list-style: none; margin: 12px 0 0; padding: 0; }}
li {{ border-top: 1px solid var(--line); padding: 10px 0; }}
li a {{ display: flex; flex-wrap: wrap; gap: 4px 12px; align-items: baseline; text-decoration: none; }}
li span {{ color: var(--muted); font-size: .9rem; overflow-wrap: anywhere; }}
li small {{ display: block; color: var(--muted); }}
footer {{ margin-top: 32px; font-size: .9rem; }}
</style>
</head>
<body>
<main>
<h1>Stonerspots</h1>
<p class="lead">Downloads of the newest release and the newest development build.</p>
{stable}
{dev}
<footer>All releases on <a href="https://github.com/{repo}/releases">GitHub</a>.
Machine-readable: <a href="latest.json">latest.json</a>.</footer>
</main>
</body>
</html>
"""


def main():
    out = pathlib.Path(sys.argv[1])
    repo = sys.argv[2]
    stable, dev = (summary(r) for r in pick(json.load(sys.stdin)))
    out.mkdir(parents=True, exist_ok=True)
    (out / "latest.json").write_text(json.dumps({"stable": stable, "dev": dev}, indent=2))
    (out / "index.html").write_text(
        PAGE.format(
            stable=section("Latest release", "release", stable),
            dev=section("Latest dev build", "dev build", dev),
            repo=html.escape(repo),
        )
    )


if __name__ == "__main__":
    main()
