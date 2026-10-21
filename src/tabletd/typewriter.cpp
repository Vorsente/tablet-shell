// Typewriter (ghostwriter screenplays in ~/Сценарии) for tablet-tools:
//   typewriter-stats                  JSON: words today (live while writing), goal, streak, best day,
//                                     the last 14 days
//   typewriter-export FILE pdf|docx|epub [OUT]
//                                     screenplay manuscript in the standard layout (Courier 12 pt,
//                                     A4, scene headings / action / character / parenthetical /
//                                     dialogue / transition indents); prints the output path
// The Markdown dialect is the one of ~/.local/share/typewriter/template.md:
//   # TITLE, *Author* · *draft*, ## 1. INT. PLACE — TIME, **CHARACTER**, *(parenthetical)*,
//   > dialogue, UPPERCASE TRANSITION: lines, anything else is action.
#include <KConfig>
#include <KConfigGroup>

#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFontDatabase>
#include <QFontMetricsF>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPainter>
#include <QPdfWriter>
#include <QRegularExpression>
#include <QStandardPaths>

#include <cstdio>

#include "tr.h"

namespace typewriter
{
const QString dataDir = QDir::homePath() + QStringLiteral("/.local/share/typewriter");

int wordsOn(const QDate &day)
{
    QFile f(dataDir + QStringLiteral("/words-") + day.toString(Qt::ISODate));
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).trimmed().toInt() : 0;
}

// While the typewriter runs, its pill keeps today's running total in the runtime dir
int wordsToday()
{
    int words = wordsOn(QDate::currentDate());
    QFile live(QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + QStringLiteral("/typewriter-live"));
    if (live.open(QIODevice::ReadOnly) && QFileInfo(live).lastModified().date() == QDate::currentDate()) {
        words = std::max(words, QString::fromUtf8(live.readAll()).trimmed().toInt());
    }
    return words;
}

QJsonObject stats()
{
    KConfig cfg(QStringLiteral("typewriterrc"), KConfig::SimpleConfig);
    const int goal = cfg.group(QStringLiteral("General")).readEntry("dailyGoal", 500);
    const QDate today = QDate::currentDate();
    const int todayWords = wordsToday();

    // streak: days in a row with the goal reached; today only counts once it is reached
    int streak = 0;
    QDate d = todayWords >= goal ? today : today.addDays(-1);
    while (goal > 0 && (d == today ? todayWords : wordsOn(d)) >= goal) {
        ++streak;
        d = d.addDays(-1);
    }
    QJsonArray days;
    for (int i = 13; i >= 0; --i) {
        const QDate day = today.addDays(-i);
        days.append(QJsonObject{{QStringLiteral("date"), day.toString(Qt::ISODate)},
                                {QStringLiteral("words"), i == 0 ? todayWords : wordsOn(day)}});
    }
    int best = 0, total = 0;
    const auto files = QDir(dataDir).entryList({QStringLiteral("words-*")}, QDir::Files);
    for (const QString &f : files) {
        const int w = f == QStringLiteral("words-") + today.toString(Qt::ISODate) ? todayWords : wordsOn(QDate::fromString(f.mid(6), Qt::ISODate));
        best = std::max(best, w);
        total += w;
    }
    return {{QStringLiteral("words"), todayWords}, {QStringLiteral("goal"), goal}, {QStringLiteral("streak"), streak},
            {QStringLiteral("best"), best}, {QStringLiteral("total"), total}, {QStringLiteral("days"), days}};
}

// ---- screenplay ------------------------------------------------------------------------------

enum class Kind { Scene, Action, Character, Parenthetical, Dialogue, Transition };
struct Element {
    Kind kind;
    QString text;
};
struct Script {
    QString title, author, draft;
    QList<Element> body;
};

QString plain(QString s)
{
    s.remove(QRegularExpression(QStringLiteral("\\*\\*|\\*|__|`")));
    return s.trimmed();
}

Script parse(const QString &markdown)
{
    Script script;
    const QStringList lines = markdown.split(QLatin1Char('\n'));
    static const QRegularExpression character(QStringLiteral("^\\*\\*([^*]+)\\*\\*$"));
    static const QRegularExpression parenthetical(QStringLiteral("^\\*?\\((.+)\\)\\*?$"));
    QStringList action;
    auto flushAction = [&] {
        if (!action.isEmpty()) {
            script.body.append({Kind::Action, plain(action.join(QLatin1Char(' ')))});
            action.clear();
        }
    };
    bool bylineNext = false;
    for (const QString &raw : lines) {
        const QString line = raw.trimmed();
        if (line.isEmpty() || line == QLatin1String("---") || line == QLatin1String("***")) {
            flushAction();
            continue;
        }
        if (line.startsWith(QLatin1String("# "))) {
            flushAction();
            script.title = plain(line.mid(2));
            bylineNext = true;
            continue;
        }
        if (bylineNext && script.body.isEmpty() && line.startsWith(QLatin1Char('*')) && !character.match(line).hasMatch()) {
            const QStringList parts = line.split(QChar(0x00B7));   // "*Author* · *draft of DATE*"
            script.author = plain(parts.value(0));
            script.draft = plain(parts.mid(1).join(QLatin1Char(' ')));
            bylineNext = false;
            continue;
        }
        bylineNext = false;
        if (line.startsWith(QLatin1String("## ")) || line.startsWith(QLatin1String("### "))) {
            flushAction();
            script.body.append({Kind::Scene, plain(line.section(QLatin1Char(' '), 1)).toUpper()});
        } else if (const auto m = character.match(line); m.hasMatch()) {
            flushAction();
            script.body.append({Kind::Character, m.captured(1).trimmed().toUpper()});
        } else if (const auto p = parenthetical.match(line); p.hasMatch() && !script.body.isEmpty()
                   && (script.body.last().kind == Kind::Character || script.body.last().kind == Kind::Dialogue)) {
            flushAction();
            script.body.append({Kind::Parenthetical, QLatin1Char('(') + plain(p.captured(1)) + QLatin1Char(')')});
        } else if (line.startsWith(QLatin1Char('>'))) {
            flushAction();
            const QString text = plain(line.mid(1));
            if (!script.body.isEmpty() && script.body.last().kind == Kind::Dialogue) {
                script.body.last().text += QLatin1Char(' ') + text;
            } else {
                script.body.append({Kind::Dialogue, text});
            }
        } else if (line.contains(QLatin1Char(':')) && line == line.toUpper() && line.size() < 40 && line.contains(QRegularExpression(QStringLiteral("\\p{L}")))) {
            flushAction();
            script.body.append({Kind::Transition, plain(line)});
        } else {
            action.append(line);
        }
    }
    flushAction();
    if (script.title.isEmpty()) {
        script.title = T(QStringLiteral("БЕЗ НАЗВАНИЯ"));
    }
    return script;
}

// Layout in inches from the left page edge (US/Russian screenplay convention), A4 page
struct Indent {
    double left, width;
    bool blankBefore;
};
Indent indentOf(Kind k)
{
    switch (k) {
    case Kind::Scene: return {1.5, 6.0, true};
    case Kind::Action: return {1.5, 6.0, true};
    case Kind::Character: return {3.7, 3.3, true};
    case Kind::Parenthetical: return {3.1, 2.0, false};
    case Kind::Dialogue: return {2.5, 3.5, false};
    case Kind::Transition: return {1.5, 6.0, true};
    }
    return {1.5, 6.0, true};
}

QStringList wrap(const QString &text, int chars)
{
    QStringList out;
    QString line;
    for (const QString &word : text.split(QLatin1Char(' '), Qt::SkipEmptyParts)) {
        if (!line.isEmpty() && line.size() + 1 + word.size() > chars) {
            out.append(line);
            line.clear();
        }
        line += (line.isEmpty() ? QString() : QStringLiteral(" ")) + word;
    }
    if (!line.isEmpty() || out.isEmpty()) {
        out.append(line);
    }
    return out;
}

QString fontFamily()
{
    static QString family;
    if (family.isEmpty()) {
        const QString dir = QDir::homePath() + QStringLiteral("/.local/share/fonts/Cousine/");
        for (const char *f : {"Cousine-Regular.ttf", "Cousine-Bold.ttf"}) {
            const int id = QFontDatabase::addApplicationFont(dir + QLatin1String(f));
            if (id >= 0 && family.isEmpty()) {
                family = QFontDatabase::applicationFontFamilies(id).value(0);
            }
        }
        if (family.isEmpty()) {
            family = QStringLiteral("Courier New");
        }
    }
    return family;
}

// The page layout, shared by the PDF and the running time: the title page, then elements line by
// line, a scene heading or a character cue kept with what follows. Calls row(element, indent, text,
// line on the page) for every printed line and newPage(page number) for every new page. Returns
// the body length in pages (the last one counted by its filled part).
template<typename Row, typename NewPage>
double layout(const Script &s, int linesPerPage, Row row, NewPage newPage, QList<double> *sceneStarts = nullptr)
{
    int page = 1, line = linesPerPage;   // the first body element starts a new page
    auto next = [&] {
        ++page;
        line = 0;
        newPage(page);
    };
    for (int i = 0; i < s.body.size(); ++i) {
        const Element &e = s.body[i];
        const Indent in = indentOf(e.kind);
        const QStringList rows = wrap(e.text, int(in.width * 10));
        const int before = (in.blankBefore && line > 0) ? 1 : 0;
        int need = before + rows.size();
        if ((e.kind == Kind::Scene || e.kind == Kind::Character) && i + 1 < s.body.size()) {
            need += 1 + (s.body[i + 1].kind == Kind::Action ? 1 : 0);
        }
        if (line + need > linesPerPage && line > 0) {
            next();
        } else {
            line += before;
        }
        if (e.kind == Kind::Scene && sceneStarts) {
            sceneStarts->append(page - 2 + double(line) / linesPerPage);
        }
        for (const QString &text : rows) {
            if (line >= linesPerPage) {
                next();
            }
            row(e, in, text, line);
            ++line;
        }
    }
    return page < 2 ? 0. : page - 2 + double(line) / linesPerPage;
}

// A4, 12 pt Courier-like, 1 inch top and bottom: lines on a page
constexpr int linesPerPage = int((11.69 * 72 - 2 * 72) / 12);

bool writePdf(const Script &s, const QString &out)
{
    QPdfWriter pdf(out);
    pdf.setPageSize(QPageSize(QPageSize::A4));
    pdf.setPageMargins(QMarginsF(0, 0, 0, 0));
    pdf.setResolution(72);              // painter units = points
    pdf.setTitle(s.title);
    pdf.setCreator(T(QStringLiteral("Печатная машинка")));
    QPainter p(&pdf);
    if (!p.isActive()) {
        return false;
    }
    QFont font(fontFamily());
    font.setPointSizeF(12);
    QFont bold = font;
    bold.setBold(true);
    p.setFont(font);
    const double inch = 72, lineH = 12, top = 1.0 * inch, bottom = 11.69 * inch - 1.0 * inch;

    // title page
    p.setFont(bold);
    const double pageW = 8.27 * inch;
    auto centered = [&](const QString &t, double y) {
        p.drawText(QRectF(0, y, pageW, lineH * 2), Qt::AlignHCenter | Qt::AlignTop, t);
    };
    centered(s.title.toUpper(), 3.6 * inch);
    p.setFont(font);
    if (!s.author.isEmpty()) {
        centered(T(QStringLiteral("автор")), 3.6 * inch + 4 * lineH);
        centered(s.author, 3.6 * inch + 6 * lineH);
    }
    if (!s.draft.isEmpty()) {
        p.drawText(QPointF(1.5 * inch, bottom), s.draft);
    }

    auto newPage = [&](int page) {
        pdf.newPage();
        p.setFont(font);
        p.drawText(QRectF(0, 0.5 * inch, 7.5 * inch, lineH * 2), Qt::AlignRight | Qt::AlignTop, QString::number(page - 1) + QLatin1Char('.'));
    };
    auto row = [&](const Element &e, const Indent &in, const QString &text, int line) {
        p.setFont(e.kind == Kind::Scene ? bold : font);
        const double y = top + line * lineH;
        const Qt::Alignment align = e.kind == Kind::Transition ? Qt::AlignRight : Qt::AlignLeft;
        p.drawText(QRectF(in.left * inch, y, in.width * inch, lineH * 2), align | Qt::AlignTop, text);
    };
    layout(s, linesPerPage, row, newPage);
    return p.end();
}

QString xml(QString s)
{
    return s.replace(QLatin1Char('&'), QLatin1String("&amp;")).replace(QLatin1Char('<'), QLatin1String("&lt;")).replace(QLatin1Char('>'), QLatin1String("&gt;"));
}

// Minimal ZIP writer (stored entries) for DOCX and EPUB
quint32 crc32(const QByteArray &data)
{
    static quint32 table[256];
    static bool ready = false;
    if (!ready) {
        for (quint32 i = 0; i < 256; ++i) {
            quint32 c = i;
            for (int k = 0; k < 8; ++k) {
                c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
            }
            table[i] = c;
        }
        ready = true;
    }
    quint32 c = 0xFFFFFFFFu;
    for (const char ch : data) {
        c = table[(c ^ quint8(ch)) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFFu;
}

bool writeZip(const QString &out, const QList<QPair<QString, QByteArray>> &entries)
{
    QFile f(out);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }
    auto le16 = [](QByteArray &b, quint16 v) { b.append(char(v & 0xFF)); b.append(char(v >> 8)); };
    auto le32 = [&](QByteArray &b, quint32 v) { le16(b, v & 0xFFFF); le16(b, v >> 16); };
    QByteArray central;
    quint32 offset = 0;
    for (const auto &[name, data] : entries) {
        const QByteArray n = name.toUtf8();
        const quint32 crc = crc32(data);
        QByteArray h;
        le32(h, 0x04034b50); le16(h, 20); le16(h, 0x0800); le16(h, 0); le16(h, 0); le16(h, 0x21);
        le32(h, crc); le32(h, data.size()); le32(h, data.size()); le16(h, n.size()); le16(h, 0);
        h += n;
        f.write(h);
        f.write(data);
        QByteArray c;
        le32(c, 0x02014b50); le16(c, 20); le16(c, 20); le16(c, 0x0800); le16(c, 0); le16(c, 0); le16(c, 0x21);
        le32(c, crc); le32(c, data.size()); le32(c, data.size()); le16(c, n.size()); le16(c, 0); le16(c, 0);
        le16(c, 0); le16(c, 0); le32(c, 0); le32(c, offset);
        c += n;
        central += c;
        offset += h.size() + data.size();
    }
    QByteArray end;
    le32(end, 0x06054b50); le16(end, 0); le16(end, 0); le16(end, entries.size()); le16(end, entries.size());
    le32(end, central.size()); le32(end, offset); le16(end, 0);
    f.write(central);
    f.write(end);
    return true;
}

bool writeDocx(const Script &s, const QString &out)
{
    // twips: 1 in = 1440; the page has 1.5 in on the left and 1 in on the right
    auto ind = [](Kind k) {
        const Indent in = indentOf(k);
        const int left = int((in.left - 1.5) * 1440);
        const int right = int((7.5 - in.left - in.width) * 1440);
        return QStringLiteral("<w:ind w:left=\"%1\" w:right=\"%2\"/>").arg(left).arg(std::max(0, right));
    };
    auto style = [&](const QString &id, const QString &name, Kind k, const QString &extra) {
        const bool blank = indentOf(k).blankBefore;
        return QStringLiteral("<w:style w:type=\"paragraph\" w:customStyle=\"1\" w:styleId=\"%1\"><w:name w:val=\"%2\"/>"
                              "<w:basedOn w:val=\"Normal\"/><w:pPr>%3<w:spacing w:before=\"%4\" w:after=\"0\"/>%5</w:pPr></w:style>")
            .arg(id, name, k == Kind::Scene || k == Kind::Character ? QStringLiteral("<w:keepNext/>") : QString())
            .arg(blank ? 240 : 0)
            .arg(ind(k) + extra);
    };
    const QString styles = QStringLiteral(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
        "<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\" w:cs=\"Courier New\" w:eastAsia=\"Courier New\"/>"
        "<w:sz w:val=\"24\"/><w:szCs w:val=\"24\"/><w:lang w:val=\"ru-RU\"/></w:rPr></w:rPrDefault>"
        "<w:pPrDefault><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"exact\"/></w:pPr></w:pPrDefault></w:docDefaults>"
        "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style>"
        "<w:style w:type=\"paragraph\" w:styleId=\"Title\"><w:name w:val=\"Title\"/><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:rPr><w:b/></w:rPr></w:style>")
        + style(QStringLiteral("SceneHeading"), QStringLiteral("Scene Heading"), Kind::Scene, QString()).replace(QLatin1String("</w:pPr>"), QLatin1String("</w:pPr><w:rPr><w:b/><w:caps/></w:rPr>"))
        + style(QStringLiteral("Action"), QStringLiteral("Action"), Kind::Action, QString())
        + style(QStringLiteral("Character"), QStringLiteral("Character"), Kind::Character, QString()).replace(QLatin1String("</w:pPr>"), QLatin1String("</w:pPr><w:rPr><w:caps/></w:rPr>"))
        + style(QStringLiteral("Parenthetical"), QStringLiteral("Parenthetical"), Kind::Parenthetical, QString())
        + style(QStringLiteral("Dialogue"), QStringLiteral("Dialogue"), Kind::Dialogue, QString())
        + style(QStringLiteral("Transition"), QStringLiteral("Transition"), Kind::Transition, QStringLiteral("<w:jc w:val=\"right\"/>"))
        + QStringLiteral("</w:styles>");

    auto para = [](const QString &styleId, const QString &text, const QString &extra = QString()) {
        return QStringLiteral("<w:p><w:pPr><w:pStyle w:val=\"%1\"/>%2</w:pPr><w:r><w:t xml:space=\"preserve\">%3</w:t></w:r></w:p>").arg(styleId, extra, xml(text));
    };
    QString body;
    body += para(QStringLiteral("Title"), s.title.toUpper(), QStringLiteral("<w:spacing w:before=\"5040\"/>"));
    if (!s.author.isEmpty()) {
        body += para(QStringLiteral("Title"), T(QStringLiteral("автор")), QStringLiteral("<w:spacing w:before=\"720\"/>"));
        body += para(QStringLiteral("Title"), s.author, QStringLiteral("<w:spacing w:before=\"240\"/>"));
    }
    if (!s.draft.isEmpty()) {
        body += para(QStringLiteral("Normal"), s.draft, QStringLiteral("<w:spacing w:before=\"5760\"/>"));
    }
    body += QStringLiteral("<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>");
    for (const Element &e : s.body) {
        static const QHash<Kind, QString> ids{{Kind::Scene, QStringLiteral("SceneHeading")}, {Kind::Action, QStringLiteral("Action")},
                                              {Kind::Character, QStringLiteral("Character")}, {Kind::Parenthetical, QStringLiteral("Parenthetical")},
                                              {Kind::Dialogue, QStringLiteral("Dialogue")}, {Kind::Transition, QStringLiteral("Transition")}};
        body += para(ids.value(e.kind), e.text);
    }
    const QString document = QStringLiteral(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
        "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><w:body>%1"
        "<w:sectPr><w:headerReference w:type=\"default\" r:id=\"rIdHeader\"/><w:pgSz w:w=\"11906\" w:h=\"16838\"/>"
        "<w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"2160\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>"
        "<w:pgNumType w:start=\"0\"/><w:titlePg/></w:sectPr></w:body></w:document>").arg(body);
    const QString header = QStringLiteral(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<w:hdr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:p><w:pPr><w:jc w:val=\"right\"/></w:pPr>"
        "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText xml:space=\"preserve\"> PAGE </w:instrText></w:r>"
        "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r><w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType=\"end\"/></w:r>"
        "<w:r><w:t>.</w:t></w:r></w:p></w:hdr>");
    const QByteArray types = QByteArrayLiteral(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>"
        "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>"
        "<Override PartName=\"/word/header1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml\"/>"
        "</Types>");
    const QByteArray rels = QByteArrayLiteral(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>"
        "</Relationships>");
    const QByteArray docRels = QByteArrayLiteral(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        "<Relationship Id=\"rIdStyles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        "<Relationship Id=\"rIdHeader\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"header1.xml\"/>"
        "</Relationships>");
    return writeZip(out, {{QStringLiteral("[Content_Types].xml"), types},
                          {QStringLiteral("_rels/.rels"), rels},
                          {QStringLiteral("word/_rels/document.xml.rels"), docRels},
                          {QStringLiteral("word/document.xml"), document.toUtf8()},
                          {QStringLiteral("word/styles.xml"), styles.toUtf8()},
                          {QStringLiteral("word/header1.xml"), header.toUtf8()}});
}

bool writeEpub(const Script &s, const QString &out)
{
    const QString uid = QStringLiteral("urn:typewriter:") + QString::number(qHash(s.title + s.author));
    QString body;
    QStringList nav;
    int scene = 0;
    static const QHash<Kind, QString> cls{{Kind::Scene, QStringLiteral("scene")}, {Kind::Action, QStringLiteral("action")},
                                          {Kind::Character, QStringLiteral("character")}, {Kind::Parenthetical, QStringLiteral("paren")},
                                          {Kind::Dialogue, QStringLiteral("dialogue")}, {Kind::Transition, QStringLiteral("transition")}};
    for (const Element &e : s.body) {
        if (e.kind == Kind::Scene) {
            ++scene;
            body += QStringLiteral("<h2 class=\"scene\" id=\"s%1\">%2</h2>\n").arg(scene).arg(xml(e.text));
            nav += QStringLiteral("<li><a href=\"text.xhtml#s%1\">%2</a></li>").arg(scene).arg(xml(e.text));
        } else {
            body += QStringLiteral("<p class=\"%1\">%2</p>\n").arg(cls.value(e.kind), xml(e.text));
        }
    }
    const QString head = QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE html>\n"
                                        "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" lang=\"ru\" xml:lang=\"ru\">"
                                        "<head><meta charset=\"utf-8\"/><title>%1</title><link rel=\"stylesheet\" href=\"style.css\"/></head><body>")
                             .arg(xml(s.title));
    const QString text = head + QStringLiteral("<section class=\"titlepage\"><h1>%1</h1><p class=\"author\">%2</p><p class=\"draft\">%3</p></section>\n")
                                    .arg(xml(s.title.toUpper()), xml(s.author), xml(s.draft))
                         + body + QStringLiteral("</body></html>");
    const QString navDoc = head + QStringLiteral("<nav epub:type=\"toc\"><h1>Сцены</h1><ol><li><a href=\"text.xhtml\">%1</a></li>%2</ol></nav></body></html>")
                                      .arg(xml(s.title), nav.join(QString()));
    const QString css = QStringLiteral(
        "body { font-family: \"Courier New\", Cousine, monospace; line-height: 1.2; margin: 0 5%; }\n"
        ".titlepage { text-align: center; margin: 30% 0; page-break-after: always; }\n"
        "h1 { font-size: 1.2em; } .author { margin-top: 2em; } .draft { margin-top: 4em; font-size: 0.9em; }\n"
        "h2.scene { font-size: 1em; font-weight: bold; text-transform: uppercase; margin: 1.5em 0 0.6em; page-break-after: avoid; }\n"
        "p { margin: 0; } .action { margin: 0.6em 0; }\n"
        ".character { margin: 1em 0 0 37%; text-transform: uppercase; page-break-after: avoid; }\n"
        ".paren { margin-left: 27%; margin-right: 30%; }\n"
        ".dialogue { margin-left: 17%; margin-right: 25%; }\n"
        ".transition { text-align: right; margin: 1em 0; }\n");
    const QString opf = QStringLiteral(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"uid\" xml:lang=\"ru\">"
        "<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:identifier id=\"uid\">%1</dc:identifier>"
        "<dc:title>%2</dc:title><dc:creator>%3</dc:creator><dc:language>ru</dc:language>"
        "<meta property=\"dcterms:modified\">%4</meta></metadata>"
        "<manifest><item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>"
        "<item id=\"text\" href=\"text.xhtml\" media-type=\"application/xhtml+xml\"/>"
        "<item id=\"css\" href=\"style.css\" media-type=\"text/css\"/></manifest>"
        "<spine><itemref idref=\"text\"/></spine></package>")
                            .arg(uid, xml(s.title), xml(s.author.isEmpty() ? QStringLiteral("—") : s.author),
                                 QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyy-MM-ddTHH:mm:ssZ")));
    const QByteArray container = QByteArrayLiteral(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">"
        "<rootfiles><rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>");
    return writeZip(out, {{QStringLiteral("mimetype"), QByteArrayLiteral("application/epub+zip")},
                          {QStringLiteral("META-INF/container.xml"), container},
                          {QStringLiteral("OEBPS/content.opf"), opf.toUtf8()},
                          {QStringLiteral("OEBPS/nav.xhtml"), navDoc.toUtf8()},
                          {QStringLiteral("OEBPS/text.xhtml"), text.toUtf8()},
                          {QStringLiteral("OEBPS/style.css"), css.toUtf8()}});
}

} // namespace typewriter

int typewriterStatsCommand()
{
    std::fputs(QJsonDocument(typewriter::stats()).toJson(QJsonDocument::Compact).constData(), stdout);
    std::fputc('\n', stdout);
    return 0;
}

int typewriterWordsOn(const QDate &day)
{
    return day == QDate::currentDate() ? typewriter::wordsToday() : typewriter::wordsOn(day);
}

QJsonObject typewriterSummary()
{
    return typewriter::stats();
}

// Running time: a screenplay page is about a minute of screen time. Pages come from the same
// layout as the PDF; every scene gets its share.
int typewriterRuntimeCommand(const QString &file)
{
    QFile in(file);
    if (!in.open(QIODevice::ReadOnly)) {
        std::fprintf(stderr, "typewriter-runtime: cannot read %s\n", qPrintable(file));
        return 1;
    }
    const typewriter::Script script = typewriter::parse(QString::fromUtf8(in.readAll()));
    QList<double> starts;
    const double pages = typewriter::layout(
        script, typewriter::linesPerPage, [](const auto &, const auto &, const auto &, int) {}, [](int) {}, &starts);
    QJsonArray scenes;
    int n = 0;
    for (const typewriter::Element &e : script.body) {
        if (e.kind != typewriter::Kind::Scene) {
            continue;
        }
        const double length = (n + 1 < starts.size() ? starts[n + 1] : pages) - starts[n];
        scenes.append(QJsonObject{{QStringLiteral("title"), e.text}, {QStringLiteral("seconds"), qRound(length * 60)}});
        ++n;
    }
    const QJsonObject result{{QStringLiteral("pages"), qRound(pages * 10) / 10.},
                             {QStringLiteral("seconds"), qRound(pages * 60)},
                             {QStringLiteral("scenes"), scenes}};
    std::fputs(QJsonDocument(result).toJson(QJsonDocument::Compact).constData(), stdout);
    std::fputc('\n', stdout);
    return 0;
}

int typewriterExportCommand(const QString &file, const QString &format, QString out)
{
    QFile in(file);
    if (!in.open(QIODevice::ReadOnly)) {
        std::fprintf(stderr, "typewriter-export: cannot read %s\n", qPrintable(file));
        return 1;
    }
    const typewriter::Script script = typewriter::parse(QString::fromUtf8(in.readAll()));
    if (out.isEmpty()) {
        const QString dir = QFileInfo(file).absolutePath() + (uiRussian() ? QStringLiteral("/Экспорт") : QStringLiteral("/Export"));
        QDir().mkpath(dir);
        out = dir + QLatin1Char('/') + QFileInfo(file).completeBaseName() + QLatin1Char('.') + format;
    }
    bool ok = false;
    if (format == QLatin1String("pdf")) {
        ok = typewriter::writePdf(script, out);
    } else if (format == QLatin1String("docx")) {
        ok = typewriter::writeDocx(script, out);
    } else if (format == QLatin1String("epub")) {
        ok = typewriter::writeEpub(script, out);
    } else {
        std::fputs("typewriter-export: format is pdf, docx or epub\n", stderr);
        return 2;
    }
    if (!ok) {
        std::fprintf(stderr, "typewriter-export: cannot write %s\n", qPrintable(out));
        return 1;
    }
    std::fputs(qPrintable(out + QLatin1Char('\n')), stdout);
    return 0;
}
