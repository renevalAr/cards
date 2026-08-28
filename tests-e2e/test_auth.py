import pytest
from playwright.sync_api import Page, expect


def test_health_check(page: Page):
    page.goto("http://localhost:8000/api/health")
    expect(page).to_have_url("http://localhost:8000/api/health")


def test_frontend_loads(page: Page):
    page.goto("http://localhost:8000")
    expect(page).to_have_title("Карточки")


def test_auth_modal_toggle(page: Page):
    page.goto("http://localhost:8000")
    page.click("#auth-tab-register")
    expect(page.locator("#auth-register-form")).to_be_visible()
    page.click("#auth-tab-login")
    expect(page.locator("#auth-login-form")).to_be_visible()


def test_register_flow(page: Page):
    page.goto("http://localhost:8000")
    page.click("#auth-tab-register")
    page.fill("#auth-register-form [name=email]", "e2e@test.com")
    page.fill("#auth-register-form [name=password]", "SecurePass123!")
    page.click("#auth-register-form button[type=submit]")
    expect(page.locator("#auth-bar")).to_be_visible(timeout=10000)


def test_login_flow(page: Page):
    page.goto("http://localhost:8000")
    page.click("#auth-tab-login")
    page.fill("#auth-login-form [name=email]", "e2e@test.com")
    page.fill("#auth-login-form [name=password]", "SecurePass123!")
    page.click("#auth-login-form button[type=submit]")
    expect(page.locator("#auth-bar")).to_be_visible(timeout=10000)


def test_logout(page: Page):
    page.goto("http://localhost:8000")
    page.click("#auth-tab-login")
    page.fill("#auth-login-form [name=email]", "e2e@test.com")
    page.fill("#auth-login-form [name=password]", "SecurePass123!")
    page.click("#auth-login-form button[type=submit]")
    expect(page.locator("#auth-bar")).to_be_visible(timeout=10000)
    page.click("#auth-logout-btn")
    expect(page.locator("#auth-bar")).to_be_hidden()
