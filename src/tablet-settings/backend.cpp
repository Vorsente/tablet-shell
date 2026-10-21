#include "backend.h"

#include <KConfig>
#include <KConfigGroup>
#include <KPluginMetaData>
#include <KQuickConfigModule>
#include <KQuickConfigModuleLoader>

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusVariant>
#include <QJsonObject>
#include <QQmlEngine>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QCoreApplication>
#include <QSysInfo>

#include "tr.h"

namespace
{
KConfigGroup groupPath(KConfig &cfg, const QString &path)
{
    const QStringList parts = path.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    KConfigGroup g = cfg.group(parts.value(0));
    for (int i = 1; i < parts.size(); ++i) {
        g = g.group(parts.at(i));
    }
    return g;
}

// the first battery (BAT0, BAT1, CMB0 ...)
QString batteryDir()
{
    const QDir power(QStringLiteral("/sys/class/power_supply"));
    for (const QString &d : power.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        QFile type(power.filePath(d + QStringLiteral("/type")));
        if (type.open(QIODevice::ReadOnly) && type.readAll().trimmed() == "Battery") {
            return power.filePath(d);
        }
    }
    return QStringLiteral("/sys/class/power_supply/BAT0");
}

QString readSys(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).trimmed() : QString();
}

void asyncCall(const QString &service, const QString &path, const QString &iface, const QString &method, const QVariantList &args = {})
{
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, iface, method);
    msg.setArguments(args);
    QDBusConnection::sessionBus().asyncCall(msg);
}

QString plasmaScript(const QString &script)
{
    QDBusInterface shell(QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"), QStringLiteral("org.kde.PlasmaShell"));
    QDBusReply<QString> r = shell.call(QStringLiteral("evaluateScript"), script);
    return r.isValid() ? r.value() : QString();
}

QString jsValue(const QVariant &v)
{
    if (v.typeId() == QMetaType::Bool) {
        return v.toBool() ? QStringLiteral("true") : QStringLiteral("false");
    }
    if (v.canConvert<double>() && v.typeId() != QMetaType::QString) {
        return v.toString();
    }
    QString s = v.toString();
    s.replace(QLatin1Char('\\'), QStringLiteral("\\\\")).replace(QLatin1Char('\''), QStringLiteral("\\'"));
    return QLatin1Char('\'') + s + QLatin1Char('\'');
}
} // namespace

Backend::Backend(QObject *parent)
    : QObject(parent)
{
    auto bus = QDBusConnection::sessionBus();
    bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin"), QStringLiteral("org.kde.KWin.TabletModeManager"),
                QStringLiteral("tabletModeChanged"), this, SLOT(onTabletModeChanged(bool)));
    QDBusInterface kwin(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin"), QStringLiteral("org.freedesktop.DBus.Properties"));
    QDBusReply<QDBusVariant> r = kwin.call(QStringLiteral("Get"), QStringLiteral("org.kde.KWin.TabletModeManager"), QStringLiteral("tabletMode"));
    m_tabletMode = r.isValid() && r.value().variant().toBool();
    // for testing the touch layout without switching the whole device
    if (qEnvironmentVariableIsSet("TABLET_SETTINGS_TOUCH")) {
        m_tabletMode = qEnvironmentVariableIntValue("TABLET_SETTINGS_TOUCH") != 0;
    }
}

void Backend::onTabletModeChanged(bool tablet)
{
    if (qEnvironmentVariableIsSet("TABLET_SETTINGS_TOUCH")) {
        return;
    }
    if (tablet != m_tabletMode) {
        m_tabletMode = tablet;
        Q_EMIT tabletModeChanged();
    }
}

QVariant Backend::read(const QString &file, const QString &group, const QString &key, const QVariant &fallback) const
{
    KConfig cfg(file, KConfig::SimpleConfig);
    const KConfigGroup g = groupPath(cfg, group);
    if (!g.hasKey(key)) {
        return fallback;
    }
    switch (fallback.typeId()) {
    case QMetaType::Bool:
        return g.readEntry(key, fallback.toBool());
    case QMetaType::Int:
        return g.readEntry(key, fallback.toInt());
    case QMetaType::Double:
        return g.readEntry(key, fallback.toDouble());
    default:
        return g.readEntry(key, fallback.toString());
    }
}

void Backend::write(const QString &file, const QString &group, const QString &key, const QVariant &value, bool notify)
{
    KConfig cfg(file, KConfig::SimpleConfig);
    KConfigGroup g = groupPath(cfg, group);
    KConfig::WriteConfigFlags flags = KConfig::Persistent;
    if (notify) {
        flags |= KConfig::Notify;
    }
    if (value.typeId() == QMetaType::Bool) {
        g.writeEntry(key, value.toBool(), flags);
    } else if (value.typeId() == QMetaType::Double && value.toDouble() == qRound(value.toDouble())) {
        g.writeEntry(key, qRound(value.toDouble()), flags);
    } else {
        g.writeEntry(key, value, flags);
    }
    cfg.sync();
}

void Backend::reapplyModes()
{
    asyncCall(QStringLiteral("org.ipad.TabletD"), QStringLiteral("/"), QStringLiteral("org.ipad.TabletD"), QStringLiteral("Reapply"));
}

void Backend::reloadKWinScript(const QString &name)
{
    QDBusInterface scripting(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), QStringLiteral("org.kde.kwin.Scripting"));
    scripting.call(QStringLiteral("unloadScript"), name);
    asyncCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"), QStringLiteral("reconfigure"));
}

// Unminimize and focus this app's window. A launch from the control center or a second launch
// (OpenModule over D-Bus) has no XDG activation token, so KWin refused requestActivate(): the
// window showed up without being the active one, and the home/app-switcher gesture, which goes
// by the active window, behaved as if no app was open. A KWin script may activate any window.
void Backend::activateWindow() const
{
    const QString name = QStringLiteral("tablet-settings-activate");
    const QString path = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + QStringLiteral("/tablet-settings-activate.js");
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return;
    }
    f.write(QStringLiteral("workspace.windowList().forEach(function (w) {\n"
                           "    if (w.pid === %1 && w.normalWindow) {\n"
                           "        w.minimized = false;\n"
                           "        workspace.activeWindow = w;\n"
                           "    }\n"
                           "});\n")
                .arg(QCoreApplication::applicationPid())
                .toUtf8());
    f.close();
    QDBusInterface scripting(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), QStringLiteral("org.kde.kwin.Scripting"));
    scripting.call(QStringLiteral("unloadScript"), name);
    QDBusReply<int> id = scripting.call(QStringLiteral("loadScript"), path, name);
    if (!id.isValid() || id.value() < 0) {
        return;
    }
    QDBusInterface script(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting/Script%1").arg(id.value()), QStringLiteral("org.kde.kwin.Script"));
    script.call(QStringLiteral("run"));
    scripting.call(QStringLiteral("unloadScript"), name);
}

// auto|on|off. tabletd owns KWin's TabletMode (auto = keyboard dock attached -> PC), so the
// choice lives in tabletrc and tabletd is asked to apply it
QString Backend::deviceMode() const
{
    const QString kwin = read(QStringLiteral("kwinrc"), QStringLiteral("Input"), QStringLiteral("TabletMode"), QStringLiteral("auto")).toString();
    return read(QStringLiteral("tabletrc"), QStringLiteral("Modes"), QStringLiteral("deviceMode"), kwin).toString();
}

void Backend::setDeviceMode(const QString &mode)
{
    write(QStringLiteral("tabletrc"), QStringLiteral("Modes"), QStringLiteral("deviceMode"), mode, false);
    asyncCall(QStringLiteral("org.ipad.TabletD"), QStringLiteral("/"), QStringLiteral("org.ipad.TabletD"), QStringLiteral("syncDeviceMode"));
}

// config of one containment type: the home screen (org.ipad.homescreen) or the dock dashboard
// (org.ipad.dashboard); each screen has its own containment, so filter by plugin
QVariant Backend::containmentConfig(const QString &plugin, const QString &key, const QVariant &fallback) const
{
    const QString out = plasmaScript(QStringLiteral("var v = '__unset__'; desktops().forEach(function (d) { if (d.type == '%1') {"
                                                    " d.currentConfigGroup = ['General']; v = d.readConfig('%2', '__unset__'); } }); print(v);")
                                         .arg(plugin, key))
                            .trimmed();
    if (out.isEmpty() || out == QLatin1String("__unset__")) {
        return fallback;
    }
    if (fallback.typeId() == QMetaType::Bool) {
        return out == QLatin1String("true");
    }
    return out;
}

void Backend::setContainmentConfig(const QString &plugin, const QString &key, const QVariant &value)
{
    plasmaScript(QStringLiteral("desktops().forEach(function (d) { if (d.type == '%1') { d.currentConfigGroup = ['General'];"
                                " d.writeConfig('%2', %3); d.reloadConfig(); } });")
                     .arg(plugin, key, jsValue(value)));
}

QVariant Backend::homeScreen(const QString &key, const QVariant &fallback) const
{
    return containmentConfig(QStringLiteral("org.ipad.homescreen"), key, fallback);
}

void Backend::setHomeScreen(const QString &key, const QVariant &value)
{
    setContainmentConfig(QStringLiteral("org.ipad.homescreen"), key, value);
}

QString Backend::run(const QStringList &command) const
{
    if (command.isEmpty()) {
        return {};
    }
    QProcess p;
    p.start(command.first(), command.mid(1));
    p.waitForFinished(15000);
    return QString::fromUtf8(p.readAllStandardOutput());
}

void Backend::start(const QStringList &command) const
{
    if (!command.isEmpty()) {
        QProcess::startDetached(command.first(), command.mid(1));
    }
}

QVariantList Backend::webApps() const
{
    QVariantList list;
    const QString dir = home() + QStringLiteral("/.local/share/applications");
    for (const QString &f : QDir(dir).entryList({QStringLiteral("webapp-*.desktop")}, QDir::Files, QDir::Name)) {
        KConfig desktop(dir + QLatin1Char('/') + f, KConfig::SimpleConfig);
        const KConfigGroup e = desktop.group(QStringLiteral("Desktop Entry"));
        list << QVariantMap{{QStringLiteral("id"), f.chopped(8)},
                            {QStringLiteral("name"), e.readEntry("Name")},
                            {QStringLiteral("url"), e.readEntry("X-WebApp-URL")},
                            {QStringLiteral("icon"), e.readEntry("Icon")}};
    }
    return list;
}

void Backend::addWebApp(const QString &name, const QString &url)
{
    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [this, p] {
        p->deleteLater();
        Q_EMIT webAppsChanged();
    });
    p->start(home() + QStringLiteral("/.local/bin/webapp-create"), {name, url});
}

void Backend::removeWebApp(const QString &id)
{
    QProcess::execute(home() + QStringLiteral("/.local/bin/webapp-create"), {QStringLiteral("--remove"), id});
    Q_EMIT webAppsChanged();
}

QVariantList Backend::wallpapers() const
{
    QVariantList list;
    for (const QString &line : run({home() + QStringLiteral("/.local/bin/wallpaper"), QStringLiteral("list")}).split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QStringList parts = line.split(QLatin1Char('\t'));
        if (parts.size() == 2) {
            list << QVariantMap{{QStringLiteral("path"), parts[0]}, {QStringLiteral("thumb"), parts[1]},
                                {QStringLiteral("name"), parts[0].section(QLatin1Char('/'), -1).remove(QStringLiteral("-iPad"))}};
        }
    }
    return list;
}

QVariantMap Backend::systemInfo() const
{
    QVariantMap info;
    info[QStringLiteral("model")] = readSys(QStringLiteral("/sys/class/dmi/id/product_version")) + QStringLiteral(" (")
        + readSys(QStringLiteral("/sys/class/dmi/id/product_name")) + QLatin1Char(')');
    QFile cpu(QStringLiteral("/proc/cpuinfo"));
    if (cpu.open(QIODevice::ReadOnly)) {
        for (const QByteArray &l : cpu.readAll().split('\n')) {
            if (l.startsWith("model name")) {
                info[QStringLiteral("cpu")] = QString::fromUtf8(l.mid(l.indexOf(':') + 1)).simplified();
                break;
            }
        }
    }
    QFile mem(QStringLiteral("/proc/meminfo"));
    if (mem.open(QIODevice::ReadOnly)) {
        const qint64 kb = QString::fromUtf8(mem.readLine()).section(QLatin1Char(':'), 1).simplified().section(QLatin1Char(' '), 0, 0).toLongLong();
        info[QStringLiteral("memory")] = QString::number(kb / 1024.0 / 1024.0, 'f', 1) + T(QStringLiteral(" ГБ"));
    }
    const double full = readSys(batteryDir() + QStringLiteral("/energy_full")).toDouble();
    const double design = readSys(batteryDir() + QStringLiteral("/energy_full_design")).toDouble();
    if (design > 0) {
        info[QStringLiteral("batteryHealth")] = QString::number(qRound(100 * full / design)) + T(QStringLiteral(" % от исходной ёмкости"));
    }
    info[QStringLiteral("battery")] = readSys(batteryDir() + QStringLiteral("/capacity")) + QStringLiteral(" %");
    const QStorageInfo root(QStringLiteral("/"));
    info[QStringLiteral("disk")] = T(QStringLiteral("%1 ГБ свободно из %2 ГБ"))
                                       .arg(root.bytesAvailable() / 1e9, 0, 'f', 1)
                                       .arg(root.bytesTotal() / 1e9, 0, 'f', 1);
    info[QStringLiteral("kernel")] = QSysInfo::kernelVersion();
    info[QStringLiteral("system")] = QSysInfo::prettyProductName();
    info[QStringLiteral("plasma")] = run({QStringLiteral("plasmashell"), QStringLiteral("--version")}).trimmed().section(QLatin1Char(' '), -1);
    return info;
}

QString Backend::home() const
{
    return QDir::homePath();
}

namespace
{
struct Category {
    QString name;
    QString parent;
    int weight = 0;
};

QHash<QString, Category> categories()
{
    QHash<QString, Category> out;
    const QString dir = QStringLiteral("/usr/share/systemsettings/categories");
    for (const QString &f : QDir(dir).entryList({QStringLiteral("*.desktop")})) {
        KConfig cfg(dir + QLatin1Char('/') + f, KConfig::SimpleConfig);
        cfg.setLocale(uiRussian() ? QStringLiteral("ru") : QStringLiteral("en"));   // localized keys (Name[ru]) follow the UI language
        const KConfigGroup e = cfg.group(QStringLiteral("Desktop Entry"));
        Category c;
        c.name = e.readEntry("Name");
        c.parent = e.readEntry("X-KDE-System-Settings-Parent-Category");
        c.weight = e.readEntry("X-KDE-Weight", 100);
        out.insert(e.readEntry("X-KDE-System-Settings-Category"), c);
    }
    return out;
}

// a settings module's name in the shell's language (Russian from Name[ru], otherwise the plugin's
// own localized name)
QString localName(const KPluginMetaData &md)
{
    if (!uiRussian()) {
        return md.name();
    }
    const QJsonObject plugin = md.rawData().value(QStringLiteral("KPlugin")).toObject();
    return plugin.value(QStringLiteral("Name[ru]")).toString(md.name());
}
} // namespace

QVariantList Backend::modules() const
{
    const auto cats = categories();
    struct Entry {
        QVariantMap data;
        int groupWeight;
        int weight;
    };
    QList<Entry> entries;
    QSet<QString> seen;
    for (const auto &[ns, qml] : {std::pair{QStringLiteral("plasma/kcms/systemsettings"), true},
                                  std::pair{QStringLiteral("plasma/kcms/systemsettings_qwidgets"), false}}) {
        for (const KPluginMetaData &md : KPluginMetaData::findPlugins(ns)) {
            if (seen.contains(md.pluginId()) || md.rawData().value(QStringLiteral("X-KDE-System-Settings-Parent-Category")).toString().isEmpty()) {
                continue;   // modules without a category are not shown in System Settings either
            }
            seen.insert(md.pluginId());
            // walk up to the top-level category (the group shown in the list)
            QString cat = md.rawData().value(QStringLiteral("X-KDE-System-Settings-Parent-Category")).toString();
            int guard = 0;
            while (cats.contains(cat) && !cats.value(cat).parent.isEmpty() && guard++ < 5) {
                cat = cats.value(cat).parent;
            }
            const Category top = cats.value(cat);
            entries.append({QVariantMap{{QStringLiteral("id"), md.pluginId()},
                                        {QStringLiteral("name"), localName(md)},
                                        {QStringLiteral("icon"), md.iconName()},
                                        {QStringLiteral("group"), cat},
                                        {QStringLiteral("groupName"), top.name.isEmpty() ? T(QStringLiteral("Другое")) : top.name},
                                        {QStringLiteral("qml"), qml}},
                            top.name.isEmpty() ? 999 : top.weight,
                            md.rawData().value(QStringLiteral("X-KDE-Weight")).toInt(100)});
        }
    }
    std::sort(entries.begin(), entries.end(), [](const Entry &a, const Entry &b) {
        if (a.groupWeight != b.groupWeight) {
            return a.groupWeight < b.groupWeight;
        }
        if (a.weight != b.weight) {
            return a.weight < b.weight;
        }
        return a.data.value(QStringLiteral("name")).toString().localeAwareCompare(b.data.value(QStringLiteral("name")).toString()) < 0;
    });
    QVariantList out;
    for (const Entry &e : entries) {
        out << e.data;
    }
    return out;
}

QObject *Backend::loadModule(const QString &id)
{
    if (KQuickConfigModule *m = m_modules.value(id)) {
        return m;
    }
    const KPluginMetaData md(QStringLiteral("plasma/kcms/systemsettings/") + id);
    if (!md.isValid() || !m_engine) {
        return nullptr;
    }
    const auto result = KQuickConfigModuleLoader::loadModule(md, this, {}, m_engine);
    if (!result) {
        qWarning() << "tablet-settings: cannot load" << id << result.errorText;
        return nullptr;
    }
    KQuickConfigModule *module = result.plugin;
    module->load();
    m_modules.insert(id, module);
    return module;
}

void Backend::openModuleWindow(const QString &id) const
{
    // the real one: /usr/local/bin/kcmshell6 may forward to this app
    QProcess::startDetached(QStringLiteral("/usr/bin/kcmshell6"), {id});
}
