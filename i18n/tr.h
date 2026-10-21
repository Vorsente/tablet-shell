// Shell translations for the C++ programs: text is written in Russian and looked up in
// ~/.local/share/tablet-i18n/en.json (built by i18n/build.py) when the UI language is not Russian.
#pragma once

#include <QFile>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QStandardPaths>
#include <QString>

inline bool uiRussian()
{
    static const bool ru = QLocale::system().uiLanguages().value(0).startsWith(QLatin1String("ru"));
    return ru;
}

inline QString T(const QString &ru)
{
    if (uiRussian()) {
        return ru;
    }
    static const QHash<QString, QString> en = [] {
        QHash<QString, QString> map;
        QString path = QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("tablet-i18n/en.json"));
        if (path.isEmpty()) {
            path = QStringLiteral("/usr/local/share/tablet-greeter/en.json");   // the login screen's own copy
        }
        QFile f(path);
        if (f.open(QIODevice::ReadOnly)) {
            const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
            for (auto it = o.begin(); it != o.end(); ++it) {
                map.insert(it.key(), it.value().toString());
            }
        }
        return map;
    }();
    return en.value(ru, ru);
}
