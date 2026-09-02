#!/usr/bin/env python3
"""Every auth mail from one frame — the gate's own look: carbon ground, one lime pip,
a Doto label, one highlight per screen. Run it after editing and the five files are rewritten.

No invite: the app has no invite flow, and Supabase only sends that mail when someone presses
"Invite user" in the dashboard — which nobody should.

    python3 supabase/templates/build.py
"""
from pathlib import Path

HERE = Path(__file__).parent

# Tokens.swift — the same hexes the app draws with.
CARBON, CARD, HAIRLINE = "#0B0B0D", "#101014", "#1F1F24"   # hairline = 8% white on carbon, flattened
LIME, WHITE = "#EFF65A", "#FFFFFF"
TEXT2, TEXT3 = "#9B9BA1", "#8E8E95"                          # 60% / 55% white on carbon, flattened
UI = "'Jost', 'Helvetica Neue', Helvetica, Arial, sans-serif"
BRAND = "'Inter Tight', 'Helvetica Neue', Helvetica, Arial, sans-serif"
DOT = "'Doto', Menlo, Consolas, 'Courier New', monospace"

FRAME = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>{subject}</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Doto:wght@600;700&family=Inter+Tight:wght@800&family=Jost:wght@300;400;500&display=swap');
  :root {{ color-scheme: light dark; supported-color-schemes: light dark; }}
  body {{ margin:0; padding:0; background-color:{carbon}; -webkit-text-size-adjust:100%; }}
  a {{ color:{lime}; text-decoration:none; }}
  /* Dark-mode clients invert a mail to "make it dark". This one already is: pin every colour. */
  @media (prefers-color-scheme: dark) {{
    body, .nb-ground {{ background-color:{carbon} !important; background-image:linear-gradient({carbon},{carbon}) !important; }}
    .nb-card {{ background-color:{card} !important; background-image:linear-gradient({card},{card}) !important; border-color:{hairline} !important; }}
    .nb-code {{ background-color:{carbon} !important; background-image:linear-gradient({carbon},{carbon}) !important; color:{white} !important; }}
    .nb-white {{ color:{white} !important; }}
    .nb-text2 {{ color:{text2} !important; }}
    .nb-text3 {{ color:{text3} !important; }}
    .nb-pip {{ background-color:{lime} !important; background-image:linear-gradient({lime},{lime}) !important; }}
  }}
  [data-ogsc] .nb-white {{ color:{white} !important; }}
  [data-ogsc] .nb-text2 {{ color:{text2} !important; }}
  [data-ogsb] .nb-ground, [data-ogsb] .nb-code {{ background-color:{carbon} !important; }}
  [data-ogsb] .nb-card {{ background-color:{card} !important; }}
</style>
</head>
<body class="nb-ground" bgcolor="{carbon}" style="margin:0;padding:0;background-color:{carbon};background-image:linear-gradient({carbon},{carbon});">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="{carbon}" class="nb-ground" style="background-color:{carbon};background-image:linear-gradient({carbon},{carbon});">
  <tr><td align="center" bgcolor="{carbon}" class="nb-ground" style="background-color:{carbon};background-image:linear-gradient({carbon},{carbon});padding:40px 20px 48px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:390px;">

      <!-- wordmark · the gate's own -->
      <tr><td style="padding:0 0 26px;">
        <span class="nb-white" style="font-family:{brand};font-size:26px;font-weight:800;letter-spacing:-0.045em;color:{white};line-height:1;">NEXTBODY</span><span class="nb-pip" style="display:inline-block;vertical-align:top;width:7px;height:7px;background-color:{lime};background-image:linear-gradient({lime},{lime});border-radius:2px;margin:3px 0 0 7px;line-height:7px;font-size:0;">&nbsp;</span>
      </td></tr>

      <!-- card -->
      <tr><td bgcolor="{card}" class="nb-card" style="background-color:{card};background-image:linear-gradient({card},{card});border:1px solid {hairline};border-radius:18px;padding:26px 24px 24px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
          <tr><td class="nb-text3" style="font-family:{dot};font-size:11px;font-weight:600;letter-spacing:0.26em;color:{text3};padding:0 0 18px;">{label}</td></tr>
          <tr><td class="nb-white" style="font-family:{ui};font-size:21px;font-weight:300;letter-spacing:0.02em;color:{white};line-height:1.3;padding:0 0 8px;">{headline}</td></tr>
          <tr><td class="nb-text2" style="font-family:{ui};font-size:14px;font-weight:400;color:{text2};line-height:1.5;padding:0 0 22px;">{lede}</td></tr>
          {highlight}
          <tr><td class="nb-text2" style="font-family:{ui};font-size:13px;font-weight:400;color:{text2};line-height:1.5;padding:18px 0 0;border-top:1px solid {hairline};">{note}</td></tr>
        </table>
      </td></tr>

      <!-- footer -->
      <tr><td class="nb-text3" style="font-family:{dot};font-size:10px;font-weight:600;letter-spacing:0.24em;color:{text3};padding:22px 0 0;">TRAIN · RECOVER · REPEAT</td></tr>
      <tr><td class="nb-text3" style="font-family:{ui};font-size:12px;color:{text3};line-height:1.5;padding:8px 0 0;">{footer}</td></tr>
    </table>
  </td></tr>
</table>
</body>
</html>
"""

def code(token: str) -> str:
    """The highlight: six digits, big, tracked — the one bright thing on the screen."""
    return (f'<tr><td align="center" bgcolor="{CARBON}" class="nb-code" style="background-color:{CARBON};background-image:linear-gradient({CARBON},{CARBON});border:1px solid {HAIRLINE};border-radius:14px;padding:22px 12px;">'
            f'<span class="nb-white" style="font-family:{DOT};font-size:38px;font-weight:700;letter-spacing:0.26em;color:{WHITE};line-height:1;">{token}</span>'
            f'</td></tr>')

IGNORE = "If you didn't ask for this, ignore it. Nobody can get in without the code."
TEN = "It works once and expires in 10 minutes."

MAILS = {
    # The gate · 01. A first-time address and a returning one get the same mail.
    "magic_link": dict(
        subject="Your NEXTBODY code",
        label="SIGN IN · 6-DIGIT CODE",
        headline="Enter the code.",
        lede="Type these six digits into the app. No password to set.",
        highlight=code("{{ .Token }}"),
        note=TEN,
        footer=IGNORE),
    "confirmation": dict(
        subject="Your NEXTBODY code",
        label="SIGN IN · 6-DIGIT CODE",
        headline="Enter the code.",
        lede="Type these six digits into the app. No password to set.",
        highlight=code("{{ .Token }}"),
        note=TEN,
        footer=IGNORE),
    # 11 · Profile. A change of address is confirmed by code, at the new address.
    "email_change": dict(
        subject="Confirm your new email",
        label="EMAIL CHANGE · 6-DIGIT CODE",
        headline="Confirm the change.",
        lede="Your NEXTBODY account is moving from {{ .Email }} to {{ .NewEmail }}. Enter this code to confirm.",
        highlight=code("{{ .Token }}"),
        note=TEN,
        footer="If you didn't ask for this, ignore it and the address stays as it was."),
    # 01 rule 05 · there is no password, so this mail should never leave — styled all the same.
    "recovery": dict(
        subject="Your NEXTBODY code",
        label="ACCOUNT · 6-DIGIT CODE",
        headline="Enter the code.",
        lede="Type these six digits into the app to get back in.",
        highlight=code("{{ .Token }}"),
        note=TEN,
        footer=IGNORE),
    "reauthentication": dict(
        subject="Confirm it's you",
        label="CONFIRM · 6-DIGIT CODE",
        headline="Confirm it's you.",
        lede="A change to your account needs a second look. Enter this code in the app.",
        highlight=code("{{ .Token }}"),
        note=TEN,
        footer=IGNORE),
}

if __name__ == "__main__":
    for name, m in MAILS.items():
        html = FRAME.format(carbon=CARBON, card=CARD, hairline=HAIRLINE, lime=LIME, white=WHITE,
                            text2=TEXT2, text3=TEXT3, ui=UI, brand=BRAND, dot=DOT, **m)
        (HERE / f"{name}.html").write_text(html)
        print(f"{name:18s} {m['subject']}")
