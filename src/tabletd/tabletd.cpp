// tabletd: the ThinkPad 10 tablet daemon (replaces tablet-mode-switch, power-button, pen-palm).
//
//  * Mode switching: tabletd decides the mode itself (a USB keyboard / the keyboard dock attached =
//    PC mode, see keyboardAttached) and sets KWin's tablet mode on/off. KWin's own "auto" only
//    re-evaluates when devices come and go and got stuck in tablet mode after a dock reconnect.
//    The user's choice auto|on|off is tabletrc [Modes] deviceMode. It then follows KWin's mode and
//    switches between the iPadOS-like tablet setup and the DeX-like PC setup. Settings are written
//    in-process with KConfig and every D-Bus call is asynchronous, so a switch costs milliseconds
//    instead of ~20 helper processes. The panels are rebuilt with a single Plasma script.
//  * Power button: tap locks and turns the screen off (or wakes it when locked), hold opens the
//    shutdown/restart/sleep menu. Reads KEY_POWER from evdev.
//  * Tray: app icons (StatusNotifierItems) go behind the tray's arrow as they appear, unless they
//    were pinned (moved to "always shown"); the system icons stay as they are.
//  * Windows button on the tablet (KEY_LEFTMETA of the same gpio-keys device): opens Claude Desktop.
//    KWin's Meta-only shortcut asks tabletd (MetaKey) so the Meta key of a keyboard still opens the
//    app launcher.
//  * Dock mode (PC mode + external monitor): the external monitor becomes the primary screen with
//    the home screen and panel, the built-in screen shows the dashboard (org.ipad.dashboard
//    containment) and the dock-mode KWin script keeps app windows off it. Monitors are watched
//    through kernel uevents (drm), no polling.
//  * Pen: palm rejection (finger touches are ignored while the pen is near the screen) and
//    Quick Note (a pen stroke from the bottom-right corner inwards).
// Device access for the evdev parts comes from udev "uaccess" rules.
#include <KConfig>
#include <KConfigGroup>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusConnectionInterface>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QDBusUnixFileDescriptor>
#include <QDir>
#include <QElapsedTimer>
#include <QStandardPaths>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSocketNotifier>
#include <QTimer>
#include <QHash>
#include <QRegularExpression>

#include <array>
#include <functional>
#include <cmath>
#include <cstring>
#include <cerrno>
#include <csignal>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/netlink.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

#include "tr.h"
#include <QtCore/qlogging.h>

namespace
{
const QString home = QDir::homePath();

QDBusConnection bus()
{
    return QDBusConnection::sessionBus();
}

// Fire-and-forget D-Bus call: never wait for KWin/Plasma to answer
void asyncCall(const QString &service, const QString &path, const QString &iface, const QString &method,
               const QVariantList &args = {})
{
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, iface, method);
    msg.setArguments(args);
    bus().asyncCall(msg);
}

// User settings of this environment (~/.config/tabletrc, edited by the tablet-settings app).
// Read fresh each time: the file is tiny and changes must apply without restarting.
QElapsedTimer hardwareMeta;   // last press of the tablet's Windows button

bool setting(const char *group, const char *key, bool fallback)
{
    KConfig cfg(QStringLiteral("tabletrc"), KConfig::SimpleConfig);
    return cfg.group(QString::fromLatin1(group)).readEntry(key, fallback);
}

QString settingString(const char *group, const char *key, const QString &fallback)
{
    KConfig cfg(QStringLiteral("tabletrc"), KConfig::SimpleConfig);
    return cfg.group(QString::fromLatin1(group)).readEntry(key, fallback);
}

QString readSys(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).trimmed() : QString();
}

bool processRunning(const QByteArray &comm)
{
    const auto pids = QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &pid : pids) {
        QFile f(QStringLiteral("/proc/%1/comm").arg(pid));
        if (f.open(QIODevice::ReadOnly) && f.readAll().trimmed() == comm) {
            return true;
        }
    }
    return false;
}

// Event devices that report a given key (e.g. KEY_POWER, BTN_TOOL_PEN), as /dev/input/eventN paths
QStringList devicesWithKey(int key, const std::function<bool(const QString &name)> &nameFilter = {})
{
    QStringList out;
    const auto events = QDir(QStringLiteral("/sys/class/input")).entryList({QStringLiteral("event*")});
    for (const QString &ev : events) {
        const QString base = QStringLiteral("/sys/class/input/%1/device/").arg(ev);
        const QStringList words = readSys(base + QStringLiteral("capabilities/key")).split(QLatin1Char(' '), Qt::SkipEmptyParts);
        // the bitmap is printed most significant 64-bit word first
        const int word = key / 64;
        if (word >= words.size()) {
            continue;
        }
        const quint64 bits = words.at(words.size() - 1 - word).toULongLong(nullptr, 16);
        if (!(bits & (1ULL << (key % 64)))) {
            continue;
        }
        if (nameFilter && !nameFilter(readSys(base + QStringLiteral("name")))) {
            continue;
        }
        out << QStringLiteral("/dev/input/") + ev;
    }
    return out;
}

// Opens evdev devices and calls back for every input_event
class EvdevReader : public QObject
{
public:
    using Handler = std::function<void(int fd, const input_event &)>;

    // Paths already open are skipped, so this can be called again for devices that came later.
    // A device that goes away (unplugged pen, Bluetooth off) is closed and may be opened again.
    bool open(const QStringList &paths, Handler handler)
    {
        for (const QString &path : paths) {
            if (m_paths.contains(path)) {
                continue;
            }
            const int fd = ::open(path.toLocal8Bit().constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
            if (fd < 0) {
                continue;
            }
            m_fds << fd;
            m_paths.insert(path, fd);
            auto *n = new QSocketNotifier(fd, QSocketNotifier::Read, this);
            connect(n, &QSocketNotifier::activated, this, [this, n, fd, path, handler] {
                input_event ev;
                ssize_t got;
                while ((got = ::read(fd, &ev, sizeof(ev))) == ssize_t(sizeof(ev))) {
                    handler(fd, ev);
                }
                if (got < 0 && errno == ENODEV) {
                    n->setEnabled(false);
                    n->deleteLater();
                    m_fds.removeAll(fd);
                    m_paths.remove(path);
                    ::close(fd);
                }
            });
        }
        return !m_fds.isEmpty();
    }

    ~EvdevReader() override
    {
        for (int fd : m_fds) {
            ::close(fd); // also releases any exclusive grab
        }
    }

    // A dedicated ACPI/GPIO power-key device can be grabbed exclusively, avoiding
    // duplicate physical events in Plasma/PowerDevil. Never grab a full keyboard,
    // volume controller or other multipurpose input device.
    void grabDedicatedPowerKeys()
    {
        for (int fd : m_fds) {
            std::array<unsigned long, (KEY_MAX + sizeof(unsigned long) * 8) / (sizeof(unsigned long) * 8)> bits{};
            if (::ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(bits)), bits.data()) < 0) {
                continue;
            }
            bool power = false, shared = false;
            for (int key = 0; key <= KEY_MAX; ++key) {
                if (!(bits[size_t(key) / (sizeof(unsigned long) * 8)] &
                      (1UL << (size_t(key) % (sizeof(unsigned long) * 8))))) {
                    continue;
                }
                if (key == KEY_POWER) {
                    power = true;
                } else if (key != KEY_LEFTMETA) {
                    shared = true;
                }
            }
            if (power && !shared) {
                ::ioctl(fd, EVIOCGRAB, 1); // best effort; PowerDevil is disabled below too
            }
        }
    }

    QList<int> fds() const
    {
        return m_fds;
    }

private:
    QList<int> m_fds;
    QHash<QString, int> m_paths;   // open device node -> fd
};
// Any external monitor (HDMI/DP) connected? eDP/DSI are the built-in panel.
QString externalConnector()
{
    const auto entries = QDir(QStringLiteral("/sys/class/drm")).entryList({QStringLiteral("card*-*")});
    for (const QString &e : entries) {
        const QString connector = e.section(QLatin1Char('-'), 1);
        if (connector.startsWith(QLatin1String("eDP")) || connector.startsWith(QLatin1String("DSI"))) {
            continue;
        }
        if (readSys(QStringLiteral("/sys/class/drm/%1/status").arg(e)) == QLatin1String("connected")) {
            return connector;
        }
    }
    return {};
}

// A keyboard attached over USB: the ThinkPad 10 keyboard dock ("Lenovo ThinkPad 10 Ultrabook
// Keyboard") or the USB dock with an external keyboard. Built-in buttons (gpio-keys, power,
// headset jack) are not USB.
// A real keyboard: a USB or Bluetooth input device with letter keys (Q, A and Z; the lowest 64 key
// bits are the last word of the capability mask). Mice, consumer-control keys, the power button
// and our own uinput device do not count. Same rule as tablet-keyboard.
// Detachable covers on other buses count too: the Surface Type Cover (Surface Pro 9 and newer) sits
// behind the Surface System Aggregator ("ssam", HID bus 0019 = host), not on USB. A fixed laptop
// keyboard (i8042/serio) never counts: convertibles report their folding with SW_TABLET_MODE.
bool detachableBus(const QString &path)
{
    static const QRegularExpression hostHid(QStringLiteral("/0019:[0-9A-F]{4}:[0-9A-F]{4}\\."));
    return path.contains(QLatin1String("/usb")) || path.contains(QLatin1String("/bluetooth")) || path.contains(QLatin1String("/uhid"))
           || path.contains(QLatin1String("/ssam:")) || path.contains(QLatin1String("surface")) || hostHid.match(path).hasMatch();
}

bool keyboardAttached()
{
    const QDir input(QStringLiteral("/sys/class/input"));
    for (const QString &e : input.entryList({QStringLiteral("input*")})) {
        const QString path = QFileInfo(input.filePath(e)).canonicalFilePath();
        if (!detachableBus(path)) {
            continue;
        }
        const QStringList words = readSys(path + QStringLiteral("/capabilities/key")).trimmed().split(QLatin1Char(' '));
        const quint64 low = words.last().toULongLong(nullptr, 16);
        if ((low >> 16 & 1) && (low >> 30 & 1) && (low >> 44 & 1)) {
            return true;
        }
    }
    return false;
}

// Hardware tablet-mode switch (SW_TABLET_MODE: a 360° hinge, a cover folded back or taken off,
// e.g. surface_aggregator_tabletsw on Surface Pro): -1 = no readable switch, 0 = laptop, 1 = tablet.
// Reading needs the uaccess rule for switches (system/devices.sh).
QStringList tabletSwitchNodes()
{
    QStringList nodes;
    const QDir input(QStringLiteral("/sys/class/input"));
    for (const QString &e : input.entryList({QStringLiteral("event*")})) {
        const QStringList words = readSys(input.filePath(e) + QStringLiteral("/device/capabilities/sw")).trimmed().split(QLatin1Char(' '));
        if (words.last().toULongLong(nullptr, 16) >> SW_TABLET_MODE & 1) {
            nodes << QStringLiteral("/dev/input/") + e;
        }
    }
    return nodes;
}

int tabletSwitch()
{
    int state = -1;
    for (const QString &node : tabletSwitchNodes()) {
        const int fd = ::open(QFile::encodeName(node).constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) {
            continue;
        }
        unsigned long bits[(SW_MAX + 8 * sizeof(long)) / (8 * sizeof(long))] = {};
        if (::ioctl(fd, EVIOCGSW(sizeof(bits)), bits) >= 0) {
            const bool on = bits[SW_TABLET_MODE / (8 * sizeof(long))] >> (SW_TABLET_MODE % (8 * sizeof(long))) & 1;
            state = std::max(state, on ? 1 : 0);
        }
        ::close(fd);
    }
    return state;
}

// Calls back (debounced) when a device of SUBSYSTEM reports a change: monitor (drm) or keyboard
// (input) plugged in or out
class UeventWatcher : public QObject
{
public:
    UeventWatcher(const char *subsystem, int debounceMs, std::function<void()> changed, QObject *parent)
        : QObject(parent)
        , m_match(QByteArray("SUBSYSTEM=") + subsystem)
    {
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(debounceMs);
        connect(&m_debounce, &QTimer::timeout, this, changed);
        m_fd = ::socket(AF_NETLINK, SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC, NETLINK_KOBJECT_UEVENT);
        sockaddr_nl addr = {};
        addr.nl_family = AF_NETLINK;
        addr.nl_groups = 1; // kernel uevents
        if (m_fd < 0 || ::bind(m_fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0) {
            return;
        }
        auto *n = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
        connect(n, &QSocketNotifier::activated, this, [this] {
            char buf[8192];
            ssize_t len;
            while ((len = ::recv(m_fd, buf, sizeof(buf) - 1, 0)) > 0) {
                buf[len] = 0;
                // NUL-separated KEY=value lines after the header
                for (ssize_t i = 0; i < len; i += ssize_t(strlen(buf + i)) + 1) {
                    if (strcmp(buf + i, m_match.constData()) == 0) {
                        m_debounce.start();
                        break;
                    }
                }
            }
        });
    }
    ~UeventWatcher() override
    {
        if (m_fd >= 0) {
            ::close(m_fd);
        }
    }

private:
    const QByteArray m_match;
    int m_fd = -1;
    QTimer m_debounce;
};
} // namespace

void openClaude();

// ---- mode switching ------------------------------------------------------------------------

class ModeSwitcher : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.ipad.TabletD")
public:
    explicit ModeSwitcher(QObject *parent)
        : QObject(parent)
    {
        bus().connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin"),
                      QStringLiteral("org.kde.KWin.TabletModeManager"), QStringLiteral("tabletModeChanged"), this,
                      SLOT(onTabletModeChanged(bool)));
        bus().connect(QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("/org/freedesktop/Notifications"),
                      QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("ActionInvoked"), this,
                      SLOT(onActionInvoked(uint, QString)));
        m_external = externalConnector();
        // the dock brings the monitor up in several steps
        new UeventWatcher("drm", 1200, [this] {
            const QString ext = externalConnector();
            if (ext != m_external) {
                m_external = ext;
                if (m_known) {
                    applyDock();
                }
            }
        }, this);
        // keyboard dock: it also drops off the bus for a moment now and then, so wait 1.5 s
        new UeventWatcher("input", 1500, [this] { watchSwitches(); syncDeviceMode(); }, this);
        watchSwitches();
        syncDeviceMode();
        // At login: apply once plasmashell is up (its panels are reshaped by script), not after a
        // fixed delay that is too short on a slow start
        // and again whenever plasmashell comes back (restart, crash): a switch that ran while it
        // was going down left half-reshaped panels
        const QString plasma = QStringLiteral("org.kde.plasmashell");
        if (bus().interface()->isServiceRegistered(plasma)) {
            QTimer::singleShot(1500, this, [this] { waitForPlasma(++m_plasmaWait, 0); });
        }
        auto *watcher = new QDBusServiceWatcher(plasma, bus(), QDBusServiceWatcher::WatchForRegistration | QDBusServiceWatcher::WatchForUnregistration, this);
        connect(watcher, &QDBusServiceWatcher::serviceUnregistered, this, [this] {
            ++m_generation; // cancel pending panel work while Plasma is down
        });
        connect(watcher, &QDBusServiceWatcher::serviceRegistered, this, [this] {
            QTimer::singleShot(1500, this, [this] { waitForPlasma(++m_plasmaWait, 0); });
        });
        // the keyboard/dock may have changed while the screen was locked or the tablet asleep
        // tray app icons: the ones already there, then each new one
        bus().connect(QStringLiteral("org.kde.StatusNotifierWatcher"), QStringLiteral("/StatusNotifierWatcher"),
                      QStringLiteral("org.kde.StatusNotifierWatcher"), QStringLiteral("StatusNotifierItemRegistered"), this,
                      SLOT(onTrayItem(QString)));
        QTimer::singleShot(8000, this, [this] {
            const QVariant items = QDBusInterface(QStringLiteral("org.kde.StatusNotifierWatcher"), QStringLiteral("/StatusNotifierWatcher"),
                                                  QStringLiteral("org.kde.StatusNotifierWatcher")).property("RegisteredStatusNotifierItems");
            for (const QString &item : items.toStringList()) {
                onTrayItem(item);
            }
        });
        bus().connect(QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"),
                      QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("ActiveChanged"), this,
                      SLOT(onScreenSaverActive(bool)));
        QDBusConnection::systemBus().connect(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"),
                                             QStringLiteral("org.freedesktop.login1.Manager"), QStringLiteral("PrepareForSleep"),
                                             this, SLOT(onPrepareForSleep(bool)));
    }

public Q_SLOTS:
    void onTabletModeChanged(bool tablet)
    {
        apply(tablet);
        if (!tablet && (setting("Modes", "askTypewriter", true) || setting("Modes", "askCoding", true))) {
            // after the mode change animation: a popup sent during it was hidden under the
            // full-screen animation and often timed out unseen
            QTimer::singleShot(2600, this, [this] {
                if (!m_tablet) {
                    askTypewriter();
                }
            });
        }
    }

    // "service/path" (or a bare service): read the item's Id and hide it in every tray
    void onTrayItem(const QString &item)
    {
        if (!setting("Tray", "hideApps", true)) {
            return;
        }
        const int slash = item.indexOf(QLatin1Char('/'));
        const QString service = slash < 0 ? item : item.left(slash);
        const QString path = slash < 0 ? QStringLiteral("/StatusNotifierItem") : item.mid(slash);
        QDBusMessage msg = QDBusMessage::createMethodCall(service, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
        msg << QStringLiteral("org.kde.StatusNotifierItem") << QStringLiteral("Id");
        auto *watcher = new QDBusPendingCallWatcher(bus().asyncCall(msg), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
            watcher->deleteLater();
            QDBusPendingReply<QDBusVariant> reply = *watcher;
            const QString id = reply.isValid() ? reply.value().variant().toString() : QString();
            if (id.isEmpty() || id.contains(QLatin1Char('"')) || id.contains(QLatin1Char('\\'))) {
                return;
            }
            // one script for all ids that came in together (parallel scripts overwrite each other)
            if (m_trayPending.isEmpty()) {
                QTimer::singleShot(500, this, &ModeSwitcher::hideTrayItems);
            }
            if (!m_trayPending.contains(id)) {
                m_trayPending << id;
            }
        });
    }

    void hideTrayItems()
    {
        const QString ids = QStringLiteral("[\"") + m_trayPending.join(QStringLiteral("\", \"")) + QStringLiteral("\"]");
        m_trayPending.clear();
        evaluate(QStringLiteral("var ids = %1;\n"
                                "panels().forEach(function (p) { p.widgets('org.kde.plasma.systemtray').forEach(function (t) {\n"
                                "    t.currentConfigGroup = ['General'];\n"
                                "    var shown = t.readConfig('shownItems', []), hidden = t.readConfig('hiddenItems', []);\n"
                                "    if (typeof shown === 'string') shown = shown ? shown.split(',') : [];\n"
                                "    if (typeof hidden === 'string') hidden = hidden ? hidden.split(',') : [];\n"
                                "    var changed = false;\n"
                                "    ids.forEach(function (id) {\n"
                                "        if (shown.indexOf(id) < 0 && hidden.indexOf(id) < 0) { hidden.push(id); changed = true; }\n"
                                "    });\n"
                                "    if (changed) t.writeConfig('hiddenItems', hidden);\n"
                                "}); });\n").arg(ids));
    }

    void onScreenSaverActive(bool active)
    {
        if (!active) {
            syncDeviceMode();
            checkMode("unlock");
        }
    }

    void onPrepareForSleep(bool sleeping)
    {
        if (!sleeping) {
            QTimer::singleShot(1500, this, [this] {
                syncDeviceMode();
                checkMode("resume");
            });
        }
    }

    // Ask KWin for the real tablet mode, look at the monitors, and fix whatever differs
    void checkMode(const char *reason)
    {
        QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin"),
                                                          QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
        msg << QStringLiteral("org.kde.KWin.TabletModeManager") << QStringLiteral("tabletMode");
        auto *watcher = new QDBusPendingCallWatcher(bus().asyncCall(msg), this);
        const QByteArray why(reason);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, why] {
            watcher->deleteLater();
            QDBusPendingReply<QDBusVariant> r = *watcher;
            if (!r.isValid()) {
                return;
            }
            const bool tablet = r.value().variant().toBool();
            const QString ext = externalConnector();
            if (!m_known || tablet != m_tablet || why == "start") {
                m_external = ext;
                apply(tablet);
            } else if (ext != m_external) {
                m_external = ext;
                applyDock();
            }
        });
    }

    // KWin's tablet mode from tabletrc [Modes] deviceMode (auto|on|off; auto = no keyboard ->
    // tablet). Only written when it changes; KWin then emits tabletModeChanged.
    Q_SCRIPTABLE void syncDeviceMode()
    {
        KConfig tabletrc(QStringLiteral("tabletrc"), KConfig::SimpleConfig);
        KConfigGroup modes = tabletrc.group(QStringLiteral("Modes"));
        KConfig kwinrc(QStringLiteral("kwinrc"), KConfig::SimpleConfig);
        KConfigGroup input = kwinrc.group(QStringLiteral("Input"));
        QString choice = modes.readEntry("deviceMode", QString());
        if (choice.isEmpty()) {
            // first run: take over what was set in KWin
            choice = input.readEntry("TabletMode", QStringLiteral("auto"));
            modes.writeEntry("deviceMode", choice);
            tabletrc.sync();
        }
        // auto: tablet when the hinge/cover switch says so, else when no keyboard is attached
        const bool tablet = tabletSwitch() == 1 || !keyboardAttached();
        const QString want = choice == QLatin1String("auto") ? (tablet ? QStringLiteral("on") : QStringLiteral("off")) : choice;
        if (input.readEntry("TabletMode", QString()) != want) {
            input.writeEntry("TabletMode", want, KConfig::Notify | KConfig::Persistent);
            kwinrc.sync();
        }
    }

    // SW_TABLET_MODE changes come as input events, not uevents: keep the switches open
    void watchSwitches()
    {
        const QStringList nodes = tabletSwitchNodes();
        for (auto it = m_switches.begin(); it != m_switches.end();) {
            if (!nodes.contains(it.key())) {
                ::close(int(it.value()->socket()));
                delete it.value();
                it = m_switches.erase(it);
            } else {
                ++it;
            }
        }
        for (const QString &node : nodes) {
            if (m_switches.contains(node)) {
                continue;
            }
            const int fd = ::open(QFile::encodeName(node).constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
            if (fd < 0) {
                continue;
            }
            auto *n = new QSocketNotifier(fd, QSocketNotifier::Read, this);
            connect(n, &QSocketNotifier::activated, this, [this, fd] {
                input_event ev;
                bool changed = false;
                while (::read(fd, &ev, sizeof(ev)) == ssize_t(sizeof(ev))) {
                    changed = changed || (ev.type == EV_SW && ev.code == SW_TABLET_MODE);
                }
                if (changed) {
                    QTimer::singleShot(300, this, [this] { syncDeviceMode(); });
                }
            });
            m_switches.insert(node, n);
        }
    }

    // KWin's Meta-only shortcut (kwinrc [ModifierOnlyShortcuts] Meta): the app launcher, unless it
    // was the tablet's Windows button (that one opens Claude Desktop, see openClaude)
    Q_SCRIPTABLE void MetaKey()
    {
        if (hardwareMeta.isValid() && hardwareMeta.elapsed() < 1500 && setting("Buttons", "windowsClaude", true)) {
            return;
        }
        asyncCall(QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"), QStringLiteral("org.kde.PlasmaShell"),
                  QStringLiteral("activateLauncherMenu"));
    }

    // what the Windows button does, for other buttons and gestures too
    Q_SCRIPTABLE void OpenClaude()
    {
        openClaude();
    }

    // Answer of the KWin probe script (probeViews): "desktops,panels" = windows plasmashell has
    Q_SCRIPTABLE void PanelViews(const QString &counts)
    {
        const QStringList parts = counts.split(QLatin1Char(','));
        if (!m_probe || parts.size() != 2) {
            return;
        }
        auto done = std::move(m_probe);
        m_probe = nullptr;
        done(parts[0].toInt(), parts[1].toInt());
    }

    // D-Bus (org.ipad.TabletD /): settings changed, apply the current mode again
    Q_SCRIPTABLE void Reapply()
    {
        if (m_known) {
            apply(m_tablet);
        }
    }

    void onActionInvoked(uint id, const QString &action)
    {
        if (id != m_askId) {
            return;
        }
        m_askId = 0;
        const QString typewriter = home + QStringLiteral("/.local/bin/typewriter");
        if (action == QLatin1String("open")) {
            QProcess::startDetached(typewriter, {});
        } else if (action == QLatin1String("new")) {
            QProcess::startDetached(typewriter, {QStringLiteral("new")});
        } else if (action == QLatin1String("coding")) {
            QProcess::startDetached(home + QStringLiteral("/.local/bin/coding-mode"), {});
        }
    }

public:
    void apply(bool tablet)
    {
        const int generation = ++m_generation;
        m_tablet = tablet;
        m_known = true;
        if (announceMode()) {
            // the animation covers the screen first, then everything changes behind it
            QTimer::singleShot(450, this, [this, tablet, generation] {
                if (generation == m_generation && m_tablet == tablet) {
                    applyNow(tablet);
                }
            });
        } else {
            applyNow(tablet);
        }
    }

    void applyNow(bool tablet)
    {
        // what tablet mode changes (all on by default; see the tablet-settings app)
        const bool hideTitleBars = tablet && setting("Modes", "hideTitleBars", true);
        const bool maximize = tablet && setting("Modes", "maximizeWindows", true);
        const bool iphoneGestures = tablet && setting("Modes", "iphoneGestures", true);
        const bool singleClick = tablet && setting("Modes", "singleClick", true);

        // Title bars: tablet mode forces them off with a KWin rule
        {
            KConfig rules(QStringLiteral("kwinrulesrc"), KConfig::SimpleConfig);
            KConfigGroup general = rules.group(QStringLiteral("General"));
            QStringList order = general.readEntry("Order", QStringList());
            order.removeAll(QStringLiteral("tablet-noborder"));
            if (hideTitleBars) {
                order << QStringLiteral("tablet-noborder");
                KConfigGroup rule = rules.group(QStringLiteral("tablet-noborder"));
                rule.writeEntry("Description", T(QStringLiteral("Планшет: без заголовков окон")));
                rule.writeEntry("decorationpolicy", QStringLiteral("none"));
                rule.writeEntry("decorationpolicyrule", 2);
                rule.writeEntry("types", 1);
            } else {
                rules.deleteGroup(QStringLiteral("tablet-noborder"));
            }
            general.writeEntry("Order", order);
            rules.sync();
        }
        {
            KConfig kwinrc(QStringLiteral("kwinrc"), KConfig::SimpleConfig);
            KConfigGroup windows = kwinrc.group(QStringLiteral("Windows"));
            windows.writeEntry("Placement", maximize ? QStringLiteral("Maximizing") : QStringLiteral("Centered"));
            windows.writeEntry("BorderlessMaximizedWindows", hideTitleBars);
            kwinrc.group(QStringLiteral("Plugins")).writeEntry("mobiletaskswitcherEnabled", iphoneGestures);
            kwinrc.group(QStringLiteral("Plugins")).writeEntry("dock-modeEnabled", docked());
            kwinrc.sync();
        }
        makeExternalPrimary();
        {
            KConfig globals(QStringLiteral("kdeglobals"));
            globals.group(QStringLiteral("KDE")).writeEntry("SingleClick", singleClick, KConfig::Notify | KConfig::Persistent);
            globals.sync();
        }
        {
            // touch has no hover: a tap left Plasma's tooltips (tray, panel) hanging on screen.
            // Off in tablet mode (what "Display informational tooltips" in System Settings writes)
            KConfig plasmarc(QStringLiteral("plasmarc"));
            KConfigGroup tips = plasmarc.group(QStringLiteral("PlasmaToolTips"));
            if (tablet) {
                tips.writeEntry("Delay", -1.0, KConfig::Notify | KConfig::Persistent);
            } else {
                tips.deleteEntry("Delay", KConfig::Notify | KConfig::Persistent);
            }
            plasmarc.sync();
        }

        // Plasma: reshape the existing panels in place (rebuilding the tray costs seconds)
        morphPanels(tablet);

        // KWin: re-read the settings, iPhone-style gestures only in tablet mode
        asyncCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"),
                  QStringLiteral("reconfigure"));
        asyncCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"), QStringLiteral("org.kde.kwin.Effects"),
                  iphoneGestures ? QStringLiteral("loadEffect") : QStringLiteral("unloadEffect"), {QStringLiteral("mobiletaskswitcher")});
        // running KDE apps: mouse settings (single/double click) changed
        QDBusMessage notify = QDBusMessage::createSignal(QStringLiteral("/KGlobalSettings"), QStringLiteral("org.kde.KGlobalSettings"),
                                                         QStringLiteral("notifyChange"));
        notify << 3 << 0;
        bus().send(notify);

        if (maximize) {
            // maximize every open window, like apps on iPadOS
            const QString scripting = QStringLiteral("org.kde.kwin.Scripting");
            asyncCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), scripting, QStringLiteral("unloadScript"),
                      {QStringLiteral("tablet-maximize")});
            asyncCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), scripting, QStringLiteral("loadScript"),
                      {home + QStringLiteral("/.local/share/tablet-mode/maximize-all.js"), QStringLiteral("tablet-maximize")});
            asyncCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), scripting, QStringLiteral("start"));
        } else if (!tablet) {
            // PC: title bars with close / minimize / maximize back on the windows already open
            const QString scripting = QStringLiteral("org.kde.kwin.Scripting");
            asyncCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), scripting, QStringLiteral("unloadScript"),
                      {QStringLiteral("tablet-borders")});
            asyncCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), scripting, QStringLiteral("loadScript"),
                      {home + QStringLiteral("/.local/share/tablet-mode/restore-borders.js"), QStringLiteral("tablet-borders")});
            asyncCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), scripting, QStringLiteral("start"));
        }
        applyScale(tablet);
    }

    // Mode change animation (tabletshell ModeTransition): only for a real change, not at login
    // or when plasmashell comes back with the same mode. It covers the screen until modeReady().
    bool announceMode()
    {
        const QString mode = docked() ? QStringLiteral("dock") : m_tablet ? QStringLiteral("tablet") : QStringLiteral("pc");
        const bool changed = !m_shownMode.isEmpty() && mode != m_shownMode;
        if (changed) {
            asyncCall(QStringLiteral("org.ipad.TabletShell"), QStringLiteral("/"), QStringLiteral("org.ipad.TabletShell"),
                      QStringLiteral("ModeTransition"), {m_shownMode, mode});
        }
        m_shownMode = mode;
        return changed;
    }

    // the new mode is in place: the animation may uncover the screen
    void modeReady()
    {
        asyncCall(QStringLiteral("org.ipad.TabletShell"), QStringLiteral("/"), QStringLiteral("org.ipad.TabletShell"),
                  QStringLiteral("ModeReady"));
    }

    bool docked() const
    {
        return !m_tablet && !m_external.isEmpty();
    }

    // Monitor plugged in or out while the mode stays: only the dock parts change
    void applyDock()
    {
        if (announceMode()) {
            QTimer::singleShot(450, this, [this] { applyDockNow(); });
        } else {
            applyDockNow();
        }
    }

    void applyDockNow()
    {
        {
            KConfig kwinrc(QStringLiteral("kwinrc"), KConfig::SimpleConfig);
            kwinrc.group(QStringLiteral("Plugins")).writeEntry("dock-modeEnabled", docked());
            kwinrc.sync();
        }
        asyncCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"), QStringLiteral("reconfigure"));
        makeExternalPrimary();
        // the monitors are rearranged asynchronously (kscreen-doctor)
        QTimer::singleShot(1500, this, [this] { modeReady(); });
    }

    // Scale of the built-in screen: big for fingers in tablet mode, denser with a keyboard and
    // touchpad (tabletrc [Modes] tabletScale / pcScale). Apps follow it: Wayland apps at once,
    // X11 apps through KWin's Xwayland scale. Only touches the screen when the scale differs.
    void applyScale(bool tablet)
    {
        // kscreen-doctor triggers an expensive KWin/Qt relayout of every surface.
        // Keep the display scale stable by default; users can opt in explicitly.
        if (!setting("Modes", "changeDisplayScale", false)) {
            return;
        }
        const double want = settingString("Modes", tablet ? "tabletScale" : "pcScale",
                                          tablet ? QStringLiteral("1.5") : QStringLiteral("1.25")).toDouble();
        if (want < 1 || want > 3) {
            return;
        }
        auto *p = new QProcess(this);
        connect(p, &QProcess::finished, this, [p, want] {
            p->deleteLater();
            const QJsonArray outputs = QJsonDocument::fromJson(p->readAllStandardOutput()).object().value(QStringLiteral("outputs")).toArray();
            for (const QJsonValue &o : outputs) {
                const QJsonObject out = o.toObject();
                const QString name = out.value(QStringLiteral("name")).toString();
                const bool internal = name.startsWith(QLatin1String("eDP")) || name.startsWith(QLatin1String("DSI"))
                                      || name.startsWith(QLatin1String("LVDS"));
                if (!internal || !out.value(QStringLiteral("enabled")).toBool()
                    || std::abs(out.value(QStringLiteral("scale")).toDouble() - want) < 0.01) {
                    continue;
                }
                QProcess::startDetached(QStringLiteral("kscreen-doctor"), {QStringLiteral("output.%1.scale.%2").arg(name).arg(want)});
                KConfig kwinrc(QStringLiteral("kwinrc"), KConfig::SimpleConfig);
                kwinrc.group(QStringLiteral("Xwayland")).writeEntry("Scale", want);
                kwinrc.sync();
            }
        });
        p->start(QStringLiteral("kscreen-doctor"), {QStringLiteral("-j")});
    }

    // Docked: the external monitor is the primary screen (Plasma puts the home screen and panel
    // on screen 0 and the dashboard on the built-in screen). Only touches the config when needed.
    void makeExternalPrimary()
    {
        if (!docked()) {
            return;
        }
        const QString ext = m_external;
        auto *p = new QProcess(this);
        connect(p, &QProcess::finished, this, [this, p, ext] {
            p->deleteLater();
            const QJsonArray outputs = QJsonDocument::fromJson(p->readAllStandardOutput()).object().value(QStringLiteral("outputs")).toArray();
            for (const QJsonValue &o : outputs) {
                const QJsonObject out = o.toObject();
                if (out.value(QStringLiteral("name")).toString() == ext && out.value(QStringLiteral("enabled")).toBool()
                    && out.value(QStringLiteral("priority")).toInt() != 1) {
                    QProcess::startDetached(QStringLiteral("kscreen-doctor"), {QStringLiteral("output.%1.priority.1").arg(ext)});
                }
            }
        });
        p->start(QStringLiteral("kscreen-doctor"), {QStringLiteral("-j")});
    }

private:
    static QString readFile(const QString &path)
    {
        QFile f(path);
        return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
    }

    QDBusPendingCall evaluate(const QString &script)
    {
        QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"),
                                                          QStringLiteral("org.kde.PlasmaShell"), QStringLiteral("evaluateScript"));
        msg << script;
        return bus().asyncCall(msg);
    }

    // Reshape the panels in up to three script calls plus an ordering pass (see morph-panels.js): Plasma has to lay the
    // panel out between them for "insert at the start" to land in the right place. A newer mode
    // switch cancels an unfinished chain.
    void morphPanels(bool tablet)
    {
        ++m_generation;
        runPhase(tablet, 1, m_generation, false);
    }

    void runPhase(bool tablet, int phase, int generation, bool rebuilt, int attempt = 0)
    {
        const QString dir = home + QStringLiteral("/.local/share/tablet-mode/");
        const QString prelude = QStringLiteral(
            "var TABLET = %1;\n"
            "var PHASE = %2;\n"
            "var HOME = %3;\n"
            // pinned apps: the live task manager's list, kept in tabletrc [Dock] launchers so it
            // survives the phases in which no task manager exists (dock removed, bar not built yet)
            "var LAUNCHERS = [];\n"
            "var FOUND = false;\n"
            "panels().forEach(function (p) { p.widgets().forEach(function (w) {\n"
            "  if (w.type == 'org.kde.plasma.icontasks') { w.currentConfigGroup = ['General'];\n"
            "    if (!FOUND) { FOUND = true; var raw = w.readConfig('launchers', []);\n"
            "      LAUNCHERS = Array.isArray(raw) ? raw : String(raw || '').split(',').filter(function (x) { return x; }); } } }); });\n"
            "var SAVED = ConfigFile('tabletrc', 'Dock');\n"
            "if (FOUND) SAVED.writeEntry('launchers', LAUNCHERS.join(','));\n"
            "else { var s = SAVED.readEntry('launchers'); if (s) LAUNCHERS = String(s).split(',').filter(function (x) { return x; }); }\n"
            "if (LAUNCHERS.length == 0 && !FOUND) LAUNCHERS = ['applications:firefox.desktop', 'applications:org.kde.dolphin.desktop',\n"
            "  'applications:typewriter.desktop', 'applications:org.kde.gwenview.desktop', 'applications:org.kde.okular.desktop',\n"
            "  'applications:org.kde.haruna.desktop', 'applications:systemsettings.desktop'];\n")
                                    .arg(tablet ? QStringLiteral("true") : QStringLiteral("false"))
                                    .arg(phase)
                                    .arg(QString::fromUtf8(QJsonDocument(QJsonArray{home}).toJson(QJsonDocument::Compact)).mid(1).chopped(1));
        const QString morph = readFile(dir + QStringLiteral("morph-panels.js"));
        if (morph.trimmed().isEmpty()) {
            return;
        }
        QString script = prelude + morph;
        if (phase == 1) {
            // home screen: iPad pages in tablet mode, DeX-style desktop icons in PC mode
            script += QStringLiteral("\ndesktops().forEach(function (d) { d.currentConfigGroup = ['General'];"
                                     " d.writeConfig('pcMode', %1); d.reloadConfig(); });\n")
                          .arg(tablet ? QStringLiteral("false") : QStringLiteral("true"));
        }
        auto *watcher = new QDBusPendingCallWatcher(evaluate(script), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [=, this] {
            QDBusPendingReply<QString> reply = *watcher;
            watcher->deleteLater();
            if (generation != m_generation) {
                return;
            }
            if (!reply.isValid()) {
                if (attempt < 3) {
                    QTimer::singleShot(1000 * (attempt + 1), this, [=, this] {
                        if (generation == m_generation) runPhase(tablet, phase, generation, rebuilt, attempt + 1);
                    });
                }
                return;
            }
            const QString out = reply.value();
            if (out.contains(QLatin1String("DONE"))) {
                modeReady();
                verifyPanels(generation);
                return;
            }
            if (out.contains(QLatin1String("REBUILD")) && !rebuilt && attempt < 5) {
                // at login plasmashell answers before its panels are loaded: "no panels" usually
                // only means "not yet". Rebuilding then breaks the panels it is still loading.
                QTimer::singleShot(2000, this, [=, this] {
                    if (generation == m_generation) {
                        runPhase(tablet, phase, generation, rebuilt, attempt + 1);
                    }
                });
                return;
            }
            if (out.contains(QLatin1String("REBUILD")) && !rebuilt) {
                // Bootstrap missing pieces without deleting unrelated or partially loaded panels.
                const QString layout = readFile(dir + QStringLiteral("layout-tablet.js"));
                if (layout.trimmed().isEmpty()) {
                    return;
                }
                auto *build = new QDBusPendingCallWatcher(evaluate(prelude + layout), this);
                connect(build, &QDBusPendingCallWatcher::finished, this, [=, this] {
                    QDBusPendingReply<QString> result = *build;
                    build->deleteLater();
                    if (generation != m_generation) return;
                    if (!result.isValid() || !result.value().contains(QLatin1String("BUILT"))) {
                        return;
                    }
                    QTimer::singleShot(300, this, [=, this] {
                        if (generation == m_generation) {
                            runPhase(tablet, 1, generation, true);
                        }
                    });
                });
                return;
            }
            if (out.contains(QLatin1String("REBUILD"))) {
                return;
            }
            if (phase == 9) {
                // still out of order: Plasma was busy, try again a little later (3 times)
                if (attempt < 3) {
                    QTimer::singleShot(1000, this, [=, this] {
                        if (generation == m_generation) {
                            runPhase(tablet, 9, generation, rebuilt, attempt + 1);
                        }
                    });
                } else {
                }
                return;
            }
            const int next = phase + 1;
            if (next <= (tablet ? 2 : 3)) {
                QTimer::singleShot(250, this, [=, this] {
                    if (generation == m_generation) {
                        runPhase(tablet, next, generation, rebuilt);
                    }
                });
            } else {
                // last phase done: fix the widget order once the panel is laid out
                QTimer::singleShot(500, this, [=, this] {
                    if (generation == m_generation) {
                        runPhase(tablet, 9, generation, rebuilt);
                    }
                });
            }
        });
    }

    // Ask KWin which windows plasmashell has right now. The answer comes back through PanelViews();
    // no answer within 3 s (KWin busy, scripting off) counts as "unknown" (-1, -1).
    void probeViews(std::function<void(int desktops, int panels)> done)
    {
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
        const QString path = (dir.isEmpty() ? QDir::tempPath() : dir) + QStringLiteral("/tabletd-panel-probe.js");
        QFile f(path);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            done(-1, -1);
            return;
        }
        f.write("var d = 0, p = 0;\n"
                "workspace.stackingOrder.forEach(function (w) {\n"
                "    if (w.resourceClass !== 'plasmashell') return;\n"
                "    if (w.desktopWindow) ++d; else if (w.dock) ++p;\n"
                "});\n"
                "callDBus('org.ipad.TabletD', '/', 'org.ipad.TabletD', 'PanelViews', d + ',' + p);\n");
        f.close();
        const int id = ++m_probeId;
        m_probe = std::move(done);
        const QString scripting = QStringLiteral("org.kde.kwin.Scripting");
        asyncCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), scripting, QStringLiteral("unloadScript"),
                  {QStringLiteral("tabletd-panel-probe")});
        asyncCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), scripting, QStringLiteral("loadScript"),
                  {path, QStringLiteral("tabletd-panel-probe")});
        asyncCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), scripting, QStringLiteral("start"));
        QTimer::singleShot(3000, this, [this, id] {
            if (id == m_probeId && m_probe) {
                auto late = std::move(m_probe);
                m_probe = nullptr;
                late(-1, -1);
            }
        });
    }

    // At login plasmashell is on the bus long before its desktop and panels are on screen.
    // Reshaping (or removing) panels while Plasma still creates their windows left a panel
    // without a window: the panel stayed in the config but never appeared until plasmashell
    // was restarted. So wait until KWin shows plasmashell's desktop, then a little longer.
    void waitForPlasma(int token, int attempt)
    {
        if (token != m_plasmaWait) {
            return;
        }
        probeViews([this, token, attempt](int desktops, int) {
            if (token != m_plasmaWait) {
                return;
            }
            if (desktops > 0 || attempt >= 40) {
                QTimer::singleShot(1500, this, [this, token] {
                    if (token == m_plasmaWait) checkMode("start");
                });
            } else {
                QTimer::singleShot(750, this, [this, token, attempt] { waitForPlasma(token, attempt + 1); });
            }
        });
    }

    // After the panels were reshaped: every panel on an existing screen must have a window.
    // If one has none (Plasma lost the view), only a plasmashell restart brings it back; at most
    // twice in 10 minutes so a Plasma that keeps failing is not restarted in a loop.
    void verifyPanels(int generation, int attempt = 0)
    {
        QTimer::singleShot(attempt == 0 ? 2500 : 2000, this, [this, generation, attempt] {
            if (generation != m_generation) {
                return;
            }
            auto *watcher = new QDBusPendingCallWatcher(evaluate(QStringLiteral(
                "print(panels().filter(function (p) { return p.screen >= 0 && p.screen < screenCount; }).length);")), this);
            connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, generation, attempt] {
                QDBusPendingReply<QString> reply = *watcher;
                watcher->deleteLater();
                if (generation != m_generation || !reply.isValid()) {
                    return;
                }
                bool ok = false;
                const int expected = reply.value().trimmed().toInt(&ok);
                if (!ok || expected <= 0) {
                    return;
                }
                probeViews([this, generation, attempt, expected](int desktops, int panels) {
                    if (generation != m_generation || desktops < 0 || panels >= expected) {
                        return;
                    }
                    // a panel that was just added may get its window a moment later
                    if (attempt < 2) {
                        verifyPanels(generation, attempt + 1);
                        return;
                    }
                    if (!m_restartClock.isValid() || m_restartClock.elapsed() > 10 * 60 * 1000) {
                        m_restartClock.start();
                        m_plasmaRestarts = 0;
                    }
                    if (m_plasmaRestarts >= 2) {
                        return;
                    }
                    ++m_plasmaRestarts;
                    QProcess::startDetached(QStringLiteral("systemctl"),
                                            {QStringLiteral("--user"), QStringLiteral("restart"), QStringLiteral("plasma-plasmashell.service")});
                });
            });
        });
    }

    void askTypewriter()
    {
        if (m_lastAsk.isValid() && m_lastAsk.elapsed() < 10000) {
            return;
        }
        if (processRunning("ghostwriter")) {
            return;
        }
        const bool offerTypewriter = setting("Modes", "askTypewriter", true);
        const bool offerCoding = setting("Modes", "askCoding", true);
        if (!offerTypewriter && !offerCoding) return;
        m_lastAsk.start();
        QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.Notifications"),
                                                          QStringLiteral("/org/freedesktop/Notifications"),
                                                          QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("Notify"));
        QStringList actions;
        if (offerTypewriter) actions << QStringLiteral("open") << T(QStringLiteral("Писать"))
                                     << QStringLiteral("new") << T(QStringLiteral("Новый сценарий"));
        if (offerCoding) actions << QStringLiteral("coding") << T(QStringLiteral("Открыть LazyVim"));
        msg << T(QStringLiteral("Режимы работы")) << uint(0) << QStringLiteral("applications-development")
            << T(QStringLiteral("Клавиатура подключена."))
            << T(QStringLiteral("Можно писать тексты или открыть LazyVim для программирования."))
            // shown even with Do Not Disturb on (it answers the keyboard being attached right now)
            << actions << QVariantMap{{QStringLiteral("urgency"), QVariant::fromValue(uchar(2))}} << 20000;
        auto *watcher = new QDBusPendingCallWatcher(bus().asyncCall(msg), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
            QDBusPendingReply<uint> r = *watcher;
            if (r.isValid()) {
                m_askId = r.value();
                // critical popups stay until closed: take it away after 20 s like a normal one
                const uint id = m_askId;
                QTimer::singleShot(20000, this, [id] {
                    asyncCall(QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("/org/freedesktop/Notifications"),
                              QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("CloseNotification"), {id});
                });
            }
            watcher->deleteLater();
        });
    }

    QElapsedTimer m_lastAsk;
    uint m_askId = 0;
    int m_generation = 0;
    QString m_external;
    QHash<QString, QSocketNotifier *> m_switches;   // SW_TABLET_MODE devices by node
    QString m_shownMode;     // last mode the animation showed
    QStringList m_trayPending; // tray app ids waiting to be hidden
    bool m_tablet = false;
    bool m_known = false;
    std::function<void(int, int)> m_probe; // waiting for PanelViews()
    int m_probeId = 0;
    int m_plasmaWait = 0;      // current waitForPlasma() run
    int m_plasmaRestarts = 0;  // panel-recovery restarts in the current 10 minutes
    QElapsedTimer m_restartClock;
};

// ---- Windows button -> Claude Desktop -----------------------------------------------------------

// Claude Desktop (single instance: starting it again brings the open window, or the one hidden in
// the tray, to the front); without it the button opens the app menu like the Win key
void openClaude()
{
    if (QStandardPaths::findExecutable(QStringLiteral("claude-desktop")).isEmpty()) {
        asyncCall(QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"), QStringLiteral("org.kde.PlasmaShell"),
                  QStringLiteral("activateLauncherMenu"));
        return;
    }
    QProcess::startDetached(QStringLiteral("claude-desktop"), {}, QDir::homePath());
}

// ---- power button ----------------------------------------------------------------------------

class PowerButton : public QObject
{
public:
    explicit PowerButton(QObject *parent)
        : QObject(parent)
    {
        m_hold.setSingleShot(true);
        m_hold.setInterval(700);
        connect(&m_hold, &QTimer::timeout, this, [this] {
            m_held = true;
            if (!setting("PowerButton", "holdMenu", true)) {
                return;
            }
            QProcess::startDetached(QStringLiteral("kscreen-doctor"), {QStringLiteral("--dpms"), QStringLiteral("on")});
            // Our only power menu. Never launch Plasma's logout prompt as a fallback.
            auto *watcher = new QDBusPendingCallWatcher(
                bus().asyncCall(QDBusMessage::createMethodCall(QStringLiteral("org.ipad.TabletShell"), QStringLiteral("/"),
                                                               QStringLiteral("org.ipad.TabletShell"), QStringLiteral("PowerMenu"))),
                this);
            connect(watcher, &QDBusPendingCallWatcher::finished, this, [watcher] {
                watcher->deleteLater();
                // If tablet-shell is not available, stay on the desktop. A duplicate
                // logout dialog must never be opened by this handler.
            });
        });
        connect(&m_retry, &QTimer::timeout, this, &PowerButton::tryOpen);
        m_retry.start(5000);
        tryOpen();
    }

    ~PowerButton() override
    {
        if (m_powerInhibitor >= 0) {
            ::close(m_powerInhibitor); // releases logind's low-level inhibitor
        }
        if (m_active) {
            setPlasmaPowerAction(1); // give the button back to Plasma (suspend)
        }
    }

private:
    void tryOpen()
    {
        // the GPIO (soc button) device is preferred: the ACPI button may report press+release at once
        QStringList devs = devicesWithKey(KEY_POWER, [](const QString &n) { return n.contains(QLatin1String("gpio"), Qt::CaseInsensitive); });
        if (devs.isEmpty()) {
            devs = devicesWithKey(KEY_POWER);
        }
        if (!m_reader.open(devs, [this](int fd, const input_event &ev) { onEvent(fd, ev); })) {
            return;
        }
        m_retry.stop();
        m_active = true;
        setPlasmaPowerAction(0); // PowerDevil: do nothing for short/long presses
        m_reader.grabDedicatedPowerKeys();
        // The logind inhibitor lives only while this handler is active. Unlike
        // editing /etc/systemd/logind.conf, it cannot break power management
        // after the tablet daemon exits or when another desktop is used.
        QDBusMessage req = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"),
            QStringLiteral("org.freedesktop.login1.Manager"), QStringLiteral("Inhibit"));
        req << QStringLiteral("handle-power-key") << QStringLiteral("tablet-shell")
            << QStringLiteral("Custom tablet power menu") << QStringLiteral("block");
        QDBusReply<QDBusUnixFileDescriptor> reply = QDBusConnection::systemBus().call(req, QDBus::Block, 2000);
        if (reply.isValid() && reply.value().isValid()) {
            m_powerInhibitor = ::dup(reply.value().fileDescriptor());
        }
    }

    void onEvent(int fd, const input_event &ev)
    {
        if (ev.type == EV_KEY && ev.code == KEY_LEFTMETA) {
            if (ev.value == 1) {
                hardwareMeta.start();
            } else if (ev.value == 0 && setting("Buttons", "windowsClaude", true)) {
                openClaude();
            }
            return;
        }
        if (ev.type != EV_KEY || ev.code != KEY_POWER) {
            return;
        }
        if (ev.value == 1 && m_pressedFd < 0 && (!m_lastPress.isValid() || m_lastPress.elapsed() > 300)) {
            // both buttons may report the same press; the device that started it ends it
            m_pressedFd = fd;
            m_held = false;
            m_lastPress.start();
            // read before KWin wakes the panel for this very key press
            m_panelWasOff = builtinPanelOff();
            m_hold.start();
        } else if (ev.value == 0 && fd == m_pressedFd) {
            m_pressedFd = -1;
            m_hold.stop();
            if (!m_held) {
                shortPress();
            }
        }
    }

    void shortPress()
    {
        const QString action = settingString("PowerButton", "tapAction", QStringLiteral("lock"));
        if (action == QLatin1String("nothing")) {
            return;
        }
        if (action == QLatin1String("suspend")) {
            QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"),
                                                              QStringLiteral("org.freedesktop.login1.Manager"), QStringLiteral("Suspend"));
            msg << true;
            QDBusConnection::systemBus().asyncCall(msg);
            return;
        }
        // locked: toggle the panel (dark -> on, lit lock screen -> off);
        // unlocked: lock, then turn the panel off (no blocking D-Bus call)
        const QString saver = QStringLiteral("org.freedesktop.ScreenSaver");
        const bool wasOff = m_panelWasOff;
        auto *watcher = new QDBusPendingCallWatcher(
            bus().asyncCall(QDBusMessage::createMethodCall(saver, QStringLiteral("/ScreenSaver"), saver, QStringLiteral("GetActive"))), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [watcher, saver, wasOff] {
            watcher->deleteLater();
            QDBusPendingReply<bool> locked = *watcher;
            if (locked.isValid() && locked.value()) {
                QProcess::startDetached(QStringLiteral("kscreen-doctor"), {QStringLiteral("--dpms"), wasOff ? QStringLiteral("on") : QStringLiteral("off")});
                return;
            }
            asyncCall(saver, QStringLiteral("/ScreenSaver"), saver, QStringLiteral("Lock"));
            // let the lock screen appear before the panel goes dark
            QTimer::singleShot(600, [] {
                QProcess::startDetached(QStringLiteral("kscreen-doctor"), {QStringLiteral("--dpms"), QStringLiteral("off")});
            });
        });
    }

    // built-in panel switched off (DPMS), from the DRM connector's sysfs state
    static bool builtinPanelOff()
    {
        const QDir drm(QStringLiteral("/sys/class/drm"));
        for (const QString &name : drm.entryList({QStringLiteral("card*-eDP-*")}, QDir::Dirs)) {
            QFile f(drm.filePath(name + QStringLiteral("/dpms")));
            if (f.open(QIODevice::ReadOnly) && f.readAll().trimmed() == "Off") {
                return true;
            }
        }
        return false;
    }

    // 0 = Plasma ignores the button (we handle it), 1 = suspend (fallback)
    static void setPlasmaPowerAction(int action)
    {
        KConfig cfg(QStringLiteral("powerdevilrc"), KConfig::SimpleConfig);
        for (const char *profile : {"AC", "Battery", "LowBattery"}) {
            cfg.group(QString::fromLatin1(profile)).group(QStringLiteral("SuspendAndShutdown")).writeEntry("PowerButtonAction", action);
        }
        cfg.sync();
        QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.Solid.PowerManagement"),
                                                          QStringLiteral("/org/kde/Solid/PowerManagement"),
                                                          QStringLiteral("org.kde.Solid.PowerManagement"),
                                                          QStringLiteral("reparseConfiguration"));
        bus().call(msg, QDBus::Block, 2000);
    }

    EvdevReader m_reader;
    int m_powerInhibitor = -1;
    QTimer m_retry;
    QTimer m_hold;
    QElapsedTimer m_lastPress;
    bool m_panelWasOff = false;
    int m_pressedFd = -1;
    bool m_held = false;
    bool m_active = false;
};

// ---- pen: palm rejection + Quick Note --------------------------------------------------------

class Pen : public QObject
{
public:
    explicit Pen(QObject *parent)
        : QObject(parent)
    {
        m_ring.setSingleShot(true);
        m_ring.setInterval(600);
        connect(&m_ring, &QTimer::timeout, this, [this] {
            if (!m_buttonDown || m_tipDown || !m_axes.contains(m_ringFd)) {
                return;
            }
            m_buttonDown = 0;       // the release does not run the quick action
            const auto &axes = m_axes[m_ringFd];
            asyncCall(QStringLiteral("org.ipad.TabletShell"), QStringLiteral("/"), QStringLiteral("org.ipad.TabletShell"), QStringLiteral("PenRing"),
                      {double(axes[ABS_X].pos) / axes[ABS_X].max, double(axes[ABS_Y].pos) / axes[ABS_Y].max});
        });
        m_release.setSingleShot(true);
        m_release.setInterval(600);
        connect(&m_release, &QTimer::timeout, this, [this] { setTouch(true); });
        connect(&m_retry, &QTimer::timeout, this, &Pen::tryOpen);
        m_retry.start(30000);   // fallback; new pens normally come with an input uevent
        new UeventWatcher("input", 1000, [this] { tryOpen(); }, this);
        tryOpen();
    }

    ~Pen() override
    {
        setTouch(true, true); // never leave the touchscreen disabled
    }

private:
    struct Axis {
        int max = 1;
        int pos = 0;
    };

    void tryOpen()
    {
        // every device with a pen or eraser tool: names differ a lot ("Wacom HID 5256 Pen",
        // "ELAN... Stylus", "IPTS 045E:..." on Surface, "GXTP7386..." Goodix, a separate "... Eraser"
        // node), so the capability decides, not the name. Called again when input devices change:
        // Bluetooth / USB pens and late drivers come after tabletd started.
        QStringList devs = devicesWithKey(BTN_TOOL_PEN);
        for (const QString &d : devicesWithKey(BTN_TOOL_RUBBER)) {
            if (!devs.contains(d)) {
                devs << d;
            }
        }
        // a pen that went away while near the screen never reports leaving: touch back on
        if (m_reader.fds().size() < m_penCount) {
            m_release.stop();
            setTouch(true);
        }
        const bool before = !m_reader.fds().isEmpty();
        const bool any = m_reader.open(devs, [this](int fd, const input_event &ev) { onEvent(fd, ev); });
        m_penCount = int(m_reader.fds().size());
        if (!any) {
            return;
        }
        // fd numbers are reused after a device went away: measure every open one again
        for (int fd : m_reader.fds()) {
            for (int axis : {ABS_X, ABS_Y}) {
                input_absinfo info{};
                ioctl(fd, EVIOCGABS(axis), &info);
                m_axes[fd][axis].max = info.maximum > 0 ? info.maximum : 1;
            }
        }
        if (!before) {
            setTouch(true, true);
        }
    }

    void onEvent(int fd, const input_event &ev)
    {
        auto &axes = m_axes[fd];
        if (ev.type == EV_ABS && (ev.code == ABS_X || ev.code == ABS_Y)) {
            axes[ev.code].pos = ev.value;
            // Quick Note: a stroke that started in the corner moved 10 % inwards
            if (m_strokeFd == fd && setting("Pen", "quickNote", true)
                && (m_strokeX - axes[ABS_X].pos > 0.10 * axes[ABS_X].max || m_strokeY - axes[ABS_Y].pos > 0.10 * axes[ABS_Y].max)) {
                m_strokeFd = -1;
                QProcess::startDetached(home + QStringLiteral("/.local/bin/quick-note"), {});
            }
        } else if (ev.type == EV_KEY && (ev.code == BTN_STYLUS || ev.code == BTN_STYLUS2)) {
            // Pen buttons pressed in the air (pen near the screen, tip up) and let go quickly:
            // tabletrc [Pen] button1 / button2 = quicknote | screenshot | nothing. With the tip
            // on the screen the button keeps its usual meaning (right click).
            // Held longer (0.6 s) the tool ring opens where the pen is ([Pen] toolRing).
            if (ev.value) {
                m_buttonDown = m_tipDown ? 0 : ev.code;
                m_buttonTimer.start();
                if (m_buttonDown && setting("Pen", "toolRing", true)) {
                    m_ringFd = fd;
                    m_ring.start();
                }
            } else if (m_buttonDown == ev.code && !m_tipDown && m_buttonTimer.elapsed() < 700) {
                m_ring.stop();
                m_buttonDown = 0;
                const bool first = ev.code == BTN_STYLUS;
                KConfig cfg(QStringLiteral("tabletrc"), KConfig::SimpleConfig);
                const QString action = cfg.group(QStringLiteral("Pen"))
                                           .readEntry(first ? "button1" : "button2", first ? QStringLiteral("quicknote") : QStringLiteral("screenshot"));
                if (action == QLatin1String("quicknote")) {
                    QProcess::startDetached(home + QStringLiteral("/.local/bin/quick-note"), {});
                } else if (action == QLatin1String("screenshot")) {
                    // the whole screen into Spectacle's editor, to draw on it
                    QProcess::startDetached(QStringLiteral("sh"), {QStringLiteral("-c"),
                        QStringLiteral("f=\"${XDG_RUNTIME_DIR:-/tmp}/pen-screenshot-$(date +%s).png\"; "
                                       "spectacle -b -n -f -o \"$f\" && spectacle --edit-existing \"$f\"")});
                }
            } else {
                m_buttonDown = 0;
                m_ring.stop();
            }
        } else if (ev.type == EV_KEY && ev.code == BTN_TOUCH) {
            m_tipDown = ev.value;
            if (ev.value) {
                m_buttonDown = 0;       // the tip went down: a normal button + tip use
                m_ring.stop();
            }
            const int x = axes[ABS_X].pos, y = axes[ABS_Y].pos;
            if (ev.value && x > 0.94 * axes[ABS_X].max && y > 0.94 * axes[ABS_Y].max) {
                m_strokeFd = fd;
                m_strokeX = x;
                m_strokeY = y;
            } else if (!ev.value) {
                m_strokeFd = -1;
            }
        } else if (ev.type == EV_KEY && (ev.code == BTN_TOOL_PEN || ev.code == BTN_TOOL_RUBBER)) {
            if (ev.value) {
                m_release.stop();
                if (setting("Pen", "palmRejection", true)) {
                    setTouch(false);
                }
            } else {
                m_release.start();
            }
        }
    }

    // Enable/disable every touchscreen in KWin (InputDevice "enabled" property)
    void setTouch(bool enabled, bool force = false)
    {
        if (!force && enabled == m_touchEnabled) {
            return;
        }
        m_touchEnabled = enabled;
        if (m_touchscreens.isEmpty()) {
            QDBusInterface mgr(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin/InputDevice"),
                               QStringLiteral("org.freedesktop.DBus.Properties"), bus());
            QDBusReply<QDBusVariant> names = mgr.call(QStringLiteral("Get"), QStringLiteral("org.kde.KWin.InputDeviceManager"),
                                                      QStringLiteral("devicesSysNames"));
            for (const QString &dev : names.value().variant().toStringList()) {
                QDBusInterface d(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin/InputDevice/") + dev,
                                 QStringLiteral("org.freedesktop.DBus.Properties"), bus());
                QDBusReply<QDBusVariant> touch = d.call(QStringLiteral("Get"), QStringLiteral("org.kde.KWin.InputDevice"), QStringLiteral("touch"));
                if (touch.isValid() && touch.value().variant().toBool()) {
                    m_touchscreens << dev;
                }
            }
        }
        for (const QString &dev : std::as_const(m_touchscreens)) {
            QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin/InputDevice/") + dev,
                                                              QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Set"));
            msg << QStringLiteral("org.kde.KWin.InputDevice") << QStringLiteral("enabled") << QVariant::fromValue(QDBusVariant(enabled));
            if (force) {
                bus().call(msg, QDBus::Block, 2000);
            } else {
                bus().asyncCall(msg);
            }
        }
    }

    EvdevReader m_reader;
    QTimer m_retry;
    QTimer m_release;
    QHash<int, std::array<Axis, 2>> m_axes;
    QStringList m_touchscreens;
    bool m_touchEnabled = true;
    int m_strokeFd = -1;
    bool m_tipDown = false;
    int m_penCount = 0;            // pen devices open at the last scan
    int m_buttonDown = 0;          // pen button pressed in the air (BTN_STYLUS / BTN_STYLUS2)
    QElapsedTimer m_buttonTimer;
    QTimer m_ring;                 // the button held: the tool ring
    int m_ringFd = -1;
    int m_strokeX = 0;
    int m_strokeY = 0;
};

// ---- weekly cleanup ----------------------------------------------------------------------------
// tabletrc [Cleanup] auto (on unless switched off): once a week `tablet-tools cleanup auto` (trash
// and thumbnails older than a month, crash reports), with a notification when it freed something.
// Checked every 6 hours, first 10 minutes after the start; the last run is [Cleanup] lastRun.

class Cleanup : public QObject
{
public:
    explicit Cleanup(QObject *parent)
        : QObject(parent)
    {
        connect(&m_timer, &QTimer::timeout, this, &Cleanup::check);
        m_timer.start(6 * 3600 * 1000);
        QTimer::singleShot(10 * 60 * 1000, this, &Cleanup::check);
    }

private:
    void check()
    {
        if (!setting("Cleanup", "auto", true)) {
            return;
        }
        const QDate last = QDate::fromString(settingString("Cleanup", "lastRun", QString()), Qt::ISODate);
        if (last.isValid() && last.daysTo(QDate::currentDate()) < 7) {
            return;
        }
        auto *p = new QProcess(this);
        connect(p, &QProcess::finished, this, [p] {
            p->deleteLater();
            const qint64 freed = QJsonDocument::fromJson(p->readAllStandardOutput()).object().value(QStringLiteral("freed")).toInteger();
            KConfig tabletrc(QStringLiteral("tabletrc"), KConfig::SimpleConfig);
            tabletrc.group(QStringLiteral("Cleanup")).writeEntry("lastRun", QDate::currentDate().toString(Qt::ISODate));
            tabletrc.sync();
            if (freed < 5 * 1000 * 1000) {
                return;
            }
            QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.Notifications"),
                                                              QStringLiteral("/org/freedesktop/Notifications"),
                                                              QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("Notify"));
            msg << T(QStringLiteral("Хранилище")) << uint(0) << QStringLiteral("drive-harddisk")
                << T(QStringLiteral("Автоочистка")) << T(QStringLiteral("Освобождено %1 МБ: корзина, миниатюры, отчёты о сбоях")).arg(freed / 1000000)
                << QStringList() << QVariantMap() << 8000;
            bus().asyncCall(msg);
        });
        p->start(home + QStringLiteral("/.local/bin/tablet-tools"), {QStringLiteral("cleanup"), QStringLiteral("auto")});
    }

    QTimer m_timer;
};

// ---- main ------------------------------------------------------------------------------------

static int signalPipe[2];

int main(int argc, char *argv[])
{
    // Keep Qt diagnostics silent without an app-local helper declaration.
    // TABLET_SHELL_DEBUG=1 keeps Qt/QML messages for troubleshooting
    if (!qEnvironmentVariableIsSet("TABLET_SHELL_DEBUG")) qInstallMessageHandler([](QtMsgType, const QMessageLogContext &, const QString &) {});
    QCoreApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("tabletd"));

    // quit cleanly on SIGTERM/SIGINT so the power button and touchscreen are handed back
    socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, signalPipe);
    auto handler = [](int) {
        char c = 1;
        (void)::write(signalPipe[0], &c, 1);
    };
    std::signal(SIGTERM, handler);
    std::signal(SIGINT, handler);
    QSocketNotifier sigNotifier(signalPipe[1], QSocketNotifier::Read);
    QObject::connect(&sigNotifier, &QSocketNotifier::activated, &app, &QCoreApplication::quit);

    // our KWin scripts name their shortcuts in the UI language (they cannot see the locale)
    {
        KConfig kwinrc(QStringLiteral("kwinrc"));
        for (const char *script : {"picture-in-picture", "slide-over", "split-view"}) {
            kwinrc.group(QStringLiteral("Script-") + QLatin1String(script)).writeEntry("russian", uiRussian());
        }
    }

    auto *modes = new ModeSwitcher(&app);
    QDBusConnection::sessionBus().registerService(QStringLiteral("org.ipad.TabletD"));
    QDBusConnection::sessionBus().registerObject(QStringLiteral("/"), modes, QDBusConnection::ExportScriptableSlots);
    auto *power = new PowerButton(&app);
    auto *pen = new Pen(&app);
    new Cleanup(&app);
    QObject::connect(&app, &QCoreApplication::aboutToQuit, [&] {
        delete pen;
        delete power;
        delete modes;
    });
    return app.exec();
}

#include "tabletd.moc"
