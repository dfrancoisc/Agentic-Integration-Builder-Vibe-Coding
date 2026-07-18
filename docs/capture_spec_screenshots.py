"""Capture screenshots of the InterSystems Integration Spec Questionnaire.

Saves PNGs to docs/img/ for the README. Same approach as
capture_screenshots.py: playwright against the IRIS container on 22773,
dark colour scheme, dev credentials from the container.

The questionnaire normally inherits the Interop Editor's JWT. Opened
standalone there is no parent to bridge from, so we seed the chat's
localStorage credential (AGENTIC_AUTH) before load -- that is the same
fallback the page uses in standalone mode.

Screenshots captured:
  30_spec_questionnaire   landing state, all sections collapsed
  31_spec_describe        description filled, ready to extract
  32_spec_filled          form populated, fields marked "verify"
  33_spec_catalog_picker  catalog picker filtered to MLLP
  34_spec_output_trial    generated specification preview
"""
import base64
import os
import time

from playwright.sync_api import sync_playwright

BASE = "http://localhost:22773"
USER = "_SYSTEM"
PASS = "Agentic1!"
AUTH_HEADER = "Basic " + base64.b64encode(f"{USER}:{PASS}".encode()).decode()

IMG_DIR = os.path.join(os.path.dirname(__file__), "img")
os.makedirs(IMG_DIR, exist_ok=True)

VIEWPORT = {"width": 1600, "height": 950}

SPEC = f"{BASE}/agentic/spec/index.html?ns=HSCUSTOM"

DESCRIPTION = (
    "Receive HL7 v2.5 ADT^A01 admission messages from the HIS over MLLP on port 5000. "
    "Strip the dashes out of the SSN in PID:19 and set the sending application MSH:3 to EPIC. "
    "Transform to ORU^R01 and send to the LIS at 10.1.4.22:6000 over MLLP. "
    "Anything that fails goes to /data/hl7/deadletter/."
)

# A real extraction response, so the captures show genuine output without
# spending an LLM call (and without a 20s wait) on every doc rebuild.
EXTRACTION = """{
  "answers": {
    "name": "HIS admissions to LIS",
    "shortName": "ADTLIS",
    "purpose": "Route ADT admissions from the HIS to the LIS as ORU observation reports.",
    "srcSystem": "HIS", "srcStandard": "hl7v2", "srcHl7Version": "2.5",
    "srcMsgTypes": ["ADT_A01"], "srcTransport": "tcp", "srcPort": 5000,
    "production": "USER.Productions.ADTLIS",
    "deadLetter": "/data/hl7/deadletter/"
  },
  "repeats": {
    "targets": [{"name": "LIS", "standard": "hl7v2", "msgType": "ORU_R01",
                 "transport": "tcp", "endpoint": "10.1.4.22:6000", "transform": "yes"}],
    "mappings": [
      {"action": "copy-field", "source": "PID:19", "target": "PID:19",
       "value": "Strip the dashes out of the SSN"},
      {"action": "set", "target": "MSH:3", "value": "EPIC"}
    ]
  },
  "notes": ["The archive directory for the inbound feed was not stated."]
}"""


def shot(page, name, wait=1.0):
    time.sleep(wait)
    path = os.path.join(IMG_DIR, f"{name}.png")
    page.screenshot(path=path, full_page=False)
    print(f"  saved {name}.png")


def stub_extraction(page):
    """Serve the canned extraction for POST /api/agentic/chat."""
    def handler(route):
        route.fulfill(status=200, content_type="application/json",
                      body='{"ok":1,"response":' + _json_str(EXTRACTION) + '}')
    page.route("**/api/agentic/chat*", handler)


def _json_str(s):
    import json
    return json.dumps(s)


def main():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        ctx = browser.new_context(viewport=VIEWPORT, color_scheme="dark",
                                  extra_http_headers={"Authorization": AUTH_HEADER})
        page = ctx.new_page()

        # standalone fallback credential (same key the chat uses)
        ctx.add_init_script(
            f"try {{ localStorage.setItem('AGENTIC_AUTH', {_json_str(AUTH_HEADER)}); }} catch (e) {{}}"
        )

        # ---- 30. landing state: every section collapsed ----
        page.goto(SPEC, wait_until="networkidle")
        time.sleep(2)
        shot(page, "30_spec_questionnaire")

        # ---- 31. description typed, ready to extract ----
        page.fill("#seed-text", DESCRIPTION)
        shot(page, "31_spec_describe")

        # ---- 32. form populated from the description ----
        stub_extraction(page)
        page.click("#seed-go")
        page.wait_for_function(
            "() => { const s = document.getElementById('seed-status');"
            " return s && !s.hidden && !s.querySelector('.spinner'); }",
            timeout=15000)
        # open the source section so the verify markers are visible
        page.evaluate("document.querySelector('#sec-source .section-head').click()")
        time.sleep(0.6)
        page.evaluate("document.getElementById('sec-source').scrollIntoView({block:'start'})")
        shot(page, "32_spec_filled")

        # ---- 33. catalog picker, filtered ----
        page.evaluate(
            "document.querySelector('.field[data-qid=\"srcHostClass\"] .cat-field .btn').click()")
        page.wait_for_selector(".cp-item", timeout=15000)
        page.fill("#cp-q", "MLLP")
        time.sleep(0.8)
        shot(page, "33_spec_catalog_picker")
        page.evaluate("document.getElementById('cp-cancel').click()")
        time.sleep(0.4)

        # ---- 34. generated specification ----
        page.evaluate("document.getElementById('btn-trial').click()")
        page.wait_for_selector("#preview:not([hidden])", timeout=8000)
        time.sleep(0.8)
        shot(page, "34_spec_output_trial")

        browser.close()
        print("done")


if __name__ == "__main__":
    main()
