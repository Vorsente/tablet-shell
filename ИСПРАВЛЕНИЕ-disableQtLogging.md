# Исправление сборки клавиатуры — disableQtLogging

- `src/tablet-keyboard/main.cpp`: добавлен `#include "../common/no-logging.h"`.
- Исправлена ошибка компиляции `disableQtLogging was not declared in this scope`.
- Добавлен регрессионный тест `tests/no-logging-header.test.cjs`, проверяющий объявления во всех C++ точках входа.
- Функциональность клавиатуры, уведомлений, Apple/Pixel-оформления и установщика не изменялась.

## Применение

В распакованном проекте выполнить:

```bash
bash ./update.sh --offline
```

Проведена проверка всех JS-тестов (`node --test tests/*.test.cjs`). Реальная компиляция Qt требует Arch Linux с зависимостями проекта.
