// Shared shell appearance. Watches KDE's tabletrc without polling expensive processes.
// KConfig may replace files atomically: watch both parent directory and actual file.
#pragma once
#include <QObject>
#include <QFileSystemWatcher>
#include <QSettings>
#include <QStandardPaths>
#include <QDir>
#include <QFileInfo>
#include <QTimer>

class UiStyle : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString name READ name NOTIFY changed)
    Q_PROPERTY(bool pixel READ pixel NOTIFY changed)
public:
    explicit UiStyle(QObject *parent = nullptr) : QObject(parent) {
        m_file = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
                 + QStringLiteral("/tabletrc");
        const QString dir = QFileInfo(m_file).absolutePath();
        if (QFileInfo::exists(dir)) m_watcher.addPath(dir);
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &UiStyle::refresh);
        connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &UiStyle::refresh);
        // Fallback for unusual filesystem watchers / newly created configuration directories.
        auto *check = new QTimer(this);
        check->setInterval(10000);
        connect(check, &QTimer::timeout, this, &UiStyle::refresh);
        check->start();
        refresh();
    }
    QString name() const { return m_name; }
    bool pixel() const { return m_name == QLatin1String("pixel"); }
Q_SIGNALS:
    void changed();
private:
    void refresh() {
        QSettings settings(m_file, QSettings::IniFormat);
        const QString value = settings.value(QStringLiteral("Appearance/shellStyle"), QStringLiteral("apple")).toString();
        const QString next = value == QLatin1String("pixel") ? QStringLiteral("pixel") : QStringLiteral("apple");
        if (m_name != next) { m_name = next; Q_EMIT changed(); }
        if (QFileInfo::exists(m_file) && !m_watcher.files().contains(m_file)) m_watcher.addPath(m_file);
        const QString dir = QFileInfo(m_file).absolutePath();
        if (QFileInfo::exists(dir) && !m_watcher.directories().contains(dir)) m_watcher.addPath(dir);
    }
    QFileSystemWatcher m_watcher;
    QString m_file;
    QString m_name;
};
