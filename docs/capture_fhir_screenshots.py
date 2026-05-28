"""Capture FHIR Assistant-specific screenshots for the FHIR docs.

Saves PNGs to docs/img/ numbered 20-26 to avoid collision with the
generic capture_screenshots.py inventory (01-18).

Captures:
  20_fhir_management.png       — shipped FHIR Server Management page (/csp/fhir-management)
                                  with the injected FHIR Assistant launcher button
  21_fhir_chatbot.png          — FHIR Assistant chatbot full screen
                                  (/agentic/chat/index.html?chatbot=fhir-management)
  22_admin_chatbots.png        — admin UI Chatbots tab showing both shipped chatbot
                                  rows (interop, fhir-management)
  23_admin_agent_fhir.png      — admin UI Agents tab with FHIRSpecialist selected
  24_admin_mcp_fhirserver.png  — admin UI MCPs tab with MCP.FHIRServer selected
  25_admin_tool_fhirserver.png — admin UI Tools tab showing Tool.FHIRServer

Requires the iris-agentic container running on localhost:22773.
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
    """Fill the agentic chatbot login overlay if present."""
    try:
        page.wait_for_selector("#agentic-login-overlay", timeout=5000)
        page.fill("#agentic-login-user", USER)
        page.fill("#agentic-login-pass", PASS)
        page.click('#agentic-login-form button[type="submit"]')
        page.wait_for_selector("#agentic-login-overlay", state="detached", timeout=10000)
        time.sleep(1)
        print("  logged in")
    except Exception:
        print("  no login overlay")


def click_nav_button(page, data_tab):
    """Click an admin UI nav tab by its data-tab attribute (e.g. agents, mcps, chatbots)."""
    sel = f'#tabs button[data-tab="{data_tab}"]'
    btn = page.locator(sel)
    if btn.count() > 0:
        btn.first.click()
        time.sleep(1.5)
        return True
    return False


def click_list_item(page, css, text):
    """Click a list item by text inside a container."""
    items = page.locator(css)
    for i in range(items.count()):
        if text.lower() in items.nth(i).inner_text().lower():
            items.nth(i).click()
            time.sleep(1.0)
            return True
    return False


def main():
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=True)
        # For /csp/fhir-management we need the Authorization header (shipped IRIS
        # UI is not behind the agentic login overlay). For /agentic/admin and
        # /agentic/chat we rely on the login overlay so the agentic JWT flow
        # initializes correctly — matches docs/capture_screenshots.py.

        # 20 — FHIR Management page (Auth header context)
        ctx_fhir = browser.new_context(
            viewport=VIEWPORT,
            extra_http_headers={"Authorization": AUTH_HEADER},
        )
        page = ctx_fhir.new_page()
        try:
            page.goto(f"{BASE}/csp/fhir-management/", wait_until="domcontentloaded")
            time.sleep(3)
            shot(page, "20_fhir_management", wait=2)
        except Exception as e:
            print(f"  WARN: 20_fhir_management failed — {e}")
        ctx_fhir.close()

        # 21-25 — agentic UI: login-overlay context, no auth header
        ctx = browser.new_context(viewport=VIEWPORT, color_scheme="dark")
        page = ctx.new_page()

        # 21 — FHIR Assistant chatbot full screen
        try:
            page.goto(f"{BASE}/agentic/chat/index.html?chatbot=fhir-management",
                      wait_until="networkidle")
            time.sleep(2)
            do_login(page)
            time.sleep(2)
            shot(page, "21_fhir_chatbot", wait=2)
        except Exception as e:
            print(f"  WARN: 21_fhir_chatbot failed — {e}")

        # 22 — Admin Chatbots tab (shows both interop + fhir-management rows)
        try:
            page.goto(f"{BASE}/agentic/admin/index.html", wait_until="networkidle")
            time.sleep(2)
            do_login(page)
            time.sleep(2)
            if click_nav_button(page, "chatbots"):
                shot(page, "22_admin_chatbots", wait=2)
            else:
                print("  WARN: 22_admin_chatbots — tab button not found")
        except Exception as e:
            print(f"  WARN: 22_admin_chatbots failed — {e}")

        # 23 — Admin Agents tab with FHIRSpecialist selected
        try:
            if click_nav_button(page, "agents"):
                click_list_item(page, "li, tr, .list-item, .agent-row, .row", "FHIRSpecialist")
                shot(page, "23_admin_agent_fhir", wait=2)
            else:
                print("  WARN: 23 — agents tab not found")
        except Exception as e:
            print(f"  WARN: 23_admin_agent_fhir — {e}")

        # 24 — Admin MCPs tab with FHIRServer selected
        try:
            if click_nav_button(page, "mcps"):
                click_list_item(page, "li, tr, .list-item, .mcp-row, .row", "FHIRServer")
                shot(page, "24_admin_mcp_fhirserver", wait=2)
            else:
                print("  WARN: 24 — mcps tab not found")
        except Exception as e:
            print(f"  WARN: 24_admin_mcp_fhirserver — {e}")

        # 25 — Admin Tools tab with Tool.FHIRServer selected
        try:
            if click_nav_button(page, "tools"):
                click_list_item(page, "li, tr, .list-item, .tool-row, .row", "FHIRServer")
                shot(page, "25_admin_tool_fhirserver", wait=2)
            else:
                print("  WARN: 25 — tools tab not found")
        except Exception as e:
            print(f"  WARN: 25_admin_tool_fhirserver — {e}")

        browser.close()
        print("\nDone — FHIR Assistant screenshots saved to docs/img/")


if __name__ == "__main__":
    main()
