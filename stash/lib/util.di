# Module-level constants exist only in the main thread, not in a multi-threaded
# server's workers, so shared values are functions; a Regexp is built once per
# worker, on first use.
class Patterns
  def self.safe_query_re()
    if @@safe_query_re == nil then @@safe_query_re = Regexp.new("\\A[A-Za-z0-9_.~-]*\\z") end
    @@safe_query_re
  end

  def self.tag_separator_re()
    if @@tag_separator_re == nil then @@tag_separator_re = Regexp.new("[,\\s]+") end
    @@tag_separator_re
  end

  def self.tag_format_re()
    if @@tag_format_re == nil then @@tag_format_re = Regexp.new("^[a-z0-9][a-z0-9-]{0,39}$") end
    @@tag_format_re
  end

  def self.email_re()
    if @@email_re == nil then @@email_re = Regexp.new("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$") end
    @@email_re
  end

  def self.username_re()
    if @@username_re == nil then @@username_re = Regexp.new("^[A-Za-z0-9_]+$") end
    @@username_re
  end

  def self.web_url_re()
    if @@web_url_re == nil then @@web_url_re = Regexp.new("^https?://[^\\s/]+\\S*$") end
    @@web_url_re
  end
end

# Percent-encoding for query values (unreserved chars pass through, space -> +).
def url_encode(text)
  if Patterns.safe_query_re().match?(text) then return text end
  hex = "0123456789ABCDEF"
  out = StringBuilder.new()
  i = 0
  while i < text.length()
    ch = text.slice(i, 1)
    c = ch.ord()
    if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || ch == "-" || ch == "_" || ch == "." || ch == "~"
      out.append(ch)
    elsif ch == " "
      out.append("+")
    else
      out.append("%" + hex.slice(c / 16, 1) + hex.slice(c % 16, 1))
    end
    i += 1
  end
  out.to_s()
end

# -1 for a non-hex-digit byte.
def hex_digit_value(ch)
  code = ch.ord()
  if code >= 48 && code <= 57
    code - 48
  elsif code >= 97 && code <= 102
    code - 87
  elsif code >= 65 && code <= 70
    code - 55
  else
    -1
  end
end

# application/x-www-form-urlencoded decoding: "+" is a space, "%XX" a byte.
def url_decode(value)
  if value.index_of("%") == nil && value.index_of("+") == nil then return value end
  sb = StringBuilder.new()
  i = 0
  n = value.length()
  while i < n
    ch = value[i]
    if ch == "+"
      sb.append(" ")
      i += 1
    elsif ch == "%" && i + 2 < n
      hi = hex_digit_value(value[i + 1])
      lo = hex_digit_value(value[i + 2])
      if hi >= 0 && lo >= 0
        sb.append(chr(hi * 16 + lo))
        i += 3
      else
        sb.append(ch)
        i += 1
      end
    else
      sb.append(ch)
      i += 1
    end
  end
  sb.to_s()
end

# [page, total_pages, offset] for a raw page param, clamped to the real range.
def paginate(page_param, total, page_size)
  page = if page_param == nil then 1 else page_param.to_i() end
  if page < 1 then page = 1 end
  total_pages = if total == 0 then 1 else ((total - 1) / page_size) + 1 end
  if page > total_pages then page = total_pages end
  [page, total_pages, (page - 1) * page_size]
end

# "/?q=ruby&tag=web&page=2": only the parts that are set, ALREADY HTML-escaped
# (the "&" separator is emitted as &amp;) for an href via <%== %>.
def list_href(q, tag, page)
  out = "/"
  sep = "?"
  if q != nil && q != ""
    out = out + sep + "q=" + url_encode(q)
    sep = "&amp;"
  end
  if tag != nil && tag != ""
    out = out + sep + "tag=" + url_encode(tag)
    sep = "&amp;"
  end
  if page != nil && page > 1 then out = out + sep + "page=" + page.to_s() end
  out
end
