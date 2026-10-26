// tablet-tools: small helpers of the ThinkPad 10 setup in one binary (replaces Python scripts).
// Called through symlinks under the old names, so callers did not change:
//   webapp-create NAME URL | webapp-create --remove ID   home screen web apps (launcher + rounded icon)
//   wallpaper list | set PATH | live on|off | sync           wallpaper gallery for the home screen
//   screentime-apps ID...                                app names/icons (JSON) for screen time
//   dashboard [--force|--local]                          data of the dock dashboard (JSON; online part cached 5 min)
//   youtube-login                                        one-time Google sign-in for the YouTube Analytics API
//   today [--force]                                      Today page: Linux / Russia news, exchange rates, on this day
//   typewriter-stats | typewriter-export FILE FMT [OUT]  typewriter statistics, manuscript export (typewriter.cpp)
//   typewriter-runtime FILE                              running time of a screenplay (page ~ minute)
//   cleanup scan | run ID... | auto                      storage: sizes / clean up (tablet-settings «Хранилище»)
//   weekly                                               week report: screen time, words, battery vs the week before
//   app-icons [--force]                                  MacTahoe-style icons for apps the icon theme lacks (icons.cpp)
#include <KConfig>
#include <KConfigGroup>

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QDirIterator>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLinearGradient>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPainter>
#include <QPainterPath>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QTcpServer>
#include <QTcpSocket>
#include <QUrlQuery>
#include <QJsonArray>
#include <QDateTime>
#include <QXmlStreamReader>
#include <QRandomGenerator>
#include <QTextStream>
#include <QTimer>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <unistd.h>

#include "tr.h"
#include <QtCore/qlogging.h>

// typewriter (typewriter.cpp): words today, goal, streak, history
QJsonObject typewriterSummary();
int typewriterStatsCommand();
int typewriterWordsOn(const QDate &day);
int typewriterExportCommand(const QString &file, const QString &format, QString out);
int typewriterRuntimeCommand(const QString &file);
// app icons in the icon theme's style (icons.cpp)
int appIconsCommand(const QStringList &args);

namespace
{
const QString home = QDir::homePath();

QStringList appDirs()
{
    return {home + QStringLiteral("/.local/share/applications"), home + QStringLiteral("/.local/share/flatpak/exports/share/applications"),
            QStringLiteral("/var/lib/flatpak/exports/share/applications"), QStringLiteral("/usr/local/share/applications"),
            QStringLiteral("/usr/share/applications")};
}

void out(const QString &s)
{
    std::fputs(s.toUtf8().constData(), stdout);
}

// a small file (sysfs), empty if it cannot be read
QByteArray readFile(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
}

// ---- web apps --------------------------------------------------------------------------------

const QByteArray userAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36";

struct Fetched {
    QUrl finalUrl;
    QByteArray data;
    bool ok = false;
};

Fetched fetch(QNetworkAccessManager &net, const QUrl &url, qint64 limit = 2'000'000)
{
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, userAgent);
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setTransferTimeout(10000);
    QNetworkReply *reply = net.get(req);
    // A huge HTML page or icon must not fill RAM while the nested event loop
    // waits for completion. Abort above the caller's size limit.
    QObject::connect(reply, &QNetworkReply::downloadProgress, reply, [reply, limit](qint64 received, qint64) {
        if (received > limit) reply->abort();
    });
    QEventLoop loop;
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();
    Fetched f;
    f.finalUrl = reply->url();
    f.ok = reply->error() == QNetworkReply::NoError;
    f.data = reply->read(limit);
    reply->deleteLater();
    return f;
}

// Best icon of the page: apple-touch-icon first (made for tablets), then the largest <link rel=icon>,
// then /apple-touch-icon.png and /favicon.ico
QImage findIcon(QNetworkAccessManager &net, QUrl url)
{
    QList<QPair<int, QUrl>> candidates;
    const Fetched page = fetch(net, url);
    if (page.ok) {
        url = page.finalUrl;
        static const QRegularExpression linkRe(QStringLiteral("<link\\b[^>]*>"), QRegularExpression::CaseInsensitiveOption);
        static const QRegularExpression attrRe(QStringLiteral("([a-zA-Z-]+)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)"));
        const QString html = QString::fromUtf8(page.data);
        for (auto it = linkRe.globalMatch(html); it.hasNext();) {
            const QString tag = it.next().captured(0);
            QHash<QString, QString> attrs;
            for (auto a = attrRe.globalMatch(tag); a.hasNext();) {
                const auto m = a.next();
                QString v = m.captured(2);
                if (v.startsWith(QLatin1Char('"')) || v.startsWith(QLatin1Char('\''))) {
                    v = v.mid(1, v.size() - 2);
                }
                attrs.insert(m.captured(1).toLower(), v);
            }
            const QString rel = attrs.value(QStringLiteral("rel")).toLower();
            const QString href = attrs.value(QStringLiteral("href"));
            if (href.isEmpty() || !rel.contains(QLatin1String("icon"))) {
                continue;
            }
            int size = 0;
            static const QRegularExpression sizeRe(QStringLiteral("(\\d+)x\\d+"));
            for (auto s = sizeRe.globalMatch(attrs.value(QStringLiteral("sizes"))); s.hasNext();) {
                size = qMax(size, s.next().captured(1).toInt());
            }
            int score = (rel.contains(QLatin1String("apple-touch-icon")) ? 2 : 1) * 1000 + size;
            if (href.endsWith(QLatin1String(".svg")) || attrs.value(QStringLiteral("type")).contains(QLatin1String("svg"))) {
                score += 500;
            }
            candidates << qMakePair(score, url.resolved(QUrl(href)));
        }
        std::sort(candidates.begin(), candidates.end(), [](const auto &a, const auto &b) { return a.first > b.first; });
    }
    const QString root = url.scheme() + QStringLiteral("://") + url.authority();
    candidates << qMakePair(0, QUrl(root + QStringLiteral("/apple-touch-icon.png"))) << qMakePair(0, QUrl(root + QStringLiteral("/favicon.ico")));
    for (const auto &c : std::as_const(candidates)) {
        const Fetched f = fetch(net, c.second);
        QImage img;
        if (f.ok && f.data.size() >= 100 && img.loadFromData(f.data) && !img.isNull()) {
            return img;
        }
    }
    return {};
}

// iPadOS-style tile: rounded square, the site icon on white, or a coloured letter tile
QImage tile(const QImage &icon, const QString &name)
{
    const int size = 256;
    QImage out(size, size, QImage::Format_ARGB32_Premultiplied);
    out.fill(Qt::transparent);
    QPainter p(&out);
    p.setRenderHints(QPainter::Antialiasing | QPainter::SmoothPixmapTransform | QPainter::TextAntialiasing);
    QPainterPath shape;
    shape.addRoundedRect(QRectF(0, 0, size, size), 56, 56);
    p.setClipPath(shape);
    if (!icon.isNull()) {
        p.fillRect(out.rect(), Qt::white);
        const QImage scaled = icon.scaled(size, size, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        p.drawImage((size - scaled.width()) / 2, (size - scaled.height()) / 2, scaled);
    } else {
        const int hue = QCryptographicHash::hash(name.toUtf8(), QCryptographicHash::Md5).at(0) & 0xff;
        QLinearGradient g(0, 0, 0, size);
        g.setColorAt(0, QColor::fromHsl(hue * 360 / 256, 178, 148));
        g.setColorAt(1, QColor::fromHsl(hue * 360 / 256, 178, 107));
        p.fillRect(out.rect(), g);
        QFont font(QStringLiteral("Inter"));
        font.setPixelSize(140);
        font.setWeight(QFont::DemiBold);
        p.setFont(font);
        p.setPen(Qt::white);
        p.drawText(out.rect(), Qt::AlignCenter, name.trimmed().left(1).toUpper());
    }
    return out;
}

QString execQuote(const QString &s)
{
    QString q = s;
    q.replace(QLatin1Char('\\'), QStringLiteral("\\\\")).replace(QLatin1Char('"'), QStringLiteral("\\\""));
    q.replace(QLatin1Char('`'), QStringLiteral("\\`")).replace(QLatin1Char('$'), QStringLiteral("\\$")).replace(QLatin1Char('%'), QStringLiteral("%%"));
    return QLatin1Char('"') + q + QLatin1Char('"');
}

int webappCreate(const QString &name, QString url)
{
    static const QRegularExpression scheme(QStringLiteral("^[a-z]+://"));
    if (!scheme.match(url).hasMatch()) {
        url.prepend(QStringLiteral("https://"));
    }
    QString slug = name.toLower();
    slug.replace(QRegularExpression(QStringLiteral("[^a-z0-9]+")), QStringLiteral("-"));
    slug.remove(QRegularExpression(QStringLiteral("^-+|-+$")));
    if (slug.isEmpty()) {
        slug = QString::fromLatin1(QCryptographicHash::hash(url.toUtf8(), QCryptographicHash::Md5).toHex().left(8));
    }
    const QString id = QStringLiteral("webapp-") + slug;
    const QString icons = home + QStringLiteral("/.local/share/webapps/icons");
    const QString apps = home + QStringLiteral("/.local/share/applications");
    QDir().mkpath(icons);
    QDir().mkpath(apps);
    for (const QString &old : QDir(icons).entryList({id + QStringLiteral(".*")})) {
        QFile::remove(icons + QLatin1Char('/') + old);
    }

    QNetworkAccessManager net;
    const QString iconPath = icons + QLatin1Char('/') + id + QStringLiteral(".png");
    tile(findIcon(net, QUrl(url)), name).save(iconPath);

    QFile desktop(apps + QLatin1Char('/') + id + QStringLiteral(".desktop"));
    if (!desktop.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return 1;
    }
    QTextStream ts(&desktop);
    ts << "[Desktop Entry]\nType=Application\nName=" << name << "\nComment=Веб-приложение: " << url << "\n"
       << "Exec=" << execQuote(home + QStringLiteral("/.local/bin/webapp-runner")) << ' ' << execQuote(id) << ' ' << execQuote(name) << ' '
       << execQuote(url) << "\nIcon=" << iconPath << "\nCategories=Network;\nStartupWMClass=" << id << "\nX-WebApp-URL=" << url << "\n";
    desktop.close();
    QProcess::startDetached(QStringLiteral("kbuildsycoca6"), {});
    out(id + QLatin1Char('\n'));
    return 0;
}

int webappRemove(const QString &id)
{
    if (!id.startsWith(QLatin1String("webapp-")) || id.contains(QLatin1Char('/'))) {
        std::fputs("not a web app id\n", stderr);
        return 1;
    }
    QFile::remove(home + QStringLiteral("/.local/share/applications/") + id + QStringLiteral(".desktop"));
    const QString icons = home + QStringLiteral("/.local/share/webapps/icons");
    for (const QString &f : QDir(icons).entryList({id + QStringLiteral(".*")})) {
        QFile::remove(icons + QLatin1Char('/') + f);
    }
    QDir(home + QStringLiteral("/.local/share/") + id).removeRecursively();
    QDir(home + QStringLiteral("/.cache/") + id).removeRecursively();
    QProcess::startDetached(QStringLiteral("kbuildsycoca6"), {});
    return 0;
}

// ---- wallpapers ------------------------------------------------------------------------------

int wallpaperList()
{
    QSet<QString> seen;
    for (const QString &base : {home + QStringLiteral("/.local/share/wallpapers"), QStringLiteral("/usr/share/wallpapers")}) {
        auto packages = QDir(base).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        // same order as before: by "name/" (so "WhiteSur-dark" comes before "WhiteSur")
        std::sort(packages.begin(), packages.end(), [](const QFileInfo &a, const QFileInfo &b) {
            return (a.fileName() + QLatin1Char('/')).toUtf8() < (b.fileName() + QLatin1Char('/')).toUtf8();
        });
        for (const QFileInfo &pkg : packages) {
            if (seen.contains(pkg.fileName())) {
                continue;
            }
            QString thumb;
            for (const char *shot : {"contents/screenshot.png", "contents/screenshot.jpg"}) {
                if (QFile::exists(pkg.filePath() + QLatin1Char('/') + QLatin1String(shot))) {
                    thumb = pkg.filePath() + QLatin1Char('/') + QLatin1String(shot);
                    break;
                }
            }
            if (thumb.isEmpty()) {
                // smallest image of the package loads fastest
                const auto images = QDir(pkg.filePath() + QStringLiteral("/contents/images")).entryInfoList(QDir::Files, QDir::Size | QDir::Reversed);
                if (!images.isEmpty()) {
                    thumb = images.first().filePath();
                }
            }
            if (!thumb.isEmpty()) {
                seen.insert(pkg.fileName());
                out(pkg.filePath() + QLatin1Char('\t') + thumb + QLatin1Char('\n'));
            }
        }
    }
    static const QStringList ext = {QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"), QStringLiteral("*.png"), QStringLiteral("*.webp"),
                                    QStringLiteral("*.jxl"), QStringLiteral("*.avif")};
    for (const QString &base : {home + QStringLiteral("/Pictures"), home + QStringLiteral("/Pictures/Wallpapers"), home + QStringLiteral("/Изображения"),
                                home + QStringLiteral("/Downloads")}) {
        QDir dir(base);
        dir.setNameFilters(ext);
        for (const QFileInfo &f : dir.entryInfoList(QDir::Files, QDir::Name | QDir::IgnoreCase)) {
            if (!seen.contains(f.filePath())) {
                seen.insert(f.filePath());
                out(f.filePath() + QLatin1Char('\t') + f.filePath() + QLatin1Char('\n'));
            }
        }
    }
    return 0;
}

// The built-in screen: the first connected eDP / DSI / LVDS connector, as its output name (eDP-1)
// and native mode (the first line of "modes"). Empty when the device has none.
struct Panel {
    QString output;
    QSize size;
};
Panel internalPanel()
{
    const QDir drm(QStringLiteral("/sys/class/drm"));
    for (const QString &c : drm.entryList({QStringLiteral("card*-eDP-*"), QStringLiteral("card*-DSI-*"), QStringLiteral("card*-LVDS-*")}, QDir::Dirs)) {
        if (readFile(drm.filePath(c + QStringLiteral("/status"))).trimmed() != "connected") {
            continue;
        }
        const QList<QByteArray> mode = readFile(drm.filePath(c + QStringLiteral("/modes"))).split('\n').value(0).split('x');
        return {c.section(QLatin1Char('-'), 1), QSize(mode.value(0).toInt(), mode.value(1).toInt())};
    }
    return {};
}

// What this device has, for the settings and the control center to hide what cannot work:
//   tablet-tools hardware -> {"model", "internalOutput", "pen", "windowsButton", "lightSensor",
//                             "waydroid", "chargeThreshold"}
QString sysName(const QString &path)
{
    return QString::fromUtf8(readFile(path)).trimmed();
}
int hardware()
{
    // model: ThinkPads keep the marketing name in product_version, most others in product_name
    QString model = sysName(QStringLiteral("/sys/class/dmi/id/product_version"));
    static const QStringList junk{QStringLiteral("System Version"), QStringLiteral("To be filled"), QStringLiteral("Default"),
                                  QStringLiteral("None"), QStringLiteral("Not Applicable")};
    if (model.isEmpty() || std::any_of(junk.begin(), junk.end(), [&](const QString &j) { return model.contains(j, Qt::CaseInsensitive); })) {
        model = sysName(QStringLiteral("/sys/class/dmi/id/product_name"));
    }
    bool pen = false, windowsButton = false;
    const QDir input(QStringLiteral("/sys/class/input"));
    for (const QString &e : input.entryList({QStringLiteral("input*")})) {
        const QString dir = input.filePath(e);
        const QString name = sysName(dir + QStringLiteral("/name"));
        const QList<QByteArray> keys = readFile(dir + QStringLiteral("/capabilities/key")).trimmed().split(' ');
        auto hasKey = [&](int code) {
            const int word = code / 64;
            if (word >= keys.size()) {
                return false;
            }
            return (keys[keys.size() - 1 - word].toULongLong(nullptr, 16) >> (code % 64) & 1) != 0;
        };
        pen = pen || hasKey(0x140 /* BTN_TOOL_PEN */);
        // a Windows/home button below the screen: KEY_LEFTMETA on the built-in button device
        windowsButton = windowsButton || (name == QLatin1String("gpio-keys") && hasKey(125 /* KEY_LEFTMETA */));
    }
    bool lightSensor = false;
    const QDir iio(QStringLiteral("/sys/bus/iio/devices"));
    for (const QString &d : iio.entryList({QStringLiteral("iio:device*")})) {
        lightSensor = lightSensor || !QDir(iio.filePath(d)).entryList({QStringLiteral("in_illuminance*")}).isEmpty();
    }
    bool chargeThreshold = false;
    const QDir power(QStringLiteral("/sys/class/power_supply"));
    for (const QString &b : power.entryList({QStringLiteral("BAT*")})) {
        chargeThreshold = chargeThreshold || QFile::exists(power.filePath(b + QStringLiteral("/charge_control_end_threshold")));
    }
    const QJsonObject o{{QStringLiteral("model"), model},
                        {QStringLiteral("internalOutput"), internalPanel().output},
                        {QStringLiteral("pen"), pen},
                        {QStringLiteral("windowsButton"), windowsButton},
                        {QStringLiteral("lightSensor"), lightSensor},
                        {QStringLiteral("waydroid"), !QStandardPaths::findExecutable(QStringLiteral("waydroid")).isEmpty()},
                        {QStringLiteral("chargeThreshold"), chargeThreshold}};
    out(QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact)) + QLatin1Char('\n'));
    return 0;
}

// The login screen (tablet-greeter) shows the same picture as the home and lock screens: a
// screen-sized copy it can read, in the light or dark variant of the current appearance.
void syncGreeterWallpaper()
{
    const QString greeterWallpaper = QStringLiteral("/var/lib/tablet-greeter/wallpaper.jpg");
    if (!QFileInfo(greeterWallpaper).isWritable()) {
        return;
    }
    KConfig locker(QStringLiteral("kscreenlockerrc"));
    QString image = QUrl(locker.group(QStringLiteral("Greeter")).group(QStringLiteral("Wallpaper")).group(QStringLiteral("org.kde.image"))
                             .group(QStringLiteral("General")).readEntry("Image", QString())).toLocalFile();
    if (image.endsWith(QLatin1Char('/'))) {
        image.chop(1);
    }
    if (QFileInfo(image).isDir()) {
        // wallpaper package: its largest image, images_dark/ when the dark look is active (the
        // live wallpaper follows the theme too)
        KConfig globals(QStringLiteral("kdeglobals"));
        const QString look = globals.group(QStringLiteral("KDE")).readEntry("LookAndFeelPackage", QString());
        const QString scheme = globals.group(QStringLiteral("General")).readEntry("ColorScheme", QString());
        const bool dark = look.isEmpty() ? scheme.contains(QLatin1String("dark"), Qt::CaseInsensitive)
                                         : !(look == QLatin1String("org.ipad.light") || look == QLatin1String("org.tabletshell.pixel.light"));
        QFileInfoList files;
        if (dark) {
            files = QDir(image + QStringLiteral("/contents/images_dark")).entryInfoList(QDir::Files, QDir::Size);
        }
        if (files.isEmpty()) {
            files = QDir(image + QStringLiteral("/contents/images")).entryInfoList(QDir::Files, QDir::Size);
        }
        image = files.isEmpty() ? QString() : files.first().absoluteFilePath();
    }
    // the watcher calls this on every kdeglobals change: skip when the source did not change
    const QString stampFile = QDir::homePath() + QStringLiteral("/.cache/greeter-wallpaper.stamp");
    const QString stamp = image + QLatin1Char(' ') + QString::number(QFileInfo(image).lastModified().toSecsSinceEpoch());
    QFile stampIn(stampFile);
    if (stampIn.open(QIODevice::ReadOnly) && QString::fromUtf8(stampIn.readAll()) == stamp && QFileInfo(greeterWallpaper).size() > 0) {
        return;
    }
    QImage img(image);
    if (!img.isNull()) {
        QFile stampOut(stampFile);
        if (stampOut.open(QIODevice::WriteOnly)) {
            stampOut.write(stamp.toUtf8());
        }
        const QSize screen = internalPanel().size;
        img.scaled(screen.isValid() && !screen.isEmpty() ? screen : QSize(1920, 1080), Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation)
            .save(greeterWallpaper, "JPG", 90);
    }
}

// "Живые обои" (tabletrc [Appearance] liveWallpaper, on by default): a wallpaper package with a
// dark variant is shown with the org.ipad.daynight plugin, which cross-fades light and dark with
// the theme, on the home screens and the lock screen; anything else with Plasma's image plugin.
bool liveWallpaperWanted(const QString &abs)
{
    KConfig rc(QStringLiteral("tabletrc"), KConfig::SimpleConfig);
    return rc.group(QStringLiteral("Appearance")).readEntry("liveWallpaper", true) && QFileInfo(abs).isDir()
        && QDir(abs + QStringLiteral("/contents/images_dark")).exists();
}

void applyLiveWallpaper(const QString &abs)
{
    const QString url = QStringLiteral("file://") + abs;
    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"),
                                                      QStringLiteral("org.kde.PlasmaShell"), QStringLiteral("evaluateScript"));
    msg << QStringLiteral("desktops().forEach(function (d) { d.wallpaperPlugin = 'org.ipad.daynight';"
                          " d.currentConfigGroup = ['Wallpaper', 'org.ipad.daynight', 'General'];"
                          " d.writeConfig('Image', '%1'); d.reloadConfig(); });").arg(url);
    QDBusConnection::sessionBus().call(msg, QDBus::Block, 15000);
}

int wallpaperSet(const QString &path)
{
    const QString abs = QFileInfo(path).absoluteFilePath();
    const bool live = liveWallpaperWanted(abs);
    if (live) {
        applyLiveWallpaper(abs);
    } else {
        QProcess::execute(QStringLiteral("plasma-apply-wallpaperimage"), {abs});
    }
    {
        KConfig rc(QStringLiteral("tabletrc"), KConfig::SimpleConfig);
        const QString style = rc.group(QStringLiteral("Appearance")).readEntry(QStringLiteral("shellStyle"), QStringLiteral("apple"));
        rc.group(QStringLiteral("Appearance")).writeEntry(style == QLatin1String("pixel") ? QStringLiteral("pixelWallpaper") : QStringLiteral("appleWallpaper"), abs);

        KConfig locker(QStringLiteral("kscreenlockerrc"));
        KConfigGroup greeter = locker.group(QStringLiteral("Greeter"));
        const QString url = QStringLiteral("file://") + abs + (QFileInfo(abs).isDir() ? QStringLiteral("/") : QString());
        // the image plugin's entry stays the reference for the login screen copy (syncGreeterWallpaper)
        greeter.group(QStringLiteral("Wallpaper")).group(QStringLiteral("org.kde.image")).group(QStringLiteral("General")).writeEntry("Image", url);
        greeter.group(QStringLiteral("Wallpaper")).group(QStringLiteral("org.ipad.daynight")).group(QStringLiteral("General")).writeEntry("Image", url);
        greeter.writeEntry("WallpaperPlugin", live ? QStringLiteral("org.ipad.daynight") : QStringLiteral("org.kde.image"));
    }
    syncGreeterWallpaper();
    return 0;
}

// wallpaper live on|off: switch the current wallpaper between the live and the plain plugin
int wallpaperLive(bool on)
{
    {
        KConfig rc(QStringLiteral("tabletrc"), KConfig::SimpleConfig);
        rc.group(QStringLiteral("Appearance")).writeEntry("liveWallpaper", on);
    }
    KConfig locker(QStringLiteral("kscreenlockerrc"));
    QString image = QUrl(locker.group(QStringLiteral("Greeter")).group(QStringLiteral("Wallpaper")).group(QStringLiteral("org.kde.image"))
                             .group(QStringLiteral("General")).readEntry("Image", QString())).toLocalFile();
    if (image.endsWith(QLatin1Char('/'))) {
        image.chop(1);
    }
    return image.isEmpty() ? 1 : wallpaperSet(image);
}

// ---- screen time app names -------------------------------------------------------------------

QJsonObject desktopEntry(const QString &path)
{
    QFile f(path);
    QJsonObject o;
    if (!f.open(QIODevice::ReadOnly)) {
        return o;
    }
    const QString lang = qEnvironmentVariable("LANG", QStringLiteral("en")).section(QLatin1Char('.'), 0, 0);
    QString name, localName, shortName, icon;
    bool inEntry = false;
    for (const QByteArray &raw : f.readAll().split('\n')) {
        const QString line = QString::fromUtf8(raw).trimmed();
        if (line.startsWith(QLatin1Char('['))) {
            inEntry = line == QLatin1String("[Desktop Entry]");
            continue;
        }
        if (!inEntry) {
            continue;
        }
        const int eq = line.indexOf(QLatin1Char('='));
        if (eq < 0) {
            continue;
        }
        const QString key = line.left(eq).trimmed(), value = line.mid(eq + 1).trimmed();
        if (key == QLatin1String("Name")) {
            name = value;
        } else if (key == QStringLiteral("Name[%1]").arg(lang)) {
            localName = value;
        } else if (key == QStringLiteral("Name[%1]").arg(lang.left(2))) {
            shortName = value;
        } else if (key == QLatin1String("Icon")) {
            icon = value;
        }
    }
    o[QStringLiteral("name")] = !localName.isEmpty() ? localName : (!shortName.isEmpty() ? shortName : name);
    o[QStringLiteral("icon")] = icon;
    return o;
}

QJsonObject lookupApp(const QString &id)
{
    for (const QString &d : appDirs()) {
        for (const QString &cand : {d + QLatin1Char('/') + id + QStringLiteral(".desktop"), d + QLatin1Char('/') + id.toLower() + QStringLiteral(".desktop")}) {
            if (QFile::exists(cand)) {
                return desktopEntry(cand);
            }
        }
    }
    // window class only: a desktop file named *.<id> or with StartupWMClass=<id>
    for (const QString &d : appDirs()) {
        for (const QFileInfo &f : QDir(d).entryInfoList({QStringLiteral("*.desktop")}, QDir::Files)) {
            if (f.completeBaseName().toLower().endsWith(QLatin1Char('.') + id.toLower())) {
                return desktopEntry(f.filePath());
            }
            QFile file(f.filePath());
            if (file.open(QIODevice::ReadOnly) && file.readAll().contains(QByteArray("StartupWMClass=") + id.toUtf8())) {
                return desktopEntry(f.filePath());
            }
        }
    }
    return {{QStringLiteral("name"), id}, {QStringLiteral("icon"), id.toLower()}};
}

int screentimeApps(const QStringList &ids)
{
    QJsonObject result;
    for (const QString &id : ids) {
        result[id] = lookupApp(id);
    }
    out(QString::fromUtf8(QJsonDocument(result).toJson(QJsonDocument::Compact)) + QLatin1Char('\n'));
    return 0;
}

// ---- dock dashboard ----------------------------------------------------------------------------
// Claude plan limits come from the endpoint Claude Code's /usage uses (its own OAuth token).
// YouTube subscribers come from the YouTube Analytics API (exact, like YouTube Studio): lifetime
// subscribersGained - subscribersLost of the signed-in channel. Analytics lags ~2 days, so the
// gains of the last days are not in it yet. Google sign-in: `tablet-tools youtube-login` with an
// OAuth client ("Desktop app") saved as ~/.config/tablet-dashboard/google-client.json.

struct Response {
    int status = 0;
    QByteArray data;
};

Response request(QNetworkAccessManager &net, QNetworkRequest req, const QByteArray &post = {})
{
    req.setTransferTimeout(15000);
    QNetworkReply *reply = post.isNull() ? net.get(req) : net.post(req, post);
    QEventLoop loop;
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();
    Response r;
    r.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    r.data = reply->readAll();
    reply->deleteLater();
    return r;
}

QJsonObject readJson(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(f.readAll()).object() : QJsonObject();
}

bool writePrivateJson(const QString &path, const QJsonObject &o)
{
    QDir().mkpath(QFileInfo(path).path());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }
    f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    f.write(QJsonDocument(o).toJson(QJsonDocument::Compact));
    return true;
}

const QString googleClientPath = home + QStringLiteral("/.config/tablet-dashboard/google-client.json");
const QString googleTokenPath = home + QStringLiteral("/.local/share/tablet-dashboard/google-token.json");
const QString dashboardCache = home + QStringLiteral("/.cache/tablet-dashboard.json");

QJsonObject googleClient()
{
    const QJsonObject o = readJson(googleClientPath);
    return o.value(QStringLiteral("installed")).toObject().isEmpty() ? o.value(QStringLiteral("web")).toObject()
                                                                     : o.value(QStringLiteral("installed")).toObject();
}

QJsonObject claudeUsage(QNetworkAccessManager &net)
{
    const QJsonObject creds = readJson(home + QStringLiteral("/.claude/.credentials.json")).value(QStringLiteral("claudeAiOauth")).toObject();
    const QString token = creds.value(QStringLiteral("accessToken")).toString();
    if (token.isEmpty()) {
        return {{QStringLiteral("error"), T(QStringLiteral("нет входа в Claude Code"))}};
    }
    QNetworkRequest req(QUrl(QStringLiteral("https://api.anthropic.com/api/oauth/usage")));
    req.setRawHeader("Authorization", "Bearer " + token.toUtf8());
    req.setRawHeader("anthropic-beta", "oauth-2025-04-20");
    const Response r = request(net, req);
    if (r.status != 200) {
        return {{QStringLiteral("error"), r.status == 401 ? T(QStringLiteral("откройте Claude Code, чтобы обновить вход"))
                                                          : T(QStringLiteral("нет связи (%1)")).arg(r.status)}};
    }
    const QJsonObject u = QJsonDocument::fromJson(r.data).object();
    auto limit = [&](const char *key) {
        const QJsonObject l = u.value(QLatin1String(key)).toObject();
        return QJsonObject{{QStringLiteral("percent"), l.value(QStringLiteral("utilization")).toDouble()},
                           {QStringLiteral("resetsAt"), l.value(QStringLiteral("resets_at")).toString()}};
    };
    QJsonObject out{{QStringLiteral("session"), limit("five_hour")}, {QStringLiteral("weekly"), limit("seven_day")},
                    {QStringLiteral("plan"), creds.value(QStringLiteral("subscriptionType")).toString()}};
    if (u.value(QStringLiteral("seven_day_opus")).isObject()) {
        out.insert(QStringLiteral("weeklyOpus"), limit("seven_day_opus"));
    }
    return out;
}

QString googleAccessToken(QNetworkAccessManager &net, QString *error)
{
    QJsonObject token = readJson(googleTokenPath);
    if (token.value(QStringLiteral("refresh_token")).toString().isEmpty()) {
        *error = T(QStringLiteral("не подключено"));
        return {};
    }
    if (QDateTime::currentSecsSinceEpoch() < token.value(QStringLiteral("expires_at")).toInteger() - 60) {
        return token.value(QStringLiteral("access_token")).toString();
    }
    const QJsonObject client = googleClient();
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("client_id"), client.value(QStringLiteral("client_id")).toString());
    q.addQueryItem(QStringLiteral("client_secret"), client.value(QStringLiteral("client_secret")).toString());
    q.addQueryItem(QStringLiteral("refresh_token"), token.value(QStringLiteral("refresh_token")).toString());
    q.addQueryItem(QStringLiteral("grant_type"), QStringLiteral("refresh_token"));
    QNetworkRequest req(QUrl(QStringLiteral("https://oauth2.googleapis.com/token")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/x-www-form-urlencoded"));
    const Response r = request(net, req, q.query(QUrl::FullyEncoded).toUtf8());
    const QJsonObject fresh = QJsonDocument::fromJson(r.data).object();
    if (r.status != 200 || fresh.value(QStringLiteral("access_token")).toString().isEmpty()) {
        *error = r.status == 400 ? T(QStringLiteral("вход истёк, запустите youtube-setup")) : T(QStringLiteral("нет связи с Google (%1)")).arg(r.status);
        return {};
    }
    token.insert(QStringLiteral("access_token"), fresh.value(QStringLiteral("access_token")));
    token.insert(QStringLiteral("expires_at"), QDateTime::currentSecsSinceEpoch() + fresh.value(QStringLiteral("expires_in")).toInt(3600));
    writePrivateJson(googleTokenPath, token);
    return token.value(QStringLiteral("access_token")).toString();
}

QJsonObject youtubeStats(QNetworkAccessManager &net)
{
    QString error;
    const QString access = googleAccessToken(net, &error);
    if (access.isEmpty()) {
        return {{QStringLiteral("error"), error}};
    }
    auto get = [&](const QString &url) {
        QNetworkRequest req{QUrl(url)};
        req.setRawHeader("Authorization", "Bearer " + access.toUtf8());
        return request(net, req);
    };
    const Response ch = get(QStringLiteral("https://www.googleapis.com/youtube/v3/channels?part=snippet,statistics&mine=true"));
    const QJsonObject channel = QJsonDocument::fromJson(ch.data).object().value(QStringLiteral("items")).toArray().at(0).toObject();
    if (ch.status != 200 || channel.isEmpty()) {
        if (ch.data.contains("accessNotConfigured")) {
            return {{QStringLiteral("error"), T(QStringLiteral("API YouTube не включены в проекте Google"))}, {QStringLiteral("fix"), QStringLiteral("enable-apis")}};
        }
        if (ch.status == 200) {
            return {{QStringLiteral("error"), T(QStringLiteral("у этого аккаунта Google нет канала"))}};
        }
        return {{QStringLiteral("error"), QStringLiteral("YouTube API: %1").arg(ch.status)}};
    }
    const QJsonObject snippet = channel.value(QStringLiteral("snippet")).toObject();
    QJsonObject out{{QStringLiteral("title"), snippet.value(QStringLiteral("title"))},
                    {QStringLiteral("rounded"), channel.value(QStringLiteral("statistics")).toObject().value(QStringLiteral("subscriberCount")).toString().toLongLong()},
                    {QStringLiteral("views"), channel.value(QStringLiteral("statistics")).toObject().value(QStringLiteral("viewCount")).toString().toLongLong()}};
    // net subscribers over a date range from YouTube Analytics
    auto net_ = [&](const QDate &from) -> QJsonValue {
        const Response r = get(QStringLiteral("https://youtubeanalytics.googleapis.com/v2/reports?ids=channel==MINE&startDate=%1&endDate=%2"
                                              "&metrics=subscribersGained,subscribersLost")
                                   .arg(from.toString(Qt::ISODate), QDate::currentDate().toString(Qt::ISODate)));
        const QJsonArray row = QJsonDocument::fromJson(r.data).object().value(QStringLiteral("rows")).toArray().at(0).toArray();
        if (r.status != 200) {
            return QJsonValue();
        }
        return row.isEmpty() ? 0 : row.at(0).toInteger() - row.at(1).toInteger();
    };
    const QDate created = QDateTime::fromString(snippet.value(QStringLiteral("publishedAt")).toString(), Qt::ISODate).date();
    const QJsonValue total = net_(created.isValid() ? created : QDate(2005, 2, 14));
    if (total.isUndefined() || total.isNull()) {
        out.insert(QStringLiteral("error"), T(QStringLiteral("YouTube Analytics API недоступен")));
    } else {
        out.insert(QStringLiteral("subscribers"), total);
        out.insert(QStringLiteral("last28"), net_(QDate::currentDate().addDays(-28)));
    }
    return out;
}

QByteArray readProc(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
}

// Android (Waydroid): the session is a user-owned "python3 /usr/bin/waydroid ..." process (the
// container service runs as root); its memory is the RSS of everything in the lxc cgroup
QJsonObject androidState()
{
    bool session = false;
    qint64 rssPages = 0;
    const auto pids = QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &pid : pids) {
        if (!pid.at(0).isDigit()) {
            continue;
        }
        const QString dir = QStringLiteral("/proc/") + pid;
        if (readProc(dir + QStringLiteral("/cgroup")).contains("lxc.payload.waydroid")) {
            rssPages += readProc(dir + QStringLiteral("/statm")).split(' ').value(1).toLongLong();
            continue;
        }
        const QByteArray cmd = readProc(dir + QStringLiteral("/cmdline"));
        static constexpr char waydroid[] = "python3\0/usr/bin/waydroid"; // argv[0] NUL argv[1]
        if (cmd.startsWith(QByteArrayView(waydroid, sizeof(waydroid) - 1)) && !cmd.contains("container")
            && QFileInfo(dir).ownerId() == getuid()) {
            session = true;
        }
    }
    return {{QStringLiteral("running"), session || rssPages > 0}, {QStringLiteral("rss"), rssPages * sysconf(_SC_PAGESIZE)}};
}

// zram swap: original data stored, compressed size, memory used (mm_stat columns 1-3)
QJsonObject zramState()
{
    const QList<QByteArray> f = readProc(QStringLiteral("/sys/block/zram0/mm_stat")).simplified().split(' ');
    if (f.size() < 3) {
        return {};
    }
    return {{QStringLiteral("data"), f[0].toLongLong()}, {QStringLiteral("compressed"), f[1].toLongLong()},
            {QStringLiteral("used"), f[2].toLongLong()},
            {QStringLiteral("size"), readProc(QStringLiteral("/sys/block/zram0/disksize")).trimmed().toLongLong()}};
}

// screen time today: total and the top apps with their names
QJsonObject screenTimeToday()
{
    const QJsonObject day = readJson(home + QStringLiteral("/.local/share/screentime/") + QDate::currentDate().toString(Qt::ISODate) + QStringLiteral(".json"));
    QList<QPair<int, QString>> apps;
    int total = 0;
    for (auto it = day.begin(); it != day.end(); ++it) {
        const int secs = it.value().toInt();
        total += secs;
        apps.append({secs, it.key()});
    }
    std::sort(apps.begin(), apps.end(), [](const auto &a, const auto &b) { return a.first > b.first; });
    QJsonArray top;
    for (int i = 0; i < qMin(4, int(apps.size())); ++i) {
        const QJsonObject info = lookupApp(apps[i].second);
        top.append(QJsonObject{{QStringLiteral("name"), info.value(QStringLiteral("name")).toString(apps[i].second)},
                               {QStringLiteral("icon"), info.value(QStringLiteral("icon"))},
                               {QStringLiteral("seconds"), apps[i].first}});
    }
    return {{QStringLiteral("total"), total}, {QStringLiteral("top"), top}};
}

// local, always fresh (ksystemstats does not see the btrfs root)
QJsonObject withLocal(QJsonObject o)
{
    const QStorageInfo disk(home);
    o.insert(QStringLiteral("disk"), QJsonObject{{QStringLiteral("free"), disk.bytesAvailable()}, {QStringLiteral("total"), disk.bytesTotal()}});
    o.insert(QStringLiteral("zram"), zramState());
    o.insert(QStringLiteral("android"), androidState());
    o.insert(QStringLiteral("screentime"), screenTimeToday());
    o.insert(QStringLiteral("typewriter"), typewriterSummary());
    return o;
}

// ---- storage cleanup ---------------------------------------------------------------------------
// What can go: the trash, caches that rebuild themselves, old downloads (moved to the trash, not
// deleted) and pacman's package cache (pkexec, so it is only measured here; the settings page runs
// it). `auto` (weekly from tabletd) only empties what is old: trash and thumbnails older than 30
// days, crash reports.

qint64 sizeOf(const QString &path, qint64 olderThanSecs = -1)
{
    const QFileInfo top(path);
    if (!top.exists() && !top.isSymLink()) {
        return 0;
    }
    if (!top.isDir() || top.isSymLink()) {
        return top.size();
    }
    const QDateTime cut = QDateTime::currentDateTime().addSecs(-olderThanSecs);
    qint64 total = 0;
    QDirIterator it(path, QDir::Files | QDir::Hidden | QDir::System | QDir::NoSymLinks, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QFileInfo f = it.nextFileInfo();
        if (olderThanSecs < 0 || f.lastModified() < cut) {
            total += f.size();
        }
    }
    return total;
}

// files older than the cut (all when -1), then directories left empty
qint64 removeIn(const QString &path, qint64 olderThanSecs = -1)
{
    const QDateTime cut = QDateTime::currentDateTime().addSecs(-olderThanSecs);
    qint64 freed = 0;
    QDirIterator it(path, QDir::Files | QDir::Hidden | QDir::System | QDir::NoSymLinks, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QFileInfo f = it.nextFileInfo();
        if ((olderThanSecs < 0 || f.lastModified() < cut) && QFile::remove(f.filePath())) {
            freed += f.size();
        }
    }
    QDirIterator dirs(path, QDir::Dirs | QDir::Hidden | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    QStringList all;
    while (dirs.hasNext()) {
        all << dirs.next();
    }
    std::sort(all.begin(), all.end(), [](const QString &a, const QString &b) { return a.size() > b.size(); });
    for (const QString &d : all) {
        QDir().rmdir(d);          // only succeeds when empty
    }
    return freed;
}

const QString trashDir = home + QStringLiteral("/.local/share/Trash");

// trash items deleted before the cut (by their .trashinfo DeletionDate); all when -1
qint64 emptyTrash(qint64 olderThanSecs, bool measureOnly)
{
    const QDateTime cut = QDateTime::currentDateTime().addSecs(-olderThanSecs);
    qint64 total = 0;
    const QFileInfoList infos = QDir(trashDir + QStringLiteral("/info")).entryInfoList({QStringLiteral("*.trashinfo")}, QDir::Files | QDir::Hidden);
    for (const QFileInfo &info : infos) {
        QDateTime deleted;
        QFile f(info.filePath());
        if (f.open(QIODevice::ReadOnly)) {
            for (const QByteArray &line : f.readAll().split('\n')) {
                if (line.startsWith("DeletionDate=")) {
                    deleted = QDateTime::fromString(QString::fromUtf8(line.mid(13)).trimmed(), Qt::ISODate);
                }
            }
        }
        if (olderThanSecs >= 0 && (!deleted.isValid() || deleted > cut)) {
            continue;
        }
        const QString item = trashDir + QStringLiteral("/files/") + info.completeBaseName();
        const qint64 size = sizeOf(item);
        total += size;
        if (!measureOnly) {
            const QFileInfo fi(item);
            if (fi.isDir() && !fi.isSymLink()) {
                QDir(item).removeRecursively();
            } else {
                QFile::remove(item);
            }
            QFile::remove(info.filePath());
        }
    }
    if (!measureOnly && olderThanSecs < 0) {
        QFile::remove(trashDir + QStringLiteral("/directorysizes"));
    }
    return total;
}

QStringList downloadDirs()
{
    QStringList dirs;
    for (const QString &d : {home + QStringLiteral("/Загрузки"), home + QStringLiteral("/Downloads")}) {
        if (QFileInfo(d).isDir()) {
            dirs << d;
        }
    }
    return dirs;
}

// top-level entries of the download folders untouched for 30 days
QFileInfoList oldDownloads()
{
    QFileInfoList out;
    const QDateTime cut = QDateTime::currentDateTime().addDays(-30);
    for (const QString &d : downloadDirs()) {
        for (const QFileInfo &f : QDir(d).entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot)) {
            if (f.lastModified() < cut) {
                out << f;
            }
        }
    }
    return out;
}

QStringList firefoxCaches()
{
    QStringList out;
    for (const QFileInfo &p : QDir(home + QStringLiteral("/.cache/mozilla/firefox")).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        out << p.filePath() + QStringLiteral("/cache2");
    }
    return out;
}

bool running(const char *name)
{
    QProcess p;
    p.start(QStringLiteral("pgrep"), {QStringLiteral("-x"), QString::fromLatin1(name)});
    p.waitForFinished(3000);
    return p.exitCode() == 0;
}

// caches that rebuild themselves (not the shell's own: those are small and in use)
QStringList appCaches()
{
    QStringList out{home + QStringLiteral("/.cache/thumbnails"), home + QStringLiteral("/.cache/drkonqi"),
                    home + QStringLiteral("/.cache/waydroid-script"), home + QStringLiteral("/.cache/discover"),
                    home + QStringLiteral("/.cache/yay"), home + QStringLiteral("/.cache/paru"),
                    home + QStringLiteral("/.cache/pip"), home + QStringLiteral("/.npm/_cacache")};
    for (const QFileInfo &w : QDir(home + QStringLiteral("/.cache")).entryInfoList({QStringLiteral("webapp-*")}, QDir::Dirs)) {
        out << w.filePath();
    }
    return out;
}

int cleanup(const QStringList &args)
{
    const QString cmd = args.value(0);
    const qint64 month = 30LL * 24 * 3600;
    if (cmd == QLatin1String("scan")) {
        const QStorageInfo disk(home);
        qint64 browser = 0, apps = 0, downloads = 0, pacman = 0;
        for (const QString &c : firefoxCaches()) {
            browser += sizeOf(c);
        }
        for (const QString &c : appCaches()) {
            apps += sizeOf(c);
        }
        const QFileInfoList old = oldDownloads();
        for (const QFileInfo &f : old) {
            downloads += sizeOf(f.filePath());
        }
        for (const QFileInfo &f : QDir(QStringLiteral("/var/cache/pacman/pkg")).entryInfoList(QDir::Files)) {
            pacman += f.size();
        }
        auto item = [](const char *id, const char *label, qint64 bytes, const QString &note) {
            return QJsonObject{{QStringLiteral("id"), QLatin1String(id)}, {QStringLiteral("label"), T(QString::fromUtf8(label))},
                               {QStringLiteral("bytes"), bytes}, {QStringLiteral("note"), note}};
        };
        const QJsonArray items{
            item("trash", "Корзина", emptyTrash(-1, true), T(QStringLiteral("Удалённые файлы"))),
            item("browser", "Кэш Firefox", browser, running("firefox") ? T(QStringLiteral("Закройте Firefox, чтобы очистить"))
                                                                          : T(QStringLiteral("Страницы загрузятся заново"))),
            item("apps", "Кэш приложений", apps, T(QStringLiteral("Миниатюры, веб-приложения, отчёты о сбоях, сборки AUR"))),
            item("downloads", "Старые загрузки", downloads,
                 T(QStringLiteral("%1 файлов старше месяца — переносятся в корзину")).arg(old.size())),
            item("pacman", "Кэш пакетов", pacman, T(QStringLiteral("Старые версии программ; нужен пароль"))),
        };
        out(QString::fromUtf8(QJsonDocument(QJsonObject{{QStringLiteral("free"), disk.bytesAvailable()},
                                                         {QStringLiteral("total"), disk.bytesTotal()},
                                                         {QStringLiteral("items"), items}})
                                  .toJson(QJsonDocument::Compact)) + QLatin1Char('\n'));
        return 0;
    }
    qint64 freed = 0;
    if (cmd == QLatin1String("run")) {
        for (const QString &id : args.mid(1)) {
            if (id == QLatin1String("trash")) {
                freed += emptyTrash(-1, false);
            } else if (id == QLatin1String("browser") && !running("firefox")) {
                for (const QString &c : firefoxCaches()) {
                    freed += removeIn(c);
                }
            } else if (id == QLatin1String("apps")) {
                for (const QString &c : appCaches()) {
                    freed += removeIn(c);
                }
            } else if (id == QLatin1String("downloads")) {
                // to the trash: a mistake can still be undone
                for (const QFileInfo &f : oldDownloads()) {
                    QProcess::execute(QStringLiteral("gio"), {QStringLiteral("trash"), f.filePath()});
                }
            }
        }
    } else if (cmd == QLatin1String("auto")) {
        freed += emptyTrash(month, false);
        freed += removeIn(home + QStringLiteral("/.cache/thumbnails"), month);
        freed += removeIn(home + QStringLiteral("/.cache/drkonqi"));
    } else {
        std::fputs("usage: tablet-tools cleanup scan | run trash|browser|apps|downloads ... | auto\n", stderr);
        return 2;
    }
    out(QString::fromUtf8(QJsonDocument(QJsonObject{{QStringLiteral("freed"), freed}}).toJson(QJsonDocument::Compact)) + QLatin1Char('\n'));
    return 0;
}

// ---- weekly report ---------------------------------------------------------------------------
// The last 7 days (today included) against the 7 before: screen time with the top apps, typewriter
// words, battery health. Linux keeps no battery history, so each run notes today's full capacity
// and cycle count in ~/.local/share/weekly/battery.json and compares with the note a week back.
int weekly()
{
    const QDate today = QDate::currentDate();
    QJsonArray screenDays, wordDays;
    QHash<QString, qint64> apps;
    qint64 screen = 0, screenBefore = 0;
    int words = 0, wordsBefore = 0;
    for (int i = 13; i >= 0; --i) {
        const QDate day = today.addDays(-i);
        const QJsonObject st = readJson(home + QStringLiteral("/.local/share/screentime/") + day.toString(Qt::ISODate) + QStringLiteral(".json"));
        qint64 secs = 0;
        for (auto it = st.begin(); it != st.end(); ++it) {
            secs += it.value().toInteger();
            if (i < 7) {
                apps[it.key()] += it.value().toInteger();
            }
        }
        const int w = typewriterWordsOn(day);
        if (i < 7) {
            screen += secs;
            words += w;
            screenDays.append(secs);
            wordDays.append(w);
        } else {
            screenBefore += secs;
            wordsBefore += w;
        }
    }
    QList<QPair<qint64, QString>> sorted;
    for (auto it = apps.begin(); it != apps.end(); ++it) {
        sorted.append({it.value(), it.key()});
    }
    std::sort(sorted.begin(), sorted.end(), [](const auto &a, const auto &b) { return a.first > b.first; });
    QJsonArray top;
    for (int i = 0; i < qMin(3, int(sorted.size())); ++i) {
        const QJsonObject info = lookupApp(sorted[i].second);
        top.append(QJsonObject{{QStringLiteral("name"), info.value(QStringLiteral("name")).toString(sorted[i].second)},
                               {QStringLiteral("icon"), info.value(QStringLiteral("icon"))},
                               {QStringLiteral("seconds"), sorted[i].first}});
    }

    // battery: today's note, compared with the oldest note of the last 7..13 days
    QString bat = QStringLiteral("/sys/class/power_supply/BAT0/");
    const QDir power(QStringLiteral("/sys/class/power_supply"));
    for (const QString &d : power.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        if (readProc(power.filePath(d + QStringLiteral("/type"))).trimmed() == "Battery") {
            bat = power.filePath(d) + QLatin1Char('/');
            break;
        }
    }
    const double full = readProc(bat + QStringLiteral("energy_full")).trimmed().toDouble();
    const double design = readProc(bat + QStringLiteral("energy_full_design")).trimmed().toDouble();
    const int cycles = readProc(bat + QStringLiteral("cycle_count")).trimmed().toInt();
    const QString historyPath = home + QStringLiteral("/.local/share/weekly/battery.json");
    QJsonObject history = readJson(historyPath);
    if (full > 0) {
        history[today.toString(Qt::ISODate)] = QJsonObject{{QStringLiteral("full"), full}, {QStringLiteral("cycles"), cycles}};
        writePrivateJson(historyPath, history);
    }
    QJsonObject battery{{QStringLiteral("health"), design > 0 ? std::round(full / design * 1000) / 10 : 0.0},
                        {QStringLiteral("cycles"), cycles}};
    for (int i = 13; i >= 7; --i) {
        const QJsonObject old = history.value(today.addDays(-i).toString(Qt::ISODate)).toObject();
        if (!old.isEmpty() && design > 0) {
            battery[QStringLiteral("healthBefore")] = std::round(old.value(QStringLiteral("full")).toDouble() / design * 1000) / 10;
            battery[QStringLiteral("cyclesBefore")] = old.value(QStringLiteral("cycles")).toInt();
            break;
        }
    }

    const QJsonObject result{
        {QStringLiteral("from"), today.addDays(-6).toString(Qt::ISODate)},
        {QStringLiteral("to"), today.toString(Qt::ISODate)},
        {QStringLiteral("screen"), QJsonObject{{QStringLiteral("total"), screen}, {QStringLiteral("before"), screenBefore},
                                               {QStringLiteral("days"), screenDays}, {QStringLiteral("top"), top}}},
        {QStringLiteral("words"), QJsonObject{{QStringLiteral("total"), words}, {QStringLiteral("before"), wordsBefore},
                                              {QStringLiteral("days"), wordDays}}},
        {QStringLiteral("battery"), battery},
    };
    out(QString::fromUtf8(QJsonDocument(result).toJson(QJsonDocument::Compact)) + QLatin1Char('\n'));
    return 0;
}

QNetworkRequest browserRequest(const QString &url)
{
    QNetworkRequest req{QUrl(url)};
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Mozilla/5.0 (X11; Linux x86_64) tablet-today/1.0 (tablet home screen)"));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    return req;
}

// Height of the sun in degrees (NOAA approximation): day or night for weather sources that do not say
double sunElevation(const QDateTime &utc, double lat, double lon)
{
    const double rad = M_PI / 180;
    const int day = utc.date().dayOfYear();
    const double hours = utc.time().hour() + utc.time().minute() / 60.0;
    const double g = 2 * M_PI / 365 * (day - 1 + (hours - 12) / 24);
    const double eqTime = 229.18 * (0.000075 + 0.001868 * std::cos(g) - 0.032077 * std::sin(g) - 0.014615 * std::cos(2 * g) - 0.040849 * std::sin(2 * g));
    const double decl = 0.006918 - 0.399912 * std::cos(g) + 0.070257 * std::sin(g) - 0.006758 * std::cos(2 * g) + 0.000907 * std::sin(2 * g)
                        - 0.002697 * std::cos(3 * g) + 0.00148 * std::sin(3 * g);
    const double hourAngle = ((hours * 60 + eqTime + 4 * lon) / 4 - 180) * rad;
    const double cosZenith = std::sin(lat * rad) * std::sin(decl) + std::cos(lat * rad) * std::cos(decl) * std::cos(hourAngle);
    return 90 - std::acos(std::clamp(cosZenith, -1.0, 1.0)) / rad;
}

// MET Norway symbol ("lightrainshowers_day") -> WMO weather code, as Open-Meteo gives it
int metnoCode(const QString &symbol)
{
    const QString s = symbol.section(QLatin1Char('_'), 0, 0);
    const bool light = s.startsWith(QLatin1String("light")), heavy = s.startsWith(QLatin1String("heavy"));
    const bool showers = s.contains(QLatin1String("showers"));
    if (s.contains(QLatin1String("thunder"))) return 95;
    if (s.contains(QLatin1String("sleet"))) return 66;
    if (s.contains(QLatin1String("snow"))) return showers ? (heavy ? 86 : 85) : light ? 71 : heavy ? 75 : 73;
    if (s.contains(QLatin1String("rain"))) return showers ? (light ? 80 : heavy ? 82 : 81) : light ? 61 : heavy ? 65 : 63;
    if (s == QLatin1String("fog")) return 45;
    if (s == QLatin1String("partlycloudy")) return 2;
    if (s == QLatin1String("cloudy")) return 3;
    if (s == QLatin1String("fair")) return 1;
    return 0;
}

// World Weather Online code (wttr.in) -> WMO weather code
int wwoCode(int c)
{
    switch (c) {
    case 113: return 0;
    case 116: return 2;
    case 119: case 122: return 3;
    case 143: case 248: case 260: return 45;
    case 263: case 266: return 53;
    case 176: case 353: return 80;
    case 356: return 81;
    case 359: return 82;
    case 293: case 296: return 61;
    case 299: case 302: return 63;
    case 305: case 308: return 65;
    case 179: case 323: case 326: return 71;
    case 329: case 332: return 73;
    case 227: case 230: case 335: case 338: return 75;
    case 368: return 85;
    case 371: return 86;
    case 182: case 185: case 281: case 284: case 311: case 314: case 317: case 320: case 350: case 362: case 365: case 374: case 377: return 66;
    case 200: case 386: case 389: case 392: case 395: return 95;
    }
    return 3;
}

// The weather source: tabletrc [Weather] source = openmeteo (default) | metno | wttr. All three are
// free and need no key; the place is always geocoded by Open-Meteo once and the coordinates cached.
QString weatherSource()
{
    KConfig rc(QStringLiteral("tabletrc"), KConfig::SimpleConfig);
    const QString s = rc.group(QStringLiteral("Weather")).readEntry("source", QStringLiteral("openmeteo"));
    return s == QLatin1String("metno") || s == QLatin1String("wttr") ? s : QStringLiteral("openmeteo");
}

QJsonObject weather(QNetworkAccessManager &net, const QString &city, const QJsonObject &old)
{
    if (city.isEmpty()) {
        return {};
    }
    const QString source = weatherSource();
    double lat = old.value(QStringLiteral("lat")).toDouble(), lon = old.value(QStringLiteral("lon")).toDouble();
    QString place = old.value(QStringLiteral("place")).toString();
    if (old.value(QStringLiteral("city")).toString() != city || (lat == 0 && lon == 0)) {
        QUrl geo(QStringLiteral("https://geocoding-api.open-meteo.com/v1/search"));
        geo.setQuery(QUrlQuery{{QStringLiteral("name"), city}, {QStringLiteral("count"), QStringLiteral("1")}, {QStringLiteral("language"), QStringLiteral("ru")}});
        const Response r = request(net, QNetworkRequest(geo));
        const QJsonObject hit = QJsonDocument::fromJson(r.data).object().value(QStringLiteral("results")).toArray().at(0).toObject();
        if (hit.isEmpty()) {
            return {{QStringLiteral("city"), city}, {QStringLiteral("source"), source},
                    {QStringLiteral("error"), r.status == 200 ? T(QStringLiteral("город не найден")) : T(QStringLiteral("нет связи"))}};
        }
        lat = hit.value(QStringLiteral("latitude")).toDouble();
        lon = hit.value(QStringLiteral("longitude")).toDouble();
        place = hit.value(QStringLiteral("name")).toString();
    }
    QJsonObject out{{QStringLiteral("city"), city}, {QStringLiteral("place"), place}, {QStringLiteral("lat"), lat}, {QStringLiteral("lon"), lon},
                    {QStringLiteral("source"), source}};
    const int sunUp = sunElevation(QDateTime::currentDateTimeUtc(), lat, lon) > -0.833 ? 1 : 0;

    if (source == QLatin1String("metno")) {
        // MET Norway (yr.no): asks for an identifying User-Agent; wind in m/s, no "feels like"
        QUrl url(QStringLiteral("https://api.met.no/weatherapi/locationforecast/2.0/compact"));
        url.setQuery(QUrlQuery{{QStringLiteral("lat"), QString::number(lat, 'f', 4)}, {QStringLiteral("lon"), QString::number(lon, 'f', 4)}});
        QNetworkRequest req(url);
        req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("tablet-shell/0.5 github.com/Vorsente/tablet-shell"));
        const Response r = request(net, req);
        const QJsonArray series = QJsonDocument::fromJson(r.data).object().value(QStringLiteral("properties")).toObject()
                                      .value(QStringLiteral("timeseries")).toArray();
        if (r.status != 200 || series.isEmpty()) {
            out.insert(QStringLiteral("error"), T(QStringLiteral("нет связи")));
            return out;
        }
        const QJsonObject first = series.at(0).toObject().value(QStringLiteral("data")).toObject();
        const QJsonObject now = first.value(QStringLiteral("instant")).toObject().value(QStringLiteral("details")).toObject();
        QString symbol = first.value(QStringLiteral("next_1_hours")).toObject().value(QStringLiteral("summary")).toObject().value(QStringLiteral("symbol_code")).toString();
        if (symbol.isEmpty()) {
            symbol = first.value(QStringLiteral("next_6_hours")).toObject().value(QStringLiteral("summary")).toObject().value(QStringLiteral("symbol_code")).toString();
        }
        const double temp = now.value(QStringLiteral("air_temperature")).toDouble();
        double hi = temp, lo = temp;
        const QDate today = QDate::currentDate();
        for (const QJsonValue &v : series) {
            const QJsonObject e = v.toObject();
            if (QDateTime::fromString(e.value(QStringLiteral("time")).toString(), Qt::ISODate).toLocalTime().date() != today) {
                continue;
            }
            const double t = e.value(QStringLiteral("data")).toObject().value(QStringLiteral("instant")).toObject()
                                 .value(QStringLiteral("details")).toObject().value(QStringLiteral("air_temperature")).toDouble(temp);
            hi = std::max(hi, t);
            lo = std::min(lo, t);
        }
        out.insert(QStringLiteral("temp"), temp);
        out.insert(QStringLiteral("feels"), temp);
        out.insert(QStringLiteral("code"), metnoCode(symbol));
        out.insert(QStringLiteral("wind"), std::round(now.value(QStringLiteral("wind_speed")).toDouble() * 36) / 10);
        out.insert(QStringLiteral("day"), symbol.endsWith(QLatin1String("_night")) ? 0 : symbol.contains(QLatin1Char('_')) ? 1 : sunUp);
        out.insert(QStringLiteral("max"), hi);
        out.insert(QStringLiteral("min"), lo);
        return out;
    }

    if (source == QLatin1String("wttr")) {
        // wttr.in (World Weather Online data), its JSON format
        const Response r = request(net, browserRequest(QStringLiteral("https://wttr.in/%1,%2?format=j1&lang=ru")
                                                           .arg(lat, 0, 'f', 4).arg(lon, 0, 'f', 4)));
        const QJsonObject w = QJsonDocument::fromJson(r.data).object();
        const QJsonObject cur = w.value(QStringLiteral("current_condition")).toArray().at(0).toObject();
        const QJsonObject day = w.value(QStringLiteral("weather")).toArray().at(0).toObject();
        if (r.status != 200 || cur.isEmpty()) {
            out.insert(QStringLiteral("error"), T(QStringLiteral("нет связи")));
            return out;
        }
        auto num = [](const QJsonObject &o, const char *key) { return o.value(QLatin1String(key)).toString().toDouble(); };
        out.insert(QStringLiteral("temp"), num(cur, "temp_C"));
        out.insert(QStringLiteral("feels"), num(cur, "FeelsLikeC"));
        out.insert(QStringLiteral("code"), wwoCode(cur.value(QStringLiteral("weatherCode")).toString().toInt()));
        out.insert(QStringLiteral("wind"), num(cur, "windspeedKmph"));
        out.insert(QStringLiteral("day"), sunUp);
        out.insert(QStringLiteral("max"), num(day, "maxtempC"));
        out.insert(QStringLiteral("min"), num(day, "mintempC"));
        return out;
    }

    QUrl url(QStringLiteral("https://api.open-meteo.com/v1/forecast"));
    url.setQuery(QUrlQuery{{QStringLiteral("latitude"), QString::number(lat)}, {QStringLiteral("longitude"), QString::number(lon)},
                           {QStringLiteral("current"), QStringLiteral("temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day")},
                           {QStringLiteral("daily"), QStringLiteral("temperature_2m_max,temperature_2m_min")},
                           {QStringLiteral("timezone"), QStringLiteral("auto")}, {QStringLiteral("forecast_days"), QStringLiteral("1")}});
    const Response r = request(net, QNetworkRequest(url));
    const QJsonObject w = QJsonDocument::fromJson(r.data).object();
    if (r.status != 200) {
        out.insert(QStringLiteral("error"), T(QStringLiteral("нет связи")));
        return out;
    }
    const QJsonObject cur = w.value(QStringLiteral("current")).toObject();
    const QJsonObject daily = w.value(QStringLiteral("daily")).toObject();
    out.insert(QStringLiteral("temp"), cur.value(QStringLiteral("temperature_2m")));
    out.insert(QStringLiteral("feels"), cur.value(QStringLiteral("apparent_temperature")));
    out.insert(QStringLiteral("code"), cur.value(QStringLiteral("weather_code")));
    out.insert(QStringLiteral("wind"), cur.value(QStringLiteral("wind_speed_10m")));
    out.insert(QStringLiteral("day"), cur.value(QStringLiteral("is_day")));
    out.insert(QStringLiteral("max"), daily.value(QStringLiteral("temperature_2m_max")).toArray().at(0));
    out.insert(QStringLiteral("min"), daily.value(QStringLiteral("temperature_2m_min")).toArray().at(0));
    return out;
}

// ---- Today page (home screen): news, exchange rates, on this day ----------------------------
// Feeds: chosen in the settings (linuxFeedSpec, countryFeedSpec below). Cached 30 minutes,
// "on this day" for the day; a failed source keeps its last good items.
const QString todayCache = home + QStringLiteral("/.cache/tablet-today.json");


QJsonArray rssItems(QNetworkAccessManager &net, const QString &url, const QString &source)
{
    const Response r = request(net, browserRequest(url));
    QJsonArray items;
    if (r.status != 200) {
        return items;
    }
    QXmlStreamReader xml(r.data);
    QString title, link, date, outlet;
    bool inItem = false;
    while (!xml.atEnd()) {
        xml.readNext();
        const QString name = xml.name().toString();
        if (xml.isStartElement() && (name == QLatin1String("item") || name == QLatin1String("entry"))) {
            inItem = true;
            title.clear(); link.clear(); date.clear(); outlet.clear();
        } else if (xml.isStartElement() && inItem) {
            if (name == QLatin1String("title")) {
                title = xml.readElementText(QXmlStreamReader::IncludeChildElements).simplified();
            } else if (name == QLatin1String("link")) {
                const QString href = xml.attributes().value(QStringLiteral("href")).toString();
                link = href.isEmpty() ? xml.readElementText().trimmed() : href;
            } else if (name == QLatin1String("pubDate") || name == QLatin1String("published") || name == QLatin1String("updated")) {
                date = xml.readElementText().trimmed();
            } else if (name == QLatin1String("source")) {
                outlet = xml.readElementText().simplified();
            }
        } else if (xml.isEndElement() && (name == QLatin1String("item") || name == QLatin1String("entry"))) {
            inItem = false;
            QDateTime t = QDateTime::fromString(date, Qt::RFC2822Date);
            if (!t.isValid()) {
                t = QDateTime::fromString(date, Qt::ISODate);
            }
            if (!outlet.isEmpty() && title.endsWith(QLatin1String(" - ") + outlet)) {
                title.chop(outlet.size() + 3);
            }
            if (!title.isEmpty()) {
                items.append(QJsonObject{{QStringLiteral("title"), title}, {QStringLiteral("link"), link},
                                         {QStringLiteral("source"), outlet.isEmpty() ? source : outlet},
                                         {QStringLiteral("time"), t.isValid() ? t.toSecsSinceEpoch() : 0}});
            }
        }
    }
    return items;
}

// newest first over all feeds of a group; nothing at all -> the cached list
QJsonArray newsGroup(QNetworkAccessManager &net, const QString &spec, const QJsonArray &old)
{
    QList<QJsonObject> all;
    const QStringList feeds = spec.split(QLatin1Char(';'), Qt::SkipEmptyParts);
    for (const QString &feed : feeds) {
        const QString url = feed.section(QLatin1Char('|'), 0, 0).trimmed();
        const QString name = feed.section(QLatin1Char('|'), 1).trimmed();
        for (const QJsonValue &v : rssItems(net, url, name)) {
            all.append(v.toObject());
        }
    }
    if (all.isEmpty()) {
        return old;
    }
    std::sort(all.begin(), all.end(), [](const QJsonObject &a, const QJsonObject &b) {
        return a.value(QStringLiteral("time")).toInteger() > b.value(QStringLiteral("time")).toInteger();
    });
    // 16 headlines (the cards page through them), at most 6 from one source when there are
    // several feeds, so a busy agency does not crowd out the others
    QJsonArray out;
    QHash<QString, int> perSource;
    const int cap = feeds.size() > 1 ? 6 : 16;
    for (const QJsonObject &item : std::as_const(all)) {
        int &n = perSource[item.value(QStringLiteral("source")).toString()];
        if (n < cap && out.size() < 16) {
            ++n;
            out.append(item);
        }
    }
    return out;
}

// Exchange rates in the chosen currency (tabletrc [Today] currency: a code, or "auto" = the news
// country's): {base, sign, source, items: [{code, sign, value, previous}]}, value = how much of the
// base one unit of the foreign currency costs. Roubles: the Bank of Russia (cbr-xml-daily.ru mirror,
// with yesterday's rate); others: ExchangeRate-API's free daily rates (open.er-api.com, no key),
// yesterday's value kept from the cache of an earlier day.
struct Currency {
    const char *code, *sign;
};
const Currency currencySigns[] = {
    {"RUB", "₽"}, {"UAH", "₴"}, {"KZT", "₸"}, {"USD", "$"}, {"EUR", "€"}, {"GBP", "£"}, {"CNY", "¥"}, {"JPY", "¥"},
    {"CAD", "C$"}, {"AUD", "A$"}, {"INR", "₹"}, {"CHF", "Fr"}, {"BRL", "R$"}, {"PLN", "zł"}, {"CZK", "Kč"},
    {"SEK", "kr"}, {"NOK", "kr"}, {"TRY", "₺"}, {"ILS", "₪"}, {"KRW", "₩"},
};
QString currencySign(const QString &code)
{
    for (const Currency &c : currencySigns) {
        if (code == QLatin1String(c.code)) {
            return QString::fromUtf8(c.sign);
        }
    }
    return code;
}
QString countryCurrency(const QString &country)
{
    static const QHash<QString, QString> map{
        {QStringLiteral("ru"), QStringLiteral("RUB")}, {QStringLiteral("ua"), QStringLiteral("UAH")}, {QStringLiteral("kz"), QStringLiteral("KZT")},
        {QStringLiteral("us"), QStringLiteral("USD")}, {QStringLiteral("gb"), QStringLiteral("GBP")}, {QStringLiteral("ca"), QStringLiteral("CAD")},
        {QStringLiteral("au"), QStringLiteral("AUD")}, {QStringLiteral("in"), QStringLiteral("INR")}, {QStringLiteral("ch"), QStringLiteral("CHF")},
        {QStringLiteral("br"), QStringLiteral("BRL")}, {QStringLiteral("pl"), QStringLiteral("PLN")}, {QStringLiteral("cz"), QStringLiteral("CZK")},
        {QStringLiteral("se"), QStringLiteral("SEK")}, {QStringLiteral("no"), QStringLiteral("NOK")}, {QStringLiteral("tr"), QStringLiteral("TRY")},
        {QStringLiteral("il"), QStringLiteral("ILS")}, {QStringLiteral("jp"), QStringLiteral("JPY")}, {QStringLiteral("kr"), QStringLiteral("KRW")},
    };
    return map.value(country, QStringLiteral("EUR"));    // the euro countries
}
// three foreign currencies worth showing against the base
QStringList foreignCurrencies(const QString &base)
{
    if (base == QLatin1String("USD")) return {QStringLiteral("EUR"), QStringLiteral("GBP"), QStringLiteral("JPY")};
    if (base == QLatin1String("EUR")) return {QStringLiteral("USD"), QStringLiteral("GBP"), QStringLiteral("CHF")};
    if (base == QLatin1String("GBP")) return {QStringLiteral("USD"), QStringLiteral("EUR"), QStringLiteral("JPY")};
    return {QStringLiteral("USD"), QStringLiteral("EUR"), QStringLiteral("CNY")};
}

QJsonObject exchangeRates(QNetworkAccessManager &net, const QString &base, const QJsonObject &old)
{
    const QStringList codes = foreignCurrencies(base);
    QJsonArray items;
    QString source;
    if (base == QLatin1String("RUB")) {
        const Response r = request(net, browserRequest(QStringLiteral("https://www.cbr-xml-daily.ru/daily_json.js")));
        const QJsonObject valute = QJsonDocument::fromJson(r.data).object().value(QStringLiteral("Valute")).toObject();
        for (const QString &code : codes) {
            const QJsonObject v = valute.value(code).toObject();
            if (v.isEmpty()) continue;
            const double nominal = std::max(1.0, v.value(QStringLiteral("Nominal")).toDouble());
            items.append(QJsonObject{{QStringLiteral("code"), code}, {QStringLiteral("sign"), currencySign(code)},
                                     {QStringLiteral("value"), v.value(QStringLiteral("Value")).toDouble() / nominal},
                                     {QStringLiteral("previous"), v.value(QStringLiteral("Previous")).toDouble() / nominal}});
        }
        source = T(QStringLiteral("ЦБ РФ"));
    } else {
        const Response r = request(net, browserRequest(QStringLiteral("https://open.er-api.com/v6/latest/") + base));
        const QJsonObject o = QJsonDocument::fromJson(r.data).object();
        const QJsonObject rates = o.value(QStringLiteral("rates")).toObject();
        const QString day = QDateTime::fromSecsSinceEpoch(o.value(QStringLiteral("time_last_update_unix")).toInteger()).date().toString(Qt::ISODate);
        // yesterday's values: what the cache had on an earlier day for the same base
        const bool sameBase = old.value(QStringLiteral("base")).toString() == base;
        const bool newDay = old.value(QStringLiteral("day")).toString() != day;
        QHash<QString, double> before;
        for (const QJsonValue &v : old.value(QStringLiteral("items")).toArray()) {
            const QJsonObject i = v.toObject();
            before.insert(i.value(QStringLiteral("code")).toString(),
                          i.value(newDay ? QStringLiteral("value") : QStringLiteral("previous")).toDouble());
        }
        for (const QString &code : codes) {
            const double perBase = rates.value(code).toDouble();
            if (perBase <= 0) continue;
            const double value = 1.0 / perBase;
            items.append(QJsonObject{{QStringLiteral("code"), code}, {QStringLiteral("sign"), currencySign(code)},
                                     {QStringLiteral("value"), value},
                                     {QStringLiteral("previous"), sameBase && before.value(code) > 0 ? before.value(code) : value}});
        }
        source = QStringLiteral("ExchangeRate-API");
        if (!items.isEmpty()) {
            return {{QStringLiteral("base"), base}, {QStringLiteral("sign"), currencySign(base)}, {QStringLiteral("source"), source},
                    {QStringLiteral("day"), day}, {QStringLiteral("items"), items}};
        }
    }
    if (items.isEmpty()) {
        return old.value(QStringLiteral("base")).toString() == base ? old : QJsonObject{};
    }
    return {{QStringLiteral("base"), base}, {QStringLiteral("sign"), currencySign(base)}, {QStringLiteral("source"), source},
            {QStringLiteral("items"), items}};
}

// a few events of this day in history (Russian Wikipedia), spread over the centuries
QJsonArray onThisDay(QNetworkAccessManager &net)
{
    const QDate d = QDate::currentDate();
    const Response r = request(net, browserRequest(QStringLiteral("https://ru.wikipedia.org/api/rest_v1/feed/onthisday/events/%1/%2")
                                                       .arg(d.month(), 2, 10, QLatin1Char('0')).arg(d.day(), 2, 10, QLatin1Char('0'))));
    QList<QJsonObject> events;
    for (const QJsonValue &v : QJsonDocument::fromJson(r.data).object().value(QStringLiteral("events")).toArray()) {
        const QJsonObject e = v.toObject();
        const QJsonObject page = e.value(QStringLiteral("pages")).toArray().at(0).toObject();
        events.append({{QStringLiteral("year"), e.value(QStringLiteral("year")).toInt()},
                       {QStringLiteral("text"), e.value(QStringLiteral("text")).toString()},
                       {QStringLiteral("link"), page.value(QStringLiteral("content_urls")).toObject().value(QStringLiteral("desktop")).toObject().value(QStringLiteral("page")).toString()}});
    }
    std::sort(events.begin(), events.end(), [](const QJsonObject &a, const QJsonObject &b) {
        return a.value(QStringLiteral("year")).toInt() > b.value(QStringLiteral("year")).toInt();
    });
    QJsonArray out;
    const int step = std::max<int>(1, events.size() / 6);
    for (int i = 0; i < events.size() && out.size() < 6; i += step) {
        out.append(events[i]);
    }
    return out;
}

// Linux news feeds: Russian ones and English ones, each switched on in the settings
// (tabletrc [Today] linuxLanguage = ru | en | both, and en_<id> per English feed).
// tabletrc [Today] linuxFeeds = "URL|Name;..." still overrides the whole list.
struct Feed {
    const char *id, *url, *name;
    bool on;     // on by default
};
const Feed linuxRu[] = {
    {"opennet", "https://www.opennet.ru/opennews/opennews_all_utf.rss", "OpenNET", true},
    {"lor", "https://www.linux.org.ru/section-rss.jsp?section=1", "LOR", true},
};
const Feed linuxEn[] = {
    {"phoronix", "https://www.phoronix.com/rss.php", "Phoronix", true},
    {"9to5linux", "https://9to5linux.com/feed/atom", "9to5Linux", true},
    {"lwn", "https://lwn.net/headlines/rss", "LWN", true},
    {"omgubuntu", "https://www.omgubuntu.co.uk/feed", "OMG! Ubuntu", false},
    {"itsfoss", "https://itsfoss.com/rss/", "It's FOSS", false},
    {"gamingonlinux", "https://www.gamingonlinux.com/article_rss.php", "GamingOnLinux", false},
    {"linuxiac", "https://linuxiac.com/feed/", "Linuxiac", false},
    {"planetkde", "https://planet.kde.org/global/atom.xml", "Planet KDE", false},
    {"archlinux", "https://archlinux.org/feeds/news/", "Arch Linux", false},
};

QString linuxFeedSpec(const KConfigGroup &g)
{
    const QString custom = g.readEntry("linuxFeeds", QString());
    if (!custom.isEmpty()) {
        return custom;
    }
    const QString lang = g.readEntry("linuxLanguage", QStringLiteral("ru"));
    QStringList feeds;
    if (lang != QLatin1String("en")) {
        for (const Feed &f : linuxRu) {
            feeds << QLatin1String(f.url) + QLatin1Char('|') + QLatin1String(f.name);
        }
    }
    if (lang == QLatin1String("en") || lang == QLatin1String("both")) {
        for (const Feed &f : linuxEn) {
            if (g.readEntry(QStringLiteral("en_") + QLatin1String(f.id), f.on)) {
                feeds << QLatin1String(f.url) + QLatin1Char('|') + QLatin1String(f.name);
            }
        }
        if (feeds.isEmpty()) {   // every English feed switched off: Phoronix rather than nothing
            feeds << QLatin1String(linuxEn[0].url) + QLatin1Char('|') + QLatin1String(linuxEn[0].name);
        }
    }
    return feeds.join(QLatin1Char(';'));
}

// The country of the news card: tabletrc [Today] newsCountry (two letters, default ru).
// Russia keeps Lenta and TASS (or tabletrc russiaFeeds); every other country gets the top
// stories of its Google News edition, in its language.
struct Country {
    const char *code, *flag, *hl, *lang;
};
const Country countries[] = {
    {"ru", "🇷🇺", "ru", "ru"}, {"ua", "🇺🇦", "uk", "uk"}, {"kz", "🇰🇿", "ru", "ru"}, {"us", "🇺🇸", "en-US", "en"},
    {"gb", "🇬🇧", "en-GB", "en"}, {"ca", "🇨🇦", "en-CA", "en"}, {"au", "🇦🇺", "en-AU", "en"}, {"in", "🇮🇳", "en-IN", "en"},
    {"de", "🇩🇪", "de", "de"}, {"at", "🇦🇹", "de", "de"}, {"ch", "🇨🇭", "de", "de"}, {"fr", "🇫🇷", "fr", "fr"},
    {"it", "🇮🇹", "it", "it"}, {"es", "🇪🇸", "es", "es"}, {"pt", "🇵🇹", "pt-PT", "pt-150"}, {"br", "🇧🇷", "pt-BR", "pt-419"},
    {"nl", "🇳🇱", "nl", "nl"}, {"pl", "🇵🇱", "pl", "pl"}, {"cz", "🇨🇿", "cs", "cs"}, {"se", "🇸🇪", "sv", "sv"},
    {"no", "🇳🇴", "no", "no"}, {"tr", "🇹🇷", "tr", "tr"}, {"il", "🇮🇱", "he", "he"}, {"jp", "🇯🇵", "ja", "ja"},
    {"kr", "🇰🇷", "ko", "ko"},
};

// The user's own feeds (tabletrc [Today] customFeeds): addresses separated by spaces, commas, new
// lines or ";", each optionally "URL|Name"; without a name the site's host is shown
QString customFeedSpec(const KConfigGroup &g)
{
    QStringList feeds;
    static const QRegularExpression sep(QStringLiteral("[\\s,;]+"));
    for (const QString &part : g.readEntry("customFeeds", QString()).split(sep, Qt::SkipEmptyParts)) {
        const QString url = part.section(QLatin1Char('|'), 0, 0);
        const QUrl u(url.contains(QLatin1String("://")) ? url : QStringLiteral("https://") + url);
        if (!u.isValid() || u.host().isEmpty() || (u.scheme() != QLatin1String("https") && u.scheme() != QLatin1String("http"))) {
            continue;
        }
        QString name = part.section(QLatin1Char('|'), 1);
        if (name.isEmpty()) {
            name = u.host().startsWith(QLatin1String("www.")) ? u.host().mid(4) : u.host();
        }
        feeds << u.toString() + QLatin1Char('|') + name;
    }
    return feeds.join(QLatin1Char(';'));
}

const Country &newsCountry(const KConfigGroup &g)
{
    const QString code = g.readEntry("newsCountry", QStringLiteral("ru")).toLower();
    for (const Country &c : countries) {
        if (code == QLatin1String(c.code)) {
            return c;
        }
    }
    return countries[0];
}

QString countryFeedSpec(const KConfigGroup &g, const Country &c)
{
    if (QLatin1String(c.code) == QLatin1String("ru")) {
        return g.readEntry("russiaFeeds", QStringLiteral("https://lenta.ru/rss/news/russia|Лента;https://tass.ru/rss/v2.xml|ТАСС"));
    }
    const QString gl = QString::fromLatin1(c.code).toUpper();
    return QStringLiteral("https://news.google.com/rss?hl=%1&gl=%2&ceid=%2:%3|Google News").arg(QLatin1String(c.hl), gl, QLatin1String(c.lang));
}

int today(bool force)
{
    const QFileInfo cache(todayCache);
    const QJsonObject cached = readJson(todayCache);
    // the feeds chosen in the settings: other feeds than the cached ones -> fetch now
    KConfig rc(QStringLiteral("tabletrc"), KConfig::SimpleConfig);
    const KConfigGroup g = rc.group(QStringLiteral("Today"));
    const Country &country = newsCountry(g);
    const QString linuxSpec = linuxFeedSpec(g), countrySpec = countryFeedSpec(g, country), customSpec = customFeedSpec(g);
    QString currency = g.readEntry("currency", QStringLiteral("auto")).toUpper();
    if (currency == QLatin1String("AUTO") || currency.size() != 3) {
        currency = countryCurrency(QLatin1String(country.code));
    }
    const QString spec = linuxSpec + QLatin1Char('\n') + countrySpec + QLatin1Char('\n') + customSpec + QLatin1Char('\n') + currency;
    const bool sameSpec = cached.value(QStringLiteral("spec")).toString() == spec;
    if (!force && sameSpec && cache.exists() && cache.lastModified().secsTo(QDateTime::currentDateTime()) < 30 * 60) {
        out(QString::fromUtf8(QJsonDocument(cached).toJson(QJsonDocument::Compact)) + QLatin1Char('\n'));
        return 0;
    }
    QNetworkAccessManager net;
    QJsonObject result{
        {QStringLiteral("linux"), newsGroup(net, linuxSpec, sameSpec ? cached.value(QStringLiteral("linux")).toArray() : QJsonArray())},
        {QStringLiteral("russia"), newsGroup(net, countrySpec, sameSpec ? cached.value(QStringLiteral("russia")).toArray() : QJsonArray())},
        {QStringLiteral("custom"), customSpec.isEmpty() ? QJsonArray()
                                   : newsGroup(net, customSpec, sameSpec ? cached.value(QStringLiteral("custom")).toArray() : QJsonArray())},
        {QStringLiteral("customTitle"), g.readEntry("customTitle", QString())},
        {QStringLiteral("country"), QLatin1String(country.code)},
        {QStringLiteral("countryFlag"), QString::fromUtf8(country.flag)},
        {QStringLiteral("spec"), spec},
        {QStringLiteral("rates"), exchangeRates(net, currency, cached.value(QStringLiteral("rates")).toObject())},
        {QStringLiteral("updated"), QDateTime::currentDateTime().toString(Qt::ISODate)},
    };
    const QString day = QDate::currentDate().toString(Qt::ISODate);
    if (cached.value(QStringLiteral("onthisdayDate")).toString() == day && !cached.value(QStringLiteral("onthisday")).toArray().isEmpty()) {
        result.insert(QStringLiteral("onthisday"), cached.value(QStringLiteral("onthisday")));
    } else {
        const QJsonArray events = onThisDay(net);
        result.insert(QStringLiteral("onthisday"), events.isEmpty() ? cached.value(QStringLiteral("onthisday")) : QJsonValue(events));
    }
    result.insert(QStringLiteral("onthisdayDate"), day);
    writePrivateJson(todayCache, result);
    out(QString::fromUtf8(QJsonDocument(result).toJson(QJsonDocument::Compact)) + QLatin1Char('\n'));
    return 0;
}

int dashboard(bool force, const QString &city)
{
    // good data is kept for 5 minutes, a failed refresh is retried after a minute
    const QFileInfo cache(dashboardCache);
    const QJsonObject cached = readJson(dashboardCache);
    const int maxAge = cached.value(QStringLiteral("retry")).toBool() ? 50 : 290;
    const QJsonObject cachedWeather = cached.value(QStringLiteral("weather")).toObject();
    const bool cityChanged = cachedWeather.value(QStringLiteral("city")).toString() != city
                          || (!city.isEmpty() && cachedWeather.value(QStringLiteral("source")).toString(QStringLiteral("openmeteo")) != weatherSource());
    if (!force && !cityChanged && cache.exists() && cache.lastModified().secsTo(QDateTime::currentDateTime()) < maxAge) {
        out(QString::fromUtf8(QJsonDocument(withLocal(readJson(dashboardCache))).toJson(QJsonDocument::Compact)) + QLatin1Char('\n'));
        return 0;
    }
    QNetworkAccessManager net;
    QJsonObject result{{QStringLiteral("claude"), claudeUsage(net)},
                       {QStringLiteral("youtube"), youtubeStats(net)},
                       {QStringLiteral("weather"), weather(net, city, cached.value(QStringLiteral("weather")).toObject())},
                       {QStringLiteral("updated"), QDateTime::currentDateTime().toString(Qt::ISODate)}};
    // no connection: keep the last good numbers (marked stale, with their time) and retry soon
    bool retry = false;
    auto keepOld = [&](const QString &section, const QString &marker, const QStringList &keys) {
        QJsonObject now = result.value(section).toObject();
        const QJsonObject old = cached.value(section).toObject();
        if (now.contains(marker) || !now.contains(QStringLiteral("error"))) {
            return;
        }
        retry = true;
        if (!old.contains(marker)) {
            return;
        }
        for (const QString &k : keys) {
            now.insert(k, old.value(k));
        }
        now.insert(QStringLiteral("stale"), true);
        now.insert(QStringLiteral("since"), old.value(QStringLiteral("since")).toString(cached.value(QStringLiteral("updated")).toString()));
        result.insert(section, now);
    };
    keepOld(QStringLiteral("claude"), QStringLiteral("session"), {QStringLiteral("session"), QStringLiteral("weekly"), QStringLiteral("plan")});
    keepOld(QStringLiteral("youtube"), QStringLiteral("subscribers"), {QStringLiteral("subscribers"), QStringLiteral("last28"), QStringLiteral("title")});
    if (retry) {
        result.insert(QStringLiteral("retry"), true);
    }
    writePrivateJson(dashboardCache, result);
    const QByteArray json = QJsonDocument(withLocal(result)).toJson(QJsonDocument::Compact);
    out(QString::fromUtf8(json) + QLatin1Char('\n'));
    return 0;
}

// Google sign-in for installed apps: browser + loopback redirect with PKCE
int youtubeLogin()
{
    const QJsonObject client = googleClient();
    if (client.value(QStringLiteral("client_id")).toString().isEmpty()) {
        std::fputs(qPrintable(T(QStringLiteral("Нет %1.\nGoogle Cloud Console -> APIs & Services: включите YouTube Data API v3 и YouTube Analytics API,\n"
                                               "Credentials -> Create OAuth client ID -> Desktop app -> Download JSON и сохраните его по этому пути.\n"))
                                   .arg(googleClientPath)),
                   stderr);
        return 1;
    }
    QTcpServer server;
    if (!server.listen(QHostAddress::LocalHost)) {
        return 1;
    }
    const QString redirect = QStringLiteral("http://127.0.0.1:%1").arg(server.serverPort());
    QByteArray verifier;
    for (int i = 0; i < 48; ++i) {
        verifier += "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"[QRandomGenerator::system()->bounded(66)];
    }
    const QByteArray challenge = QCryptographicHash::hash(verifier, QCryptographicHash::Sha256)
                                     .toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals);
    QUrl auth(QStringLiteral("https://accounts.google.com/o/oauth2/v2/auth"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("client_id"), client.value(QStringLiteral("client_id")).toString());
    q.addQueryItem(QStringLiteral("redirect_uri"), redirect);
    q.addQueryItem(QStringLiteral("response_type"), QStringLiteral("code"));
    q.addQueryItem(QStringLiteral("scope"), QStringLiteral("https://www.googleapis.com/auth/youtube.readonly https://www.googleapis.com/auth/yt-analytics.readonly"));
    q.addQueryItem(QStringLiteral("code_challenge"), QString::fromLatin1(challenge));
    q.addQueryItem(QStringLiteral("code_challenge_method"), QStringLiteral("S256"));
    q.addQueryItem(QStringLiteral("access_type"), QStringLiteral("offline"));
    q.addQueryItem(QStringLiteral("prompt"), QStringLiteral("consent"));
    auth.setQuery(q);
    std::fprintf(stderr, "%s\n%s\n", qPrintable(T(T(QStringLiteral("Открываю браузер для входа в Google...")))), auth.toString(QUrl::FullyEncoded).toLocal8Bit().constData());
    QProcess::startDetached(QStringLiteral("xdg-open"), {auth.toString(QUrl::FullyEncoded)});

    QString code;
    while (code.isEmpty()) {
        if (!server.waitForNewConnection(300000)) {
            std::fprintf(stderr, "%s\n", qPrintable(T(T(QStringLiteral("Время вышло.")))));
            return 1;
        }
        QTcpSocket *sock = server.nextPendingConnection();
        sock->waitForReadyRead(5000);
        const QString line = QString::fromUtf8(sock->readLine());
        const QUrlQuery got(QUrl(line.section(QLatin1Char(' '), 1, 1)).query());
        code = got.queryItemValue(QStringLiteral("code"));
        const QByteArray page = (code.isEmpty() ? T(T(QStringLiteral("Вход не выполнен. Можно закрыть вкладку."))) : T(T(QStringLiteral("Готово, можно закрыть вкладку.")))).toUtf8();
        sock->write("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<h2>" + page + "</h2>");
        sock->waitForBytesWritten(2000);
        sock->disconnectFromHost();
        if (code.isEmpty() && got.hasQueryItem(QStringLiteral("error"))) {
            return 1;
        }
    }
    QNetworkAccessManager net;
    QUrlQuery t;
    t.addQueryItem(QStringLiteral("client_id"), client.value(QStringLiteral("client_id")).toString());
    t.addQueryItem(QStringLiteral("client_secret"), client.value(QStringLiteral("client_secret")).toString());
    t.addQueryItem(QStringLiteral("code"), code);
    t.addQueryItem(QStringLiteral("code_verifier"), QString::fromLatin1(verifier));
    t.addQueryItem(QStringLiteral("redirect_uri"), redirect);
    t.addQueryItem(QStringLiteral("grant_type"), QStringLiteral("authorization_code"));
    QNetworkRequest req(QUrl(QStringLiteral("https://oauth2.googleapis.com/token")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/x-www-form-urlencoded"));
    const Response r = request(net, req, t.query(QUrl::FullyEncoded).toUtf8());
    QJsonObject token = QJsonDocument::fromJson(r.data).object();
    if (r.status != 200 || token.value(QStringLiteral("refresh_token")).toString().isEmpty()) {
        std::fprintf(stderr, "%s (%d): %s\n", qPrintable(T(T(QStringLiteral("Google не выдал токен")))), r.status, r.data.constData());
        return 1;
    }
    token.insert(QStringLiteral("expires_at"), QDateTime::currentSecsSinceEpoch() + token.value(QStringLiteral("expires_in")).toInt(3600));
    writePrivateJson(googleTokenPath, token);
    std::fprintf(stderr, "%s\n", qPrintable(T(T(QStringLiteral("Вход выполнен.")))));
    return dashboard(true, QString());
}
} // namespace

int main(int argc, char *argv[])
{
    // Keep Qt diagnostics silent without an app-local helper declaration.
    // TABLET_SHELL_DEBUG=1 keeps Qt/QML messages for troubleshooting
    if (!qEnvironmentVariableIsSet("TABLET_SHELL_DEBUG")) qInstallMessageHandler([](QtMsgType, const QMessageLogContext &, const QString &) {});
    QStringList args;
    for (int i = 0; i < argc; ++i) {
        args << QString::fromLocal8Bit(argv[i]);
    }
    QString tool = QFileInfo(args.takeFirst()).fileName();
    if (tool == QLatin1String("tablet-tools") && !args.isEmpty()) {
        tool = args.takeFirst();
    }

    if (tool == QLatin1String("typewriter-export")) {
        qputenv("QT_QPA_PLATFORM", "offscreen"); // fonts and the PDF painter, no window
        QGuiApplication app(argc, argv);
        if (args.size() >= 2) {
            return typewriterExportCommand(args[0], args[1], args.value(2));
        }
        std::fputs("usage: typewriter-export FILE pdf|docx|epub [OUT]\n", stderr);
        return 2;
    }
    if (tool == QLatin1String("app-icons")) {
        qputenv("QT_QPA_PLATFORM", "offscreen"); // painting icons, no window
        QGuiApplication app(argc, argv);
        return appIconsCommand(args);
    }
    if (tool == QLatin1String("webapp-create")) {
        qputenv("QT_QPA_PLATFORM", "offscreen"); // painting icons, no window
        QGuiApplication app(argc, argv);
        if (args.size() == 2 && args[0] == QLatin1String("--remove")) {
            return webappRemove(args[1]);
        }
        if (args.size() == 2) {
            return webappCreate(args[0], args[1]);
        }
        std::fputs("usage: webapp-create NAME URL | --remove ID\n", stderr);
        return 2;
    }
    QCoreApplication app(argc, argv);
    if (tool == QLatin1String("wallpaper")) {
        if (args.size() >= 1 && args[0] == QLatin1String("list")) {
            return wallpaperList();
        }
        if (args.size() == 2 && args[0] == QLatin1String("set")) {
            return wallpaperSet(args[1]);
        }
        if (args.size() == 2 && args[0] == QLatin1String("live")) {
            return wallpaperLive(args[1] == QLatin1String("on"));
        }
        if (args.size() == 1 && args[0] == QLatin1String("sync")) {
            syncGreeterWallpaper();
            return 0;
        }
        std::fputs("usage: wallpaper list | wallpaper set PATH | wallpaper live on|off | wallpaper sync\n", stderr);
        return 2;
    }
    if (tool == QLatin1String("today")) {
        return today(args.contains(QStringLiteral("--force")));
    }
    if (tool == QLatin1String("typewriter-runtime") && args.size() == 1) {
        return typewriterRuntimeCommand(args[0]);
    }
    if (tool == QLatin1String("cleanup")) {
        return cleanup(args);
    }
    if (tool == QLatin1String("weekly")) {
        return weekly();
    }
    if (tool == QLatin1String("typewriter-stats")) {
        return typewriterStatsCommand();
    }
    if (tool == QLatin1String("screentime-apps")) {
        return screentimeApps(args);
    }
    if (tool == QLatin1String("dashboard")) {
        if (args.contains(QLatin1String("--local"))) {
            out(QString::fromUtf8(QJsonDocument(withLocal({})).toJson(QJsonDocument::Compact)) + QLatin1Char('\n'));
            return 0;
        }
        const int w = args.indexOf(QLatin1String("--weather"));
        return dashboard(args.contains(QLatin1String("--force")), w >= 0 ? args.value(w + 1) : QString());
    }
    if (tool == QLatin1String("youtube-login")) {
        return youtubeLogin();
    }
    if (tool == QLatin1String("hardware")) {
        return hardware();
    }
    std::fputs("usage: tablet-tools webapp-create|wallpaper|screentime-apps|dashboard|youtube-login|hardware|app-icons ...\n", stderr);
    return 2;
}
