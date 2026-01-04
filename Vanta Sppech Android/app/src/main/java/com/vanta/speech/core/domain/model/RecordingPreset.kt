package com.vanta.speech.core.domain.model

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PhoneForwarded
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.ui.graphics.vector.ImageVector

enum class RecordingPreset(
    val id: String,
    val displayName: String,
    val icon: ImageVector
) {
    SALES_CALL(
        id = "sales_call",
        displayName = "Sales",
        icon = Icons.Default.PhoneForwarded
    ),
    PROJECT_MEETING(
        id = "project_meeting",
        displayName = "Project Meeting",
        icon = Icons.Default.Folder
    ),
    DAILY_STANDUP(
        id = "daily_standup",
        displayName = "Daily",
        icon = Icons.Default.WbSunny
    ),
    INTERVIEW(
        id = "interview",
        displayName = "Interview",
        icon = Icons.Default.PersonAdd
    ),
    FAST_IDEA(
        id = "fast_idea",
        displayName = "Quick Note",
        icon = Icons.Default.Bolt
    );

    val systemPrompt: String
        get() = when (this) {
            SALES_CALL -> """
                Ты эксперт по продажам. Проанализируй транскрипцию звонка и выдели:
                - Информация о клиенте (имя, компания, должность)
                - Потребности и боли клиента
                - Бюджет (если упоминался)
                - Возражения и как они были обработаны
                - Следующие шаги и договорённости
                - Рекомендации для follow-up

                Формат: структурированный markdown с заголовками.
            """.trimIndent()

            PROJECT_MEETING -> """
                Ты опытный проектный менеджер. Проанализируй транскрипцию встречи и выдели:
                - Ключевые обсуждаемые темы
                - Принятые решения
                - Открытые вопросы
                - Блокеры и риски
                - Задачи с ответственными (если назначены)
                - Следующие шаги

                Формат: структурированный markdown с заголовками.
            """.trimIndent()

            DAILY_STANDUP -> """
                Проанализируй транскрипцию дейли-митинга. Структурируй информацию:
                - По участникам или по темам
                - Что сделано
                - Что планируется
                - Блокеры

                Формат: краткий структурированный markdown.
            """.trimIndent()

            INTERVIEW -> """
                Ты HR-эксперт. Проанализируй транскрипцию интервью и выдели:
                - Опыт кандидата
                - Ключевые навыки
                - Red flags (если есть)
                - Сильные стороны
                - Мнение интервьюера (если есть)
                - Рекомендация (hire/no hire/maybe)

                Формат: структурированный markdown с заголовками.
            """.trimIndent()

            FAST_IDEA -> """
                Обработай голосовую заметку:
                - Очисти от слов-паразитов
                - Структурируй мысли
                - Выдели ключевые идеи
                - Извлеки задачи (если есть)

                Формат: краткий структурированный markdown.
            """.trimIndent()
        }

    companion object {
        fun fromId(id: String?): RecordingPreset? =
            entries.find { it.id == id }
    }
}
