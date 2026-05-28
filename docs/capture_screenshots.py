"""Capture screenshots of the agentic_interop admin UI and chatbot.

Saves PNGs to docs/img/ for embedding in the .docx documents.
Uses playwright against the IRIS container on port 22773.
Handles the login overlay by filling credentials.
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

VIEWPORT = {"width": 1440, "height": 900}


def shot(page, name, wait=1.5):
    time.sleep(wait)
    path = os.path.join(IMG_DIR, f"{name}.png")
    page.screenshot(path=path, full_page=False)
    print(f"  saved {name}.png")


def do_login(page):
    """Fill the login overlay if present."""
    try:
        page.wait_for_selector("#agentic-login-overlay", timeout=5000)
        page.fill("#agentic-login-user", USER)
        page.fill("#agentic-login-pass", PASS)
        page.click('#agentic-login-form button[type="submit"]')
        # Wait for overlay to disappear
        page.wait_for_selector("#agentic-login-overlay", state="detached", timeout=10000)
        time.sleep(1)
        print("  logged in")
    except Exception:
        print("  no login overlay (already authenticated)")


def click_tab(page, index):
    """Click a nav tab by index."""
    page.evaluate(f"document.querySelectorAll('nav button')[{index}].click()")
    time.sleep(1.5)


def click_first_item(page):
    """Click the first .list-item in the list panel."""
    page.evaluate("""(() => {
        var items = document.querySelectorAll('.list-item');
        if (items.length > 0) items[0].click();
    })()""")
    time.sleep(1.5)


def main():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        ctx = browser.new_context(
            viewport=VIEWPORT,
            color_scheme="dark",
        )
        page = ctx.new_page()

        # ---- Admin UI ----
        admin = f"{BASE}/agentic/admin/index.html"
        page.goto(admin, wait_until="networkidle")
        time.sleep(2)

        # Handle login
        do_login(page)
        time.sleep(2)

        # 1. Agents list
        shot(page, "01_agents_list")

        # 2. Agent detail
        click_first_item(page)
        shot(page, "02_agent_detail")

        # 3. MCPs tab
        click_tab(page, 1)
        shot(page, "03_mcps_list")

        # 4. ToolSets tab
        click_tab(page, 2)
        shot(page, "04_toolsets_list")

        # 5. Tools tab
        click_tab(page, 3)
        shot(page, "05_tools_list")

        # 6. Tool detail
        click_first_item(page)
        shot(page, "06_tool_detail")

        # 7. Skills tab
        click_tab(page, 4)
        shot(page, "07_skills_list")

        # 8. Skill detail
        click_first_item(page)
        shot(page, "08_skill_detail")

        # 9. Connections tab
        click_tab(page, 5)
        shot(page, "09_connections_list")

        # 10. Connection detail
        click_first_item(page)
        shot(page, "10_connection_detail")

        # 11. Catalogs tab
        click_tab(page, 6)
        shot(page, "11_catalogs")

        # 12. Transforms tab (empty)
        click_tab(page, 7)
        shot(page, "12_transforms_empty")

        # 13. Transforms with HL7 v2 -> FHIR R4.
        # The selector IDs changed when the Transforms tab was redesigned.
        # Try the new IDs first; fall back to the old ones; if neither
        # works, skip this shot (don't block the rest of the capture).
        try:
            for src_sel, tgt_sel in (
                ("#tf-sel-src", "#tf-sel-tgt"),
                ("#tf-source", "#tf-target"),
                ("select[name='source']", "select[name='target']"),
            ):
                if page.locator(src_sel).count() > 0 and page.locator(tgt_sel).count() > 0:
                    page.select_option(src_sel, "HL7 v2")
                    page.select_option(tgt_sel, "FHIR R4")
                    shot(page, "13_transforms_hl7_fhir", wait=2.5)
                    break
            else:
                print("  WARN: skipping 13_transforms_hl7_fhir — Transforms tab selectors not found (UI changed)")
        except Exception as e:
            print(f"  WARN: skipping 13_transforms_hl7_fhir — {e}")

        # 14. Audit tab
        click_tab(page, 8)
        shot(page, "14_audit")

        # ---- Chatbot ----
        page.goto(f"{BASE}/agentic/chat/index.html", wait_until="networkidle")
        time.sleep(2)
        do_login(page)
        time.sleep(2)
        shot(page, "15_chatbot", wait=2)

        browser.close()
        count = len([f for f in os.listdir(IMG_DIR) if f.endswith(".png")])
        print(f"\nDone. {count} screenshots in {IMG_DIR}")


if __name__ == "__main__":
    main()
