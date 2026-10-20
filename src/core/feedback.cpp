#include "core/feedback.h"
#include "core/chat.h"
#include "miniz.h"
#include <algorithm>
#include <stdexcept>

namespace isaac::feedback {
namespace {
constexpr std::uint32_t localHeader = 0x04034b50, centralHeader = 0x02014b50,
                        endOfDirectory = 0x06054b50;
constexpr std::uint16_t zipVersion = 20, utf8Names = 0x0800, stored = 0, deflated = 8;
constexpr int deflateLevel = 6;

void put16(std::vector<std::uint8_t>& out, std::uint16_t value) {
    out.push_back(static_cast<std::uint8_t>(value));
    out.push_back(static_cast<std::uint8_t>(value >> 8));
}
void put32(std::vector<std::uint8_t>& out, std::uint32_t value) {
    put16(out, static_cast<std::uint16_t>(value));
    put16(out, static_cast<std::uint16_t>(value >> 16));
}
std::vector<std::uint8_t> deflateRaw(std::span<const std::uint8_t> input) {
    std::size_t length = 0;
    const auto flags =
        tdefl_create_comp_flags_from_zip_params(deflateLevel, -MZ_DEFAULT_WINDOW_BITS, 0);
    auto* output = static_cast<std::uint8_t*>(
        tdefl_compress_mem_to_heap(input.data(), input.size(), &length, flags));
    if (!output)
        throw std::runtime_error("Cannot compress feedback file");
    std::vector<std::uint8_t> result(output, output + length);
    mz_free(output);
    return result;
}
char lower(char c) {
    return c >= 'A' && c <= 'Z' ? static_cast<char>(c - 'A' + 'a') : c;
}
bool separator(char c) {
    return c == '\\' || c == '/';
}
// Length of the profile path at text[at], treating separators as equal and
// accepting a doubled backslash as written by escaped log fields.
std::size_t profileMatch(std::string_view text, std::size_t at, std::string_view profile) {
    std::size_t i = at;
    for (const auto expected : profile) {
        if (i >= text.size())
            return 0;
        if (separator(expected)) {
            if (!separator(text[i]))
                return 0;
            if (text[i] == '\\' && i + 1 < text.size() && text[i + 1] == '\\')
                ++i;
        } else if (lower(text[i]) != lower(expected))
            return 0;
        ++i;
    }
    // Do not redact a prefix of a longer directory name.
    if (i < text.size() && !separator(text[i]) && text[i] != '"' && text[i] != '\'' &&
        text[i] != ' ' && text[i] != '\r' && text[i] != '\n')
        return 0;
    return i - at;
}
std::size_t scalarLength(std::string_view text, std::size_t at) {
    const auto lead = static_cast<unsigned char>(text[at]);
    const std::size_t length = lead < 0x80 ? 1 : lead < 0xe0 ? 2 : lead < 0xf0 ? 3 : 4;
    if (at + length > text.size())
        return 0;
    return chat::boundaries(text.substr(at, length)) ? length : 0;
}
void appendUtf8(std::string& out, std::uint32_t value) {
    if (value < 0x80) {
        out += static_cast<char>(value);
    } else if (value < 0x800) {
        out += static_cast<char>(0xc0 | (value >> 6));
        out += static_cast<char>(0x80 | (value & 0x3f));
    } else if (value < 0x10000) {
        out += static_cast<char>(0xe0 | (value >> 12));
        out += static_cast<char>(0x80 | ((value >> 6) & 0x3f));
        out += static_cast<char>(0x80 | (value & 0x3f));
    } else {
        out += static_cast<char>(0xf0 | (value >> 18));
        out += static_cast<char>(0x80 | ((value >> 12) & 0x3f));
        out += static_cast<char>(0x80 | ((value >> 6) & 0x3f));
        out += static_cast<char>(0x80 | (value & 0x3f));
    }
}
std::optional<std::uint32_t> hex4(std::string_view text, std::size_t at) {
    if (at + 4 > text.size())
        return {};
    std::uint32_t value = 0;
    for (std::size_t i = at; i < at + 4; ++i) {
        const auto c = lower(text[i]);
        if (c >= '0' && c <= '9')
            value = value * 16 + static_cast<std::uint32_t>(c - '0');
        else if (c >= 'a' && c <= 'f')
            value = value * 16 + static_cast<std::uint32_t>(c - 'a' + 10);
        else
            return {};
    }
    return value;
}
bool digits(std::string_view text) {
    return !text.empty() &&
           std::all_of(text.begin(), text.end(), [](char c) { return c >= '0' && c <= '9'; });
}
} // namespace

bool safeName(std::string_view name) {
    if (name.empty() || name.front() == '/' || name.back() == '/' || name.size() > 0xffff)
        return false;
    for (std::size_t begin = 0; begin <= name.size();) {
        const auto end = std::min(name.find('/', begin), name.size());
        const auto part = name.substr(begin, end - begin);
        if (part.empty() || part == "." || part == ".." ||
            part.find_first_of(std::string_view(":\\\0", 3)) != part.npos)
            return false;
        begin = end + 1;
    }
    return static_cast<bool>(chat::boundaries(name));
}

std::vector<std::uint8_t> zip(std::span<const File> files, std::uint16_t dosTime,
                              std::uint16_t dosDate) {
    if (files.size() > 0xffff)
        throw std::runtime_error("Too many feedback files");
    std::vector<std::uint8_t> out, directory;
    for (const auto& file : files) {
        if (!safeName(file.name) || file.data.size() > 0xffffffffu)
            throw std::runtime_error("Invalid feedback file");
        const auto crc =
            static_cast<std::uint32_t>(mz_crc32(MZ_CRC32_INIT, file.data.data(), file.data.size()));
        auto body = file.data.empty() ? std::vector<std::uint8_t>{} : deflateRaw(file.data);
        auto method = deflated;
        if (file.data.empty() || body.size() >= file.data.size()) {
            body = file.data;
            method = stored;
        }
        if (out.size() > 0xffffffffu)
            throw std::runtime_error("Feedback archive too large");
        const auto offset = static_cast<std::uint32_t>(out.size());
        const bool ascii = std::all_of(file.name.begin(), file.name.end(),
                                       [](char c) { return static_cast<unsigned char>(c) < 0x80; });
        const std::uint16_t flags = ascii ? 0 : utf8Names;
        const auto nameLength = static_cast<std::uint16_t>(file.name.size());
        for (auto* header : {&out, &directory}) {
            const bool central = header == &directory;
            put32(*header, central ? centralHeader : localHeader);
            if (central)
                put16(*header, zipVersion);
            put16(*header, zipVersion);
            put16(*header, flags);
            put16(*header, method);
            put16(*header, dosTime);
            put16(*header, dosDate);
            put32(*header, crc);
            put32(*header, static_cast<std::uint32_t>(body.size()));
            put32(*header, static_cast<std::uint32_t>(file.data.size()));
            put16(*header, nameLength);
            put16(*header, 0);
            if (central) {
                put16(*header, 0); // comment
                put16(*header, 0); // disk
                put16(*header, 0); // internal attributes
                put32(*header, 0); // external attributes
                put32(*header, offset);
            }
            header->insert(header->end(), file.name.begin(), file.name.end());
        }
        out.insert(out.end(), body.begin(), body.end());
    }
    if (out.size() > 0xffffffffu || directory.size() > 0xffffffffu)
        throw std::runtime_error("Feedback archive too large");
    const auto directoryOffset = static_cast<std::uint32_t>(out.size());
    const auto count = static_cast<std::uint16_t>(files.size());
    out.insert(out.end(), directory.begin(), directory.end());
    put32(out, endOfDirectory);
    put16(out, 0);
    put16(out, 0);
    put16(out, count);
    put16(out, count);
    put32(out, static_cast<std::uint32_t>(directory.size()));
    put32(out, directoryOffset);
    put16(out, 0);
    return out;
}

std::string tail(std::string_view text, std::size_t limit, std::size_t omitted) {
    auto begin = text.size() > limit ? text.size() - limit : 0;
    if (!begin && !omitted)
        return std::string(text);
    if (const auto line = text.find('\n', begin); line != text.npos && line + 1 < text.size())
        begin = line + 1;
    while (begin < text.size() && (static_cast<unsigned char>(text[begin]) & 0xc0) == 0x80)
        ++begin;
    return "[isaac-lan feedback: dropped " + std::to_string(omitted + begin) + " older bytes]\n" +
           std::string(text.substr(begin));
}

std::string redact(std::string_view text, std::span<const std::string> profiles) {
    constexpr std::string_view steam = "userdata";
    std::string out;
    out.reserve(text.size());
    for (std::size_t i = 0; i < text.size();) {
        std::size_t matched = 0;
        for (const auto& profile : profiles)
            if (profile.size() >= 4 && (matched = profileMatch(text, i, profile)))
                break;
        if (matched) {
            out += redactedProfile;
            i += matched;
            continue;
        }
        if (i + steam.size() + 1 < text.size() && lower(text[i]) == 'u' &&
            std::equal(steam.begin(), steam.end(), text.begin() + static_cast<std::ptrdiff_t>(i),
                       [](char a, char b) { return lower(a) == lower(b); }) &&
            separator(text[i + steam.size()])) {
            auto end = i + steam.size() + 1;
            while (end < text.size() && text[end] >= '0' && text[end] <= '9')
                ++end;
            if (end > i + steam.size() + 1) {
                out += text.substr(i, steam.size() + 1);
                out += "<steamid>";
                i = end;
                continue;
            }
        }
        out += text[i++];
    }
    return out;
}

bool launchName(std::string_view name) {
    // YYYYMMDD-HHMMSS-mmm-p<pid>[-<suffix>], as created by the runtime log.
    if (name.size() < 21 || !digits(name.substr(0, 8)) || name[8] != '-' ||
        !digits(name.substr(9, 6)) || name[15] != '-' || !digits(name.substr(16, 3)) ||
        name.substr(19, 2) != "-p")
        return false;
    const auto rest = name.substr(21);
    const auto dash = rest.find('-');
    return digits(rest.substr(0, dash)) && (dash == rest.npos || digits(rest.substr(dash + 1)));
}

std::vector<std::string> launches(std::vector<std::string> names, std::string_view current) {
    std::erase_if(names,
                  [&](const std::string& name) { return !launchName(name) || name >= current; });
    std::sort(names.begin(), names.end());
    std::vector<std::string> result;
    const auto previous = std::min(names.size(), collectedLaunches - 1);
    result.assign(names.end() - static_cast<std::ptrdiff_t>(previous), names.end());
    if (launchName(current))
        result.emplace_back(current);
    return result;
}

bool validDescription(std::string_view text) {
    return text.size() <= maxDescriptionBytes && chat::boundaries(text) &&
           text.find_first_not_of(" \t\r\n") != text.npos;
}

bool validEndpoint(std::string_view endpoint) {
    if (endpoint.size() > maxEndpointBytes ||
        endpoint.find_first_of(" \t\r\n\"'<>\\") != endpoint.npos || !chat::boundaries(endpoint))
        return false;
    // Plain HTTP is only for a receiver on this machine, e.g. lab fixtures.
    for (const auto prefix : {"https://", "http://127.0.0.1:", "http://localhost:"}) {
        const std::string_view value(prefix);
        if (endpoint.starts_with(value) && endpoint.size() > value.size() &&
            endpoint.find('/', value.size()) != endpoint.npos)
            return true;
    }
    return false;
}

bool validUuid(std::string_view text) {
    if (text.size() != 36)
        return false;
    for (std::size_t i = 0; i < text.size(); ++i) {
        const auto c = text[i];
        if (i == 8 || i == 13 || i == 18 || i == 23
                ? c != '-'
                : !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')))
            return false;
    }
    return true;
}

bool validId(std::string_view text) {
    constexpr std::string_view crockford = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    return text.size() == 11 && digits(text.substr(0, 6)) && text[6] == '-' &&
           std::all_of(text.begin() + 7, text.end(),
                       [&](char c) { return crockford.find(c) != crockford.npos; });
}

std::string uuid(std::span<const std::uint8_t, 16> random) {
    std::array<std::uint8_t, 16> bytes{};
    std::copy(random.begin(), random.end(), bytes.begin());
    bytes[6] = static_cast<std::uint8_t>((bytes[6] & 0x0f) | 0x40);
    bytes[8] = static_cast<std::uint8_t>((bytes[8] & 0x3f) | 0x80);
    constexpr std::string_view hex = "0123456789abcdef";
    std::string out;
    for (std::size_t i = 0; i < bytes.size(); ++i) {
        if (i == 4 || i == 6 || i == 8 || i == 10)
            out += '-';
        out += hex[bytes[i] >> 4];
        out += hex[bytes[i] & 0xf];
    }
    return out;
}

std::string printable(std::string_view text) {
    std::string out;
    for (std::size_t i = 0; i < text.size();) {
        const auto length = scalarLength(text, i);
        if (length) {
            out += text.substr(i, length);
            i += length;
        } else {
            out += '?';
            ++i;
        }
    }
    std::replace_if(
        out.begin(), out.end(), [](char c) { return c == '\r' || c == '\n' || c == '\t'; }, ' ');
    return out;
}

std::string jsonString(std::string_view text) {
    std::string out = "\"";
    for (const auto c : text) {
        const auto byte = static_cast<unsigned char>(c);
        if (c == '"' || c == '\\') {
            out += '\\';
            out += c;
        } else if (c == '\n') {
            out += "\\n";
        } else if (c == '\r') {
            out += "\\r";
        } else if (c == '\t') {
            out += "\\t";
        } else if (byte < 0x20 || byte == 0x7f) {
            constexpr std::string_view hex = "0123456789abcdef";
            out += "\\u00";
            out += hex[byte >> 4];
            out += hex[byte & 0xf];
        } else {
            out += c;
        }
    }
    return out + "\"";
}

std::string manifest(const Manifest& value) {
    std::string out = "{\"schema\":1,\"description\":" + jsonString(value.description) +
                      ",\"createdAt\":" + jsonString(value.createdAt) +
                      ",\"client\":" + jsonString(value.client) +
                      ",\"game\":" + jsonString(value.game) + ",\"context\":{";
    for (std::size_t i = 0; i < value.context.size(); ++i)
        out += (i ? "," : "") + jsonString(value.context[i].first) + ":" +
               jsonString(value.context[i].second);
    out += "},\"mods\":[";
    for (std::size_t i = 0; i < value.mods.size(); ++i)
        out += (i ? "," : "") + jsonString(value.mods[i]);
    out += "],\"files\":[";
    for (std::size_t i = 0; i < value.files.size(); ++i)
        out += (i ? "," : "") + jsonString(value.files[i]);
    return out + "]}";
}

std::optional<std::string> jsonField(std::string_view json, std::string_view key) {
    const auto quoted = jsonString(key);
    for (auto at = json.find(quoted); at != json.npos; at = json.find(quoted, at + 1)) {
        auto i = json.find_first_not_of(" \t\r\n", at + quoted.size());
        if (i == json.npos || json[i] != ':')
            continue;
        i = json.find_first_not_of(" \t\r\n", i + 1);
        if (i == json.npos || json[i] != '"')
            return {};
        std::string value;
        for (++i; i < json.size(); ++i) {
            const auto c = json[i];
            if (c == '"')
                return value;
            if (c != '\\') {
                value += c;
                continue;
            }
            if (++i >= json.size())
                return {};
            switch (json[i]) {
            case '"':
            case '\\':
            case '/':
                value += json[i];
                break;
            case 'n':
                value += '\n';
                break;
            case 't':
                value += '\t';
                break;
            case 'r':
                value += '\r';
                break;
            case 'b':
                value += '\b';
                break;
            case 'f':
                value += '\f';
                break;
            case 'u': {
                auto code = hex4(json, i + 1);
                if (!code)
                    return {};
                i += 4;
                if (*code >= 0xd800 && *code <= 0xdbff) {
                    const auto low =
                        json.substr(i + 1, 2) == "\\u" ? hex4(json, i + 3) : std::nullopt;
                    if (!low || *low < 0xdc00 || *low > 0xdfff)
                        return {};
                    code = 0x10000 + ((*code - 0xd800) << 10) + (*low - 0xdc00);
                    i += 6;
                } else if (*code >= 0xdc00 && *code <= 0xdfff) {
                    return {};
                }
                appendUtf8(value, *code);
                break;
            }
            default:
                return {};
            }
        }
        return {};
    }
    return {};
}

Outcome interpret(int status, std::string_view body) {
    Outcome result;
    if (status == 200 || status == 201) {
        const auto id = jsonField(body, "id");
        if (id && validId(*id)) {
            result.accepted = true;
            result.id = *id;
            result.text = "反馈已提交，编号 " + *id + "。在群里报告问题时请附上这个编号。";
        } else {
            result.text = "反馈服务器返回了无法识别的结果";
        }
        return result;
    }
    const auto error = jsonField(body, "error").value_or("");
    if (status == 400) {
        result.text = "反馈未被服务器接受：数据格式错误";
    } else if (status == 413) {
        result.text = "反馈未上传：日志过大";
    } else if (status == 429) {
        result.text = "反馈过于频繁，请稍后再试";
    } else if (status == 503 && error == "paused") {
        const auto message = printable(jsonField(body, "message").value_or(""));
        result.text = message.empty() ? "反馈暂时关闭，请稍后再试"
                                      : std::string(chat::boundedOutput(message, 512));
    } else if (status == 503 && (error == "busy" || error == "storage_full")) {
        result.text = "反馈服务器繁忙，请稍后再试";
    } else if (status == 0) {
        result.retry = true;
        result.text = "无法连接反馈服务器";
    } else if (status >= 500) {
        result.retry = true;
        result.text = "反馈服务器暂时不可用（HTTP " + std::to_string(status) + "）";
    } else {
        result.text = "反馈未上传（HTTP " + std::to_string(status) + "）";
    }
    return result;
}
} // namespace isaac::feedback
