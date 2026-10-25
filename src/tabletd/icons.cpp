// App icons in the style of the MacTahoe icon theme, for the apps the theme has no icon for
// (tablet-tools app-icons [--force]):
//   - the theme's look is measured from its own icons (size and place of the squircle), so a new
//     icon lines up with the rest on the home screen, in the dock and in menus
//   - first the theme's own icon under another name is looked for (Claude -> "claude", Haruna ->
//     "org.kde.haruna", Contacts -> "contacts": parts of the desktop file name, the app name) and
//     linked; only apps without any get a drawn icon
//   - the app's own icon decides the drawing: a filled square or round picture (Haruna, Android
//     apps) fills the squircle, its corners in the picture's edge colour; a free-standing logo
//     (Throne) sits on a plate; flat, with the theme's faint shadow (no extra rim or sheen, which
//     made drawn icons stand out among the theme's own)
//   - written as SVG (a PNG inside) into MacTahoe/apps/scalable, which the -light and -dark
//     variants share. Apps of ~/.local/share/applications with an absolute icon path (Waydroid,
//     web apps) get a themed name instead: Icon= is rewritten, the old path kept as
//     X-TabletShell-Icon (and used again by --force)
// Already generated icons are kept unless --force; re-run after installing apps or the theme.
#include <QBuffer>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QIcon>
#include <QImage>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QSettings>
#include <QStandardPaths>
#include <QTextStream>
#include <QTransform>

#include <cmath>
#include <cstdio>

namespace appicons
{
const QString home = QDir::homePath();
// The same app mapping is run for both style families; Apple stays untouched.
QString theme = QStringLiteral("MacTahoe");
QString themeDir = home + QStringLiteral("/.local/share/icons/") + theme;
QString outDir = themeDir + QStringLiteral("/apps/scalable");
bool pixelTheme = false;
const QByteArray marker = "<!-- tablet-shell app-icons -->";
constexpr int S = 512; // drawing size

bool generatedByUs(const QString &name)
{
    QFile f(outDir + QLatin1Char('/') + name + QStringLiteral(".svg"));
    return f.open(QIODevice::ReadOnly) && f.read(400).contains(marker);
}

// every icon name the theme has (any context, any size) -> one of its files (scalable apps first)
QHash<QString, QString> themeNames()
{
    QHash<QString, QString> names;
    QStringList dirs{themeDir};
    if (pixelTheme) {
        const QString share = home + QStringLiteral("/.local/share/icons/");
        for (const auto &name : {QStringLiteral("Colloid"), QStringLiteral("Colloid-Dark"),
                                 QStringLiteral("Colloid-Light")}) {
            dirs << share + name;
        }
    }
    for (const QString &dir : dirs) {
        if (!QDir(dir).exists()) continue;
        QDirIterator it(dir, {QStringLiteral("*.svg"), QStringLiteral("*.png")}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString path = it.next();
            const QString name = QFileInfo(path).completeBaseName();
            if (!names.contains(name) || path.startsWith(outDir + QLatin1Char('/'))) {
                names.insert(name, path);
            }
        }
    }
    return names;
}

// the theme's icon for this app under another name: desktop file name, its parts, the app name
QString aliasFor(const QString &desktopId, const QString &appName, const QHash<QString, QString> &have)
{
    QStringList candidates;
    const QString base = desktopId.chopped(desktopId.endsWith(QLatin1String(".desktop")) ? 8 : 0);
    candidates << base << base.toLower();
    const QStringList parts = base.split(QLatin1Char('.'));
    if (parts.size() > 1) {
        candidates << parts.last() << parts.last().toLower();
    }
    QString name = appName.trimmed().toLower();
    candidates << name << name.replace(QLatin1Char(' '), QLatin1Char('-'));
    for (const QString &c : candidates) {
        if (!c.isEmpty() && !c.startsWith(QLatin1String("tablet-")) && have.contains(c) && !generatedByUs(c)) {
            return have.value(c);
        }
    }
    return {};
}

QImage render(const QIcon &icon)
{
    if (icon.isNull()) {
        return {};
    }
    QImage img = icon.pixmap(QSize(S, S)).toImage().convertToFormat(QImage::Format_ARGB32_Premultiplied);
    if (!img.isNull() && img.width() != S) {
        img = img.scaled(S, S, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    return img;
}

// the app's own icon: an absolute path, or a name looked up outside the MacTahoe theme
QImage source(const QString &icon)
{
    if (icon.startsWith(QLatin1Char('/'))) {
        QImage img(icon);
        if (img.isNull()) {
            return {};
        }
        return render(QIcon(QPixmap::fromImage(img)));
    }
    // Pixel: the Material (Colloid) logo when there is one, the app's own otherwise
    const bool colloid = pixelTheme && QFile::exists(home + QStringLiteral("/.local/share/icons/Colloid/index.theme"));
    QIcon::setThemeName(colloid ? QStringLiteral("Colloid") : QStringLiteral("hicolor"));
    QImage img = render(QIcon::fromTheme(icon));
    if (img.isNull()) {
        for (const QString &ext : {QStringLiteral(".svg"), QStringLiteral(".png"), QStringLiteral(".xpm")}) {
            const QString p = QStringLiteral("/usr/share/pixmaps/") + icon + ext;
            if (QFile::exists(p)) {
                img = render(QIcon(p));
                break;
            }
        }
    }
    return img;
}

// box of the opaque pixels, and how much of that box they cover
QRectF opaqueBox(const QImage &img, double *fill)
{
    int minX = img.width(), minY = img.height(), maxX = -1, maxY = -1;
    qint64 opaque = 0;
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            if (qAlpha(line[x]) > 128) {
                ++opaque;
                minX = std::min(minX, x);
                maxX = std::max(maxX, x);
                minY = std::min(minY, y);
                maxY = std::max(maxY, y);
            }
        }
    }
    if (maxX < 0) {
        *fill = 0;
        return {};
    }
    const QRectF box(minX, minY, maxX - minX + 1, maxY - minY + 1);
    *fill = opaque / (box.width() * box.height());
    return box;
}

// where the theme draws its squircle: measured from a few of its own app icons
QRectF themeSquircle()
{
    if (pixelTheme) return QRectF(S * 0.065, S * 0.065, S * 0.87, S * 0.87);
    QIcon::setThemeName(theme);
    for (const QString &name : {QStringLiteral("firefox"), QStringLiteral("utilities-terminal"), QStringLiteral("org.kde.konsole"),
                                QStringLiteral("preferences-system")}) {
        double fill = 0;
        const QRectF box = opaqueBox(render(QIcon::fromTheme(name)), &fill);
        if (fill > 0.85 && std::abs(box.width() - box.height()) < S * 0.04) {
            return box;
        }
    }
    return QRectF(S * 0.1, S * 0.1, S * 0.8, S * 0.8);
}

// Apple's continuous-corner squircle (a superellipse). The expensive
// trigonometry + fractional powers only depend on n=5, so compute the unit
// contour once; map it to each rectangle with a cheap affine transform.
QPainterPath squircle(const QRectF &r)
{
    static const QPainterPath unit = [] {
        QPainterPath path;
        constexpr double n = 5.0;
        for (int i = 0; i <= 256; ++i) {
            const double t = i * 2 * M_PI / 256;
            const double ct = std::cos(t), st = std::sin(t);
            const QPointF p(std::copysign(std::pow(std::abs(ct), 2 / n), ct),
                            std::copysign(std::pow(std::abs(st), 2 / n), st));
            if (i == 0) path.moveTo(p);
            else path.lineTo(p);
        }
        path.closeSubpath();
        return path;
    }();
    QTransform transform;
    transform.translate(r.center().x(), r.center().y());
    transform.scale(r.width() / 2, r.height() / 2);
    return transform.map(unit);
}

// average colour of the picture just inside its outline (square and round pictures alike)
QColor edgeColour(const QImage &img, const QRectF &box)
{
    double r = 0, g = 0, b = 0, n = 0;
    auto add = [&](double x, double y) {
        const QRgb px = img.pixel(std::clamp(int(x), 0, img.width() - 1), std::clamp(int(y), 0, img.height() - 1));
        if (qAlpha(px) > 200) {
            r += qRed(px), g += qGreen(px), b += qBlue(px), n += 1;
        }
    };
    const QPointF c = box.center();
    const double inset = box.width() * 0.04;
    for (int i = 0; i < 360; ++i) {
        const double t = i * M_PI / 180;
        add(c.x() + (box.width() / 2 - inset) * std::cos(t), c.y() + (box.height() / 2 - inset) * std::sin(t));
    }
    for (int i = 0; i < 100; ++i) {
        const double f = i / 100.0;
        add(box.left() + inset + f * (box.width() - 2 * inset), box.top() + inset);
        add(box.left() + inset + f * (box.width() - 2 * inset), box.bottom() - inset);
        add(box.left() + inset, box.top() + inset + f * (box.height() - 2 * inset));
        add(box.right() - inset, box.top() + inset + f * (box.height() - 2 * inset));
    }
    return n > 0 ? QColor(int(r / n), int(g / n), int(b / n)) : QColor(Qt::white);
}

double lightness(const QImage &img)
{
    double sum = 0, n = 0;
    for (int y = 0; y < img.height(); y += 4) {
        for (int x = 0; x < img.width(); x += 4) {
            const QRgb px = img.pixel(x, y);
            if (qAlpha(px) > 128) {
                const double a = qAlpha(px) / 255.0;
                sum += (0.2126 * qRed(px) + 0.7152 * qGreen(px) + 0.0722 * qBlue(px)) / a / 255.0;
                n += 1;
            }
        }
    }
    return n > 0 ? sum / n : 0;
}

QImage draw(const QImage &src, const QRectF &sq)
{
    QImage out(S, S, QImage::Format_ARGB32_Premultiplied);
    out.fill(Qt::transparent);
    QPainter p(&out);
    p.setRenderHints(QPainter::Antialiasing | QPainter::SmoothPixmapTransform);
    const QPainterPath shape = squircle(sq);

    // soft shadow like the theme's own icons: a few widening, very faint copies a little below
    p.setPen(Qt::NoPen);
    for (int i = 6; i >= 1; --i) {
        const double grow = i * S * 0.003;
        p.setBrush(QColor(0, 0, 0, 5));
        p.drawPath(squircle(sq.adjusted(-grow, -grow + S * 0.008, grow, grow + S * 0.008)));
    }

    double fill = 0;
    const QRectF box = opaqueBox(src, &fill);
    const bool squareBox = std::abs(box.width() - box.height()) < S * 0.08;
    p.save();
    p.setClipPath(shape);
    if (squareBox && fill >= 0.72) {
        // a filled square or round picture: it becomes the whole icon
        p.fillPath(shape, edgeColour(src, box));
        p.drawImage(sq, src, box);
    } else {
        // a free-standing logo on a plate (dark under a light logo)
        const bool lightLogo = lightness(src) > 0.82;
        QLinearGradient plate(sq.topLeft(), sq.bottomLeft());
        plate.setColorAt(0, lightLogo ? QColor(0x48, 0x48, 0x4c) : QColor(0xff, 0xff, 0xff));
        plate.setColorAt(1, lightLogo ? QColor(0x1c, 0x1c, 0x1e) : QColor(0xec, 0xec, 0xf1));
        p.fillPath(shape, plate);
        const double side = sq.width() * 0.66;
        QSizeF size = box.size().scaled(side, side, Qt::KeepAspectRatio);
        const QRectF target(sq.center().x() - size.width() / 2, sq.center().y() - size.height() / 2, size.width(), size.height());
        p.drawImage(target, src, box);
    }
    p.restore();
    // no sheen or glass rim: the theme's icons are flat, a drawn icon must not stand out among them
    p.end();
    return out;
}

// A distinct Pixel-adaptive circle, instead of the Apple superellipse.
QImage drawPixel(const QImage &src, const QRectF &rect)
{
    QImage out(S, S, QImage::Format_ARGB32_Premultiplied);
    out.fill(Qt::transparent);
    if (src.isNull()) return out;
    QPainter p(&out);
    p.setRenderHints(QPainter::Antialiasing | QPainter::SmoothPixmapTransform);
    const QRectF circle = rect.adjusted(8, 8, -8, -8);
    QPainterPath clip; clip.addEllipse(circle);
    p.setPen(Qt::NoPen);
    p.setBrush(QColor(0,0,0,15));
    p.drawEllipse(circle.translated(0,7));
    p.setClipPath(clip);
    double fill = 0;
    const QRectF box = opaqueBox(src, &fill);
    if (box.isEmpty()) return out;
    const bool full = fill >= 0.69 && std::abs(box.width() - box.height()) < S * 0.18;
    if (full) {
        p.fillPath(clip, edgeColour(src, box));
        p.drawImage(circle, src, box);
    } else {
        const bool bright = lightness(src) > 0.74;
        p.fillPath(clip, bright ? QColor("#292D39") : QColor("#E8DEF8"));
        const double side = circle.width() * 0.62;
        QSizeF sz = box.size().scaled(side, side, Qt::KeepAspectRatio);
        const QRectF target(circle.center().x()-sz.width()/2, circle.center().y()-sz.height()/2,
                             sz.width(), sz.height());
        p.drawImage(target, src, box);
    }
    return out;
}

bool save(const QImage &img, const QString &name)
{
    QByteArray png;
    QBuffer buf(&png);
    buf.open(QIODevice::WriteOnly);
    img.save(&buf, "PNG");
    const QString path = outDir + QLatin1Char('/') + name + QStringLiteral(".svg");
    if (QFileInfo(path).isSymLink()) {
        QFile::remove(path);  // an alias of an earlier run: never write through it into another theme
    }
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }
    f.write("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"512\" height=\"512\" "
            "viewBox=\"0 0 512 512\">" + marker + "<image width=\"512\" height=\"512\" xlink:href=\"data:image/png;base64,"
            + png.toBase64() + "\"/></svg>\n");
    return true;
}

// ~/.local/share/applications entry with an absolute icon path: give it a themed name
QString rename(const QString &path, const QString &oldIcon)
{
    const QString name = QStringLiteral("tablet-") + QFileInfo(path).completeBaseName();
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        return {};
    }
    QStringList lines = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
    f.close();
    bool inEntry = false, done = false;
    for (int i = 0; i < lines.size() && !done; ++i) {
        if (lines[i].startsWith(QLatin1Char('['))) {
            inEntry = lines[i].trimmed() == QLatin1String("[Desktop Entry]");
        } else if (inEntry && lines[i].startsWith(QLatin1String("Icon="))) {
            lines[i] = QStringLiteral("Icon=") + name;
            lines.insert(i + 1, QStringLiteral("X-TabletShell-Icon=") + oldIcon);
            done = true;
        }
    }
    if (!done || !f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return {};
    }
    f.write(lines.join(QLatin1Char('\n')).toUtf8());
    return name;
}
} // namespace appicons

int appIconsCommand(const QStringList &args)
{
    using namespace appicons;
    pixelTheme = args.contains(QStringLiteral("--pixel"));
    theme = pixelTheme ? QStringLiteral("TabletPixel") : QStringLiteral("MacTahoe");
    themeDir = home + QStringLiteral("/.local/share/icons/") + theme;
    outDir = themeDir + QStringLiteral("/apps/scalable");
    if (!QFile::exists(themeDir + QStringLiteral("/index.theme"))) {
        std::fprintf(stderr, "app-icons: icon theme %s is not installed\n", qPrintable(theme));
        return 1;
    }
    const bool force = args.contains(QStringLiteral("--force"));
    QDir().mkpath(outDir);
    QIcon::setThemeSearchPaths({home + QStringLiteral("/.local/share/icons"), QStringLiteral("/usr/local/share/icons"),
                                QStringLiteral("/usr/share/icons")});
    QIcon::setFallbackThemeName(QStringLiteral("hicolor"));
    const QHash<QString, QString> have = themeNames();
    const QRectF sq = themeSquircle();
    const QString userApps = home + QStringLiteral("/.local/share/applications");

    QSet<QString> seen;
    int made = 0;
    bool renamed = false;
    const QStringList dirs = {userApps, home + QStringLiteral("/.local/share/flatpak/exports/share/applications"),
                              QStringLiteral("/var/lib/flatpak/exports/share/applications"), QStringLiteral("/usr/share/applications")};
    for (const QString &dir : dirs) {
        QDirIterator it(dir, {QStringLiteral("*.desktop")}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString path = it.next();
            const QString id = QDir(dir).relativeFilePath(path).replace(QLatin1Char('/'), QLatin1Char('-'));
            if (seen.contains(id)) {
                continue;
            }
            seen.insert(id);
            QSettings entry(path, QSettings::IniFormat);
            entry.beginGroup(QStringLiteral("Desktop Entry"));
            const QString only = entry.value(QStringLiteral("OnlyShowIn")).toString();
            if (entry.value(QStringLiteral("Type")).toString() != QLatin1String("Application")
                || entry.value(QStringLiteral("NoDisplay")).toString() == QLatin1String("true")
                || entry.value(QStringLiteral("Hidden")).toString() == QLatin1String("true")
                || (!only.isEmpty() && !only.contains(QLatin1String("KDE")))) {
                continue;
            }
            QString icon = entry.value(QStringLiteral("Icon")).toString();
            const QString original = entry.value(QStringLiteral("X-TabletShell-Icon")).toString();
            if (icon.isEmpty()) {
                continue;
            }
            const bool ours = generatedByUs(icon);
            if (pixelTheme) {
                // Pixel draws EVERY app round (Colloid's rounded squares included), so the dock,
                // menus and the task switcher match the round home screen icons. Hand-made icons
                // of the theme (scalable/apps) stay; drawn ones are redrawn only with --force.
                if (QFile::exists(themeDir + QStringLiteral("/scalable/apps/") + icon + QStringLiteral(".svg"))
                    || ((ours || QFileInfo(outDir + QLatin1Char('/') + icon + QStringLiteral(".svg")).isSymLink()) && !force)) {
                    continue;
                }
            } else if (have.contains(icon) && !(force && ours)) {
                continue;  // the theme has it (or we made it before)
            }
            const QString alias = pixelTheme ? QString() : aliasFor(id, entry.value(QStringLiteral("Name")).toString(), have);
            const QImage src = alias.isEmpty() ? source(!original.isEmpty() ? original : icon) : QImage();
            if (alias.isEmpty() && src.isNull()) {
                std::fprintf(stderr, "app-icons: no picture for %s (%s)\n", qPrintable(id), qPrintable(icon));
                continue;
            }
            QString name = icon;
            if (icon.startsWith(QLatin1Char('/'))) {
                if (!path.startsWith(userApps + QLatin1Char('/'))) {
                    continue;  // a system entry pointing at a file: cannot give it a name
                }
                name = rename(path, icon);
                if (name.isEmpty()) {
                    continue;
                }
                renamed = true;
            }
            if (!alias.isEmpty()) {
                const QString link = outDir + QLatin1Char('/') + name + QStringLiteral(".svg");
                QFile::remove(link);
                if (QFile::link(QDir(outDir).relativeFilePath(alias), link)) {
                    ++made;
                    std::printf("%s\t%s\t-> %s\n", qPrintable(name), qPrintable(id), qPrintable(QFileInfo(alias).fileName()));
                }
                continue;
            }
            if (save(pixelTheme ? drawPixel(src, sq) : draw(src, sq), name)) {
                ++made;
                std::printf("%s\t%s\n", qPrintable(name), qPrintable(id));
            }
        }
    }
    if (made > 0) {
        QProcess::execute(QStringLiteral("gtk-update-icon-cache"), {QStringLiteral("-f"), QStringLiteral("-q"), themeDir});
    }
    if (renamed) {
        QProcess::startDetached(QStringLiteral("kbuildsycoca6"), {});
    }
    return 0;
}
