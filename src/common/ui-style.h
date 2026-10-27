// Shared shell appearance. Watches KDE's tabletrc without polling expensive processes.
// KConfig may replace files atomically: watch both parent directory and actual file.
//
// dp: size factor for everything the shell draws in fixed pixels (gestures, panels, buttons). The
// shell was tuned on a 10.1" 1920x1200 tablet at 125 % (7.085 logical px per mm); dp makes the same
// things the same physical size on any other screen, a little larger on big screens (seen from
// further away), times tabletrc [Appearance] uiScale (percent, Settings → Appearance). Screens that
// report no believable size (projectors, some TVs, virtual outputs) keep the tuned look (dp 1).
#pragma once
#include <QObject>
#include <QFileSystemWatcher>
#include <QSettings>
#include <QStandardPaths>
#include <QDir>
#include <QFileInfo>
#include <QTimer>
#include <QGuiApplication>
#include <QScreen>
#include <QtMath>
#include <algorithm>
#include <cmath>

namespace UiMetrics {
constexpr qreal referenceDensity = 7.085;   // logical px per mm of the reference tablet
constexpr qreal referenceDiagonal = 10.1;   // inches
// density in logical px per mm and the size in logical px -> the factor (before the user's scale)
inline qreal factor(qreal density, qreal width, qreal height)
{
    if (!(density > 2.5 && density < 25) || width <= 0 || height <= 0) {
        return 1;
    }
    const qreal diagonal = std::hypot(width, height) / density / 25.4;
    const qreal view = std::sqrt(std::clamp(diagonal / referenceDiagonal, 1.0, 2.5));
    return density / referenceDensity * view;
}
}

class UiStyle : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString name READ name NOTIFY changed)
    Q_PROPERTY(bool pixel READ pixel NOTIFY changed)
    Q_PROPERTY(qreal dp READ dp NOTIFY metricsChanged)
    Q_PROPERTY(qreal userScale READ userScale NOTIFY metricsChanged)
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
        // the screen the shell lives on: re-measure when it changes (rotation, scale, docking)
        connect(qGuiApp, &QGuiApplication::primaryScreenChanged, this, &UiStyle::watchScreen);
        watchScreen(QGuiApplication::primaryScreen());
    }
    QString name() const { return m_name; }
    bool pixel() const { return m_name == QLatin1String("pixel"); }
    qreal dp() const { return m_dp; }
    qreal userScale() const { return m_userScale; }
    // QML: uiStyle.factorFor(Screen.pixelDensity, Screen.width, Screen.height) for a window on another screen
    Q_INVOKABLE qreal factorFor(qreal density, qreal width, qreal height) const
    {
        return std::clamp(UiMetrics::factor(density, width, height) * m_userScale, 0.75, 3.0);
    }
Q_SIGNALS:
    void changed();
    void metricsChanged();
private:
    void watchScreen(QScreen *screen)
    {
        if (m_screen) {
            disconnect(m_screen, nullptr, this, nullptr);
        }
        m_screen = screen;
        if (screen) {
            connect(screen, &QScreen::geometryChanged, this, &UiStyle::measure);
            connect(screen, &QScreen::physicalDotsPerInchChanged, this, &UiStyle::measure);
            connect(screen, &QScreen::physicalSizeChanged, this, &UiStyle::measure);
        }
        measure();
    }
    void measure()
    {
        qreal next = 1;
        if (m_screen) {
            // Qt 6: geometry and physicalDotsPerInch are both in logical (scaled) pixels
            const QRect g = m_screen->geometry();
            next = factorFor(m_screen->physicalDotsPerInch() / 25.4, g.width(), g.height());
        } else {
            next = std::clamp(m_userScale, 0.75, 3.0);
        }
        next = std::round(next * 100) / 100;   // no relayout for rounding noise
        if (!qFuzzyCompare(next, m_dp)) {
            m_dp = next;
            Q_EMIT metricsChanged();
        }
    }
    void refresh() {
        QSettings settings(m_file, QSettings::IniFormat);
        const QString value = settings.value(QStringLiteral("Appearance/shellStyle"), QStringLiteral("apple")).toString();
        const QString next = value == QLatin1String("pixel") ? QStringLiteral("pixel") : QStringLiteral("apple");
        if (m_name != next) { m_name = next; Q_EMIT changed(); }
        const qreal scale = std::clamp(settings.value(QStringLiteral("Appearance/uiScale"), 100).toDouble(), 50.0, 200.0) / 100;
        if (!qFuzzyCompare(scale, m_userScale)) {
            m_userScale = scale;
            measure();
            Q_EMIT metricsChanged();
        }
        if (QFileInfo::exists(m_file) && !m_watcher.files().contains(m_file)) m_watcher.addPath(m_file);
        const QString dir = QFileInfo(m_file).absolutePath();
        if (QFileInfo::exists(dir) && !m_watcher.directories().contains(dir)) m_watcher.addPath(dir);
    }
    QFileSystemWatcher m_watcher;
    QString m_file;
    QString m_name;
    QScreen *m_screen = nullptr;
    qreal m_dp = 1;
    qreal m_userScale = 1;
};
