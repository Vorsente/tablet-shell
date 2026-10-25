// Backend of the tablet-settings app: settings files, the tablet/PC mode, and the actions that
// apply a change to the running environment (tabletd, KWin scripts, Plasma, helper tools).
#pragma once

#include <QHash>
#include <QByteArray>
#include <QStringList>
#include <QObject>
#include <QVariant>

#include <memory>

class QQmlEngine;
class KQuickConfigModule;
class QProcess;

class Backend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool tabletMode READ tabletMode NOTIFY tabletModeChanged)
    Q_PROPERTY(QVariantMap updateInfo READ updateInfo NOTIFY updateInfoChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    bool tabletMode() const
    {
        return m_tabletMode;
    }

    // KConfig access; `group` may be nested with "/" (e.g. "Containments/1/General")
    Q_INVOKABLE QVariant read(const QString &file, const QString &group, const QString &key, const QVariant &fallback) const;
    Q_INVOKABLE void write(const QString &file, const QString &group, const QString &key, const QVariant &value, bool notify = false);

    // apply changed settings to the running environment
    Q_INVOKABLE void reapplyModes();                                    // tabletd: re-apply tablet/PC mode
    Q_INVOKABLE void reloadKWinScript(const QString &name);             // KWin script reads its config on load
    Q_INVOKABLE void activateWindow() const;                            // through KWin: no activation token needed
    Q_INVOKABLE void setDeviceMode(const QString &mode);                // auto | on | off (KWin tablet mode)
    Q_INVOKABLE QString deviceMode() const;
    Q_INVOKABLE void setHomeScreen(const QString &key, const QVariant &value);  // home screen containment config
    Q_INVOKABLE QVariant homeScreen(const QString &key, const QVariant &fallback) const;
    Q_INVOKABLE QVariant containmentConfig(const QString &plugin, const QString &key, const QVariant &fallback) const;
    Q_INVOKABLE void setContainmentConfig(const QString &plugin, const QString &key, const QVariant &value);

    Q_INVOKABLE QString run(const QStringList &command) const;          // short helpers only
    Q_INVOKABLE void start(const QStringList &command) const;

    // web apps on the home screen
    Q_INVOKABLE QVariantList webApps() const;
    Q_INVOKABLE void addWebApp(const QString &name, const QString &url);
    Q_INVOKABLE void removeWebApp(const QString &id);

    Q_INVOKABLE QVariantList wallpapers() const;
    Q_INVOKABLE QVariantMap systemInfo() const;
    Q_INVOKABLE QString home() const;

    // Asynchronous GitHub updates. All stages are reported to QML, without log files.
    QVariantMap updateInfo() const { return m_updateInfo; }
    Q_INVOKABLE void checkForUpdates();
    Q_INVOKABLE void installGitHubUpdate();
    Q_INVOKABLE void cancelUpdate();

    // standard KDE settings modules (KCMs), embedded like System Settings does
    Q_INVOKABLE QVariantList modules() const;                 // [{id, name, icon, group, groupName, qml}]
    Q_INVOKABLE QObject *loadModule(const QString &id);       // QML module: the KQuickConfigModule
    Q_INVOKABLE void openModuleWindow(const QString &id) const; // widget-based module: own window
    Q_INVOKABLE QString startModule() const { return m_startModule; }

    void setEngine(std::shared_ptr<QQmlEngine> engine) { m_engine = std::move(engine); }

public Q_SLOTS:
    // D-Bus (org.ipad.TabletSettings /): a second launch hands its module over to this window
    Q_SCRIPTABLE void OpenModule(const QString &id) { Q_EMIT moduleRequested(id); }

    void setStartModule(const QString &id) { m_startModule = id; }

Q_SIGNALS:
    void tabletModeChanged();
    void webAppsChanged();
    void updateInfoChanged();
    void moduleRequested(const QString &id);

private Q_SLOTS:
    void onTabletModeChanged(bool tablet);

private:
    bool m_tabletMode = false;
    std::shared_ptr<QQmlEngine> m_engine;
    QHash<QString, KQuickConfigModule *> m_modules;
    QString m_startModule;
    QVariantMap m_updateInfo{{QStringLiteral("stage"), QStringLiteral("idle")},
                             {QStringLiteral("installed"), QStringLiteral("local")}};
    QProcess *m_updateProcess = nullptr;
    QByteArray m_updateBuffer;
    void launchUpdater(const QStringList &args);
    void consumeUpdaterOutput();
};
