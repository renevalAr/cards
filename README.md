# Карточки — flashcard-приложение в эстетике школьной тетради

Vanilla HTML/CSS/JS. Без фреймворков, сборки и зависимостей. Офлайн-first: все данные — в твоём браузере (localStorage + IndexedDB), сервера нет.

## Запуск

Открыть `index.html` в Chrome (двойной клик). Всё.

## Возможности

- Колоды и карточки: форма, массовый ввод `вопрос = ответ`, поиск, фильтры, drag-reorder
- Учить: карточки с флипом / квиз (клавиши 1–4) / полноэкранный режим / двусторонние колоды
- Озвучка карточек (TTS), картинки в карточках (IndexedDB, сжатие 480px WebP)
- Экспорт/импорт базы и колод (JSON + CSV)
- 10 палитр × светлая/тёмная/авто × размер текста S/M/L
- Статистика: день, серия дней, журнал сессий

## Тесты

29 наборов (PowerShell + Chrome DevTools Protocol), параллельный раннер:

```powershell
powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1 -Smoke   # быстро
powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1          # полный
```

CI: GitHub Actions — smoke на каждый push, полный прогон вручную (вкладка Actions → Run workflow).

## Документация

Полный контекст для человека или ИИ — [DOCUMENTATION.md](DOCUMENTATION.md): архитектура, все ID/функции, дизайн-система, решения и грабли.
