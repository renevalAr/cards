import pytest
from playwright.sync_api import sync_playwright


@pytest.fixture(scope="session")
def browser():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        yield browser
        browser.close()


@pytest.fixture
def page(browser):
    page = browser.new_page()
    yield page
    page.close()


@pytest.fixture
def authenticated_page(browser):
    page = browser.new_page()
    page.goto("http://localhost:8000")
    page.click("#auth-tab-register")
    page.fill("#auth-register-form [name=email]", "e2e@test.com")
    page.fill("#auth-register-form [name=password]", "SecurePass123!")
    page.click("#auth-register-form button[type=submit]")
    page.locator("#auth-bar").wait_for(state="visible", timeout=10000)
    yield page
    page.close()
