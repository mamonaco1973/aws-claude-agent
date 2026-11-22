#!/usr/bin/env python3
"""Generate the README architecture diagram, one SVG per colour scheme.

Two files rather than one self-switching file: GitHub strips <style> blocks
from inline SVG, so a `prefers-color-scheme` media query inside the document is
silently dropped. The README pairs them with <picture>, which GitHub honours.

A README diagram is studied, not narrated, so it is COMPLETE rather than
minimal: the work queue, the NAT path the long-poll takes, the image
registry, the secret, the logs, the report bucket and the one-shot seed
loader are all on it.

Every arrow points FROM the side that opens the connection. That is the
point of the lab: every arrow that touches the VPC boundary points out of
it. The seed loader is drawn DASHED because it runs once and powers off.

Run:  python3 make_diagram.py
"""

import os

HERE = os.path.dirname(os.path.abspath(__file__))

# ------------------------------------------------------------------------------
# Geometry and style (shared with the other projects' diagrams)
# ------------------------------------------------------------------------------
NW, NH = 420, 110                          # node width, height
GUTTER = 140                               # between columns: room for a label
MARGIN = 40
COL = [MARGIN + i * (NW + GUTTER) for i in range(4)]
ROW = [60, 300, 500, 700]
W = MARGIN * 2 + NW * 4 + GUTTER * 3
H = ROW[3] + NH + 70
TITLE_PX, SUB_PX, EDGE_PX, GROUP_PX = 26, 17, 16, 18

THEMES = {
    "dark": {
        "bg": "#0d1117", "panel": "#161b22", "text": "#e6edf3",
        "muted": "#8b949e", "line": "#58a6ff", "local": "#39c5bb",
        "purple": "#c39be8", "navy": "#c8d6e8", "blue": "#58a6ff",
        "amber": "#f2c163", "store": "#7ee787",
    },
    "light": {
        "bg": "#ffffff", "panel": "#f6f8fa", "text": "#1f2328",
        "muted": "#59636e", "line": "#0969da", "local": "#137e77",
        "purple": "#8250df", "navy": "#475467", "blue": "#0969da",
        "amber": "#9a6700", "store": "#1a7f37",
    },
}

# Lucide icon paths, on a 24-unit grid.
ICONS = {
    "globe": ['<circle cx="12" cy="12" r="10"/>',
              '<path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/>',
              '<path d="M2 12h20"/>'],
    "route": ['<circle cx="6" cy="19" r="3"/>', '<circle cx="18" cy="5" r="3"/>',
              '<path d="M12 19h4.5a3.5 3.5 0 0 0 0-7h-8a3.5 3.5 0 0 1 0-7H12"/>'],
    "network": ['<rect x="16" y="16" width="6" height="6" rx="1"/>',
                '<rect x="2" y="16" width="6" height="6" rx="1"/>',
                '<rect x="9" y="2" width="6" height="6" rx="1"/>',
                '<path d="M5 16v-3a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v3"/>',
                '<path d="M12 12V8"/>'],
    "layers": ['<path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83'
               'l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/>',
               '<path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/>',
               '<path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/>'],
    "database": ['<ellipse cx="12" cy="5" rx="9" ry="3"/>',
                 '<path d="M3 5V19A9 3 0 0 0 21 19V5"/>',
                 '<path d="M3 12A9 3 0 0 0 21 12"/>'],
    "key": ['<path d="M2.586 17.414A2 2 0 0 0 2 18.828V21a1 1 0 0 0 1 1h3a1 1 0 0 0 '
            '1-1v-1a1 1 0 0 1 1-1h1a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h.172a2 2 0 0 0 '
            '1.414-.586l.814-.814a6.5 6.5 0 1 0-4-4z"/>',
            '<circle cx="16.5" cy="7.5" r=".5"/>'],
    "monitor": ['<rect width="20" height="14" x="2" y="3" rx="2"/>',
                '<line x1="8" x2="16" y1="21" y2="21"/>',
                '<line x1="12" x2="12" y1="17" y2="21"/>'],
    "terminal": ['<polyline points="4 17 10 11 4 5"/>',
                 '<line x1="12" x2="20" y1="19" y2="19"/>'],
    "users": ['<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/>',
              '<circle cx="9" cy="7" r="4"/>',
              '<path d="M22 21v-2a4 4 0 0 0-3-3.87"/>',
              '<path d="M16 3.13a4 4 0 0 1 0 7.75"/>'],
    "bot": ['<path d="M12 8V4H8"/>',
            '<rect width="16" height="12" x="4" y="8" rx="2"/>',
            '<path d="M2 14h2"/>', '<path d="M20 14h2"/>',
            '<path d="M15 13v2"/>', '<path d="M9 13v2"/>'],
    "inbox": ['<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/>',
              '<path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6'
              'l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>'],
    "box": ['<path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 '
            '3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/>',
            '<path d="m3.3 7 8.7 5 8.7-5"/>', '<path d="M12 22V12"/>'],
    "file": ['<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 '
             '2-2V7Z"/>', '<path d="M14 2v4a2 2 0 0 0 2 2h4"/>',
             '<path d="M16 13H8"/>', '<path d="M16 17H8"/>',
             '<path d="M10 9H8"/>'],
    "list": ['<path d="M3 6h.01"/>', '<path d="M3 12h.01"/>',
             '<path d="M3 18h.01"/>', '<path d="M8 6h13"/>',
             '<path d="M8 12h13"/>', '<path d="M8 18h13"/>'],
}

NODES = {}


def _r(nid):
    """Return (left, top, right, bottom, centre-x, centre-y) for a node."""
    x, y = NODES[nid][0], NODES[nid][1]
    return x, y, x + NW, y + NH, x + NW / 2, y + NH / 2


def gutter_x(c):
    """Centre of the gutter to the right of column c."""
    return COL[c] + NW + GUTTER / 2


def gutter_y(r):
    """Centre of the gap below row r."""
    return ROW[r] + NH + (ROW[r + 1] - ROW[r] - NH) / 2


# ------------------------------------------------------------------------------
# Layout
# ------------------------------------------------------------------------------
# Top band: Anthropic (work queue and agent loop) and the build server that
# drives the control plane. Middle: the VPC, with the NAT gateway directly
# under the queue so the outbound long-poll is one straight vertical line.
# Left column: the regional AWS services ECS reads at task start and the
# log group it writes to. Right: the report bucket.
#
# id: (x, y, colour key, icon, title, subtitle[, "dashed"])
NODES.update({
    "queue":   (COL[1], ROW[0], "amber", "inbox", "Work queue",
                "self-hosted environment"),
    "loop":    (COL[2], ROW[0], "purple", "bot", "Agent loop + schedule",
                "claude-haiku-5-5, cron 0 6 * * * UTC"),
    "build":   (COL[3], ROW[0], "navy", "monitor", "Build server",
                "ant apply, run-now.sh, API key"),
    "ecr":     (COL[0], ROW[1], "navy", "box", "Amazon ECR",
                "claude-agent-worker image"),
    "nat":     (COL[1], ROW[1], "local", "route", "NAT gateway",
                "public subnet, the only way out"),
    "secrets": (COL[0], ROW[2], "store", "key", "Secrets Manager",
                "environment ID + environment key"),
    "worker":  (COL[1], ROW[2], "blue", "terminal", "Fargate worker",
                "no public IP, zero ingress rules"),
    "s3":      (COL[3], ROW[2], "store", "file", "S3 report bucket",
                "reports/YYYY-MM-DD.md, versioned"),
    "logs":    (COL[0], ROW[3], "navy", "list", "CloudWatch Logs",
                "/ecs/claude-agent-worker"),
    "rds":     (COL[1], ROW[3], "purple", "database", "RDS PostgreSQL 17",
                "private, IAM auth, role agent_ro"),
    "loader":  (COL[2], ROW[3], "amber", "monitor", "Seed loader",
                "loads Pagila once, powers off", "dashed"),
})

# Dashed boundary boxes drawn behind the nodes.
# (x, y, w, h, label)
PAD = 25
GROUPS = [
    (COL[1] - PAD, ROW[0] - 45, COL[2] + NW - COL[1] + 2 * PAD, NH + 45 + PAD,
     "Anthropic"),
    (COL[1] - PAD, ROW[1] - 45, COL[2] + NW - COL[1] + 2 * PAD,
     ROW[3] + NH + PAD - ROW[1] + 45,
     "Your VPC: private subnets, nothing inbound"),
]

q, lp, bs = _r("queue"), _r("loop"), _r("build")
ecr, nat, sec, wk = _r("ecr"), _r("nat"), _r("secrets"), _r("worker")
s3, lg, db, ld = _r("s3"), _r("logs"), _r("rds"), _r("loader")
SPLIT = 35                    # the three lines meeting the worker's left side

# ECS pulls the image and reads the key from inside the task, so those
# arrows point outward too.
# id: (path, colour key, label, label_x, label_y, anchor[, "dashed"])
EDGES = {
    "e_ctl":   (f"M{bs[0]},{bs[5]} H{lp[2] + 5}", "navy",
                "HTTPS", gutter_x(2), bs[5] - 12, "middle"),
    "e_work":  (f"M{lp[0]},{lp[5]} H{q[2] + 5}", "amber",
                "sessions", gutter_x(1), lp[5] - 12, "middle"),
    "e_poll":  (f"M{wk[4]},{wk[1]} V{nat[3] + 5}", "blue",
                "443 out: long-poll", wk[4] + 14, gutter_y(1) + 6, "start"),
    "e_nat":   (f"M{nat[4]},{nat[1]} V{q[3] + 5}", "blue",
                "HTTPS to Anthropic", nat[4] + 14, q[3] + PAD + 32, "start"),
    "e_img":   (f"M{wk[0]},{wk[5] - SPLIT} H{gutter_x(0)} V{ecr[5]} "
                f"H{ecr[2] + 5}", "navy",
                "pull image", gutter_x(0), ecr[5] - 12, "middle"),
    "e_sec":   (f"M{wk[0]},{wk[5]} H{sec[2] + 5}", "store",
                "read key", gutter_x(0), sec[5] + 24, "middle"),
    "e_log":   (f"M{wk[0]},{wk[5] + SPLIT} H{gutter_x(0)} V{lg[5]} "
                f"H{lg[2] + 5}", "navy",
                "logs", gutter_x(0) - 12, gutter_y(2) + 6, "end"),
    "e_pg":    (f"M{wk[4]},{wk[3]} V{db[1] - 5}", "purple",
                "5432, IAM token", wk[4] + 14, gutter_y(2) + 6, "start"),
    "e_put":   (f"M{wk[2]},{wk[5]} H{s3[0] - 5}", "store",
                "s3:PutObject reports/*", COL[2] + NW / 2, wk[5] - 12,
                "middle"),
    "e_seed":  (f"M{ld[0]},{ld[5]} H{db[2] + 5}", "amber",
                "5432, once", gutter_x(1), ld[5] - 12, "middle", "dashed"),
    "e_get":   (f"M{ld[2]},{ld[5]} H{s3[4]} V{s3[3] + 5}", "amber",
                "seed/ download", s3[4] + 14, gutter_y(2) + 6, "start",
                "dashed"),
}

ALT = ("A Fargate worker in a private subnet of your VPC opens an outbound "
       "HTTPS long-poll through the NAT gateway to the Managed Agents work "
       "queue at Anthropic, where the agent loop and its 06:00 UTC schedule "
       "run; the build server drives that control plane with an API key. At "
       "start ECS pulls the worker image from ECR and injects the environment "
       "key from Secrets Manager, both from inside the task; the worker writes logs to CloudWatch. The "
       "agent's tool calls run in the worker: psql to a private RDS "
       "PostgreSQL 17 database on port 5432 with an IAM auth token, and "
       "s3:PutObject of the report to an S3 bucket. A seed loader host, run "
       "once, downloads the Pagila data from S3 and loads it into the "
       "database. No arrow enters the VPC.")

# ------------------------------------------------------------------------------
# Rendering
# ------------------------------------------------------------------------------
FONT = "-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif"


def node_svg(nid, t):
    """Render one service box: rounded panel, icon, title, subtitle."""
    x, y, key, icon, title, sub, *opt = NODES[nid]
    colour = t[key]
    dash = ' stroke-dasharray="10 7"' if opt and opt[0] == "dashed" else ""
    scale = 1.25
    isz = 24 * scale
    ix, iy = x + 20, y + (NH - isz) / 2
    tx = x + 20 + isz + 14
    return "".join([
        f'<rect x="{x}" y="{y}" width="{NW}" height="{NH}" rx="10" ry="10" '
        f'fill="{t["panel"]}" stroke="{colour}" stroke-width="2"{dash}/>',
        f'<g transform="translate({ix},{iy}) scale({scale})" fill="none" '
        f'stroke="{colour}" stroke-width="2" stroke-linecap="round" '
        f'stroke-linejoin="round">' + "".join(ICONS[icon]) + "</g>",
        f'<text x="{tx}" y="{y + NH/2 - 4}" font-family="{FONT}" '
        f'font-size="{TITLE_PX}" font-weight="600" fill="{t["text"]}">{title}</text>',
        f'<text x="{tx}" y="{y + NH/2 + 22}" font-family="{FONT}" '
        f'font-size="{SUB_PX}" fill="{t["muted"]}">{sub}</text>',
    ])


def edge_svg(eid, t):
    """Render one arrow plus its label (on a background chip, so lines that
    pass behind a label never cut through its text)."""
    d, key, label, lx, ly, anchor, *opt = EDGES[eid]
    colour = t[key]
    dash = ' stroke-dasharray="8 6"' if opt and opt[0] == "dashed" else ""
    out = (f'<path d="{d}" fill="none" stroke="{colour}" stroke-width="2"{dash} '
           f'marker-end="url(#a_{eid})"/>')
    if label:
        out += (f'<text x="{lx}" y="{ly}" text-anchor="{anchor}" '
                f'font-family="{FONT}" font-size="{EDGE_PX}" font-weight="600" '
                f'fill="{colour}" stroke="{t["bg"]}" stroke-width="6" '
                f'paint-order="stroke">{label}</text>')
    return out


def build(t):
    """Assemble the diagram for one theme."""
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
           f'viewBox="0 0 {W} {H}" role="img" aria-label="{ALT}">', "<defs>"]
    # One marker per edge: a shared marker cannot carry per-edge colour.
    for eid, spec in EDGES.items():
        out.append(
            f'<marker id="a_{eid}" viewBox="0 0 10 10" refX="9" refY="5" '
            f'markerWidth="5" markerHeight="5" orient="auto-start-reverse">'
            f'<path d="M0,0 L10,5 L0,10 z" fill="{t[spec[1]]}"/></marker>')
    out.append("</defs>")
    out.append(f'<rect width="{W}" height="{H}" fill="{t["bg"]}"/>')
    for gx, gy, gw, gh, glabel in GROUPS:
        out.append(
            f'<rect x="{gx}" y="{gy}" width="{gw}" height="{gh}" rx="14" '
            f'fill="none" stroke="{t["muted"]}" stroke-width="2" '
            f'stroke-dasharray="6 6"/>'
            f'<text x="{gx + gw - 16}" y="{gy + 28}" text-anchor="end" '
            f'font-family="{FONT}" '
            f'font-size="{GROUP_PX}" font-weight="600" fill="{t["muted"]}">'
            f'{glabel}</text>')
    for eid in EDGES:
        out.append(edge_svg(eid, t))
    for nid in NODES:
        out.append(node_svg(nid, t))
    out.append("</svg>")
    return "".join(out)


def main():
    for name, theme in THEMES.items():
        path = os.path.join(HERE, f"architecture-{name}.svg")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(build(theme))
        print(f"  architecture-{name}.svg")


if __name__ == "__main__":
    main()
