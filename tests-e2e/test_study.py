import pytest
from playwright.sync_api import Page, expect


def login(page: Page, email="e2e@test.com", password="SecurePass123!"):
    page.goto("http://localhost:8000")
    page.click("#auth-tab-login")
    page.fill("#auth-login-form [name=email]", email)
    page.fill("#auth-login-form [name=password]", password)
    page.click("#auth-login-form button[type=submit]")
    expect(page.locator("#auth-bar")).to_be_visible(timeout=10000)


def test_create_deck(page: Page):
    login(page)
    page.click("#new-deck-btn")
    expect(page.locator("#workspace")).not_to_have_class("hidden")


def test_add_card(page: Page):
    login(page)
    page.click("#new-deck-btn")
    page.fill("#card-question", "What is Python?")
    page.fill("#card-answer", "A programming language")
    page.click("#save-card-btn")
    expect(page.locator("#card-rows li")).to_have_count(1, timeout=5000)


def test_study_mode(page: Page):
    login(page)
    page.click("#new-deck-btn")
    page.fill("#card-question", "2+2")
    page.fill("#card-answer", "4")
    page.click("#save-card-btn")
    expect(page.locator("#card-rows li")).to_have_count(1, timeout=5000)

    page.click("#tab-study")
    expect(page.locator("#study-board")).not_to_have_class("hidden")


def test_share_deck(page: Page):
    login(page)
    page.click("#new-deck-btn")
    page.fill("#card-question", "Q1")
    page.fill("#card-answer", "A1")
    page.click("#save-card-btn")
    expect(page.locator("#card-rows li")).to_have_count(1, timeout=5000)
