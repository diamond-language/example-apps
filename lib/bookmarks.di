# Bookmark reads and writes. A bookmark is private to its owner: every lookup
# is scoped to the signed-in user, so another user's id is simply not found.
def page_size() = 20

def url_format() = "^https?://[^\\s/]+\\S*$"

class Bookmarks
  # " ruby web-dev " from "Ruby, web-dev ruby": lowercased, deduplicated, invalid
  # names dropped, at most ten. The surrounding spaces make `LIKE '% tag %'` exact.
  def self.normalize_tags(text) -> String
    if text == nil then return " " end
    seen = []
    text.downcase().split(Patterns.tag_separator_re()).each() do |tag|
      if Patterns.tag_format_re().match?(tag) && !seen.include?(tag) && seen.length() < 10
        seen.push(tag)
      end
    end
    if seen.length() == 0 then " " else " " + seen.join(" ") + " " end
  end

  # ["ruby", "web-dev"] from the stored form.
  def self.tag_list(stored) -> Array
    stored.strip().split(" ").select() do |tag| tag != "" end
  end

  # The permitted attributes from a form: tags normalized, a blank title taken from the URL.
  def self.attributes(params)
    url = if params["url"] == nil then "" else params["url"].strip() end
    title = if params["title"] == nil then "" else params["title"].strip() end
    if title == "" then title = url end
    note = if params["note"] == nil then "" else params["note"].strip() end
    {"url": url, "title": title, "note": note, "tags": Bookmarks.normalize_tags(params["tags"])}
  end

  def self.changeset(schemas, bookmark, attrs)
    Mjolnir::Changeset.cast(schemas.bookmarks(), bookmark, attrs, ["url", "title", "note", "tags"])
      .validate_required(["url", "title"])
      .validate_length("url", 1, 2000)
      .validate_format("url", url_format(), message: "must start with http:// or https://")
      .validate_length("title", 1, 300)
      .validate_length("note", 0, 5000)
  end

  def self.create(repo, schemas, user, params)
    attrs = Bookmarks.attributes(params)
    changeset = Bookmarks.changeset(schemas, nil, attrs).put_change("user_id", user.id())
    result = repo.insert(changeset)
    case result
    when Mjolnir::Ok then result
    when Mjolnir::Err then Mjolnir::Err.new(Changesets.messages(result.error()))
    end
  end

  def self.update(repo, schemas, bookmark, params)
    result = repo.update(Bookmarks.changeset(schemas, bookmark, Bookmarks.attributes(params)))
    case result
    when Mjolnir::Ok then result
    when Mjolnir::Err then Mjolnir::Err.new(Changesets.messages(result.error()))
    end
  end

  # The user's bookmark with this id, or nil.
  def self.find(repo, schemas, user, id)
    repo.get_by(schemas.bookmarks(), {"id": id.to_i(), "user_id": user.id()})
  end

  def self.delete(repo, schemas, bookmark)
    repo.delete(schemas.bookmarks(), bookmark.id())
  end

  # The user's bookmarks matching the search text and tag, as a Mjolnir query.
  def self.matching(schemas, user, q, tag)
    bookmarks = schemas.bookmarks()
    query = bookmarks.query().where({"user_id": user.id()})
    if q != ""
      pattern = "%#{q}%"
      query = query.where(bookmarks.column("title").like(pattern)
        .or_else(bookmarks.column("url").like(pattern))
        .or_else(bookmarks.column("note").like(pattern))
        .or_else(bookmarks.column("tags").like(pattern)))
    end
    if tag != ""
      query = query.where(bookmarks.column("tags").like("% #{tag} %"))
    end
    query
  end

  # One page of the list: {"items", "total", "page", "pages", "q", "tag"}.
  def self.list(repo, schemas, user, params)
    q = if params["q"] == nil then "" else params["q"].strip() end
    tag = if params["tag"] == nil then "" else params["tag"].strip().downcase() end
    query = Bookmarks.matching(schemas, user, q, tag)
    total = repo.count(query)
    paged = paginate(params["page"], total, page_size())
    items = repo.all(query.order_by("created_at", :desc).order_by("id", :desc).limit(page_size()).offset(paged[2]))
    {"items": items, "total": total, "page": paged[0], "pages": paged[1], "q": q, "tag": tag}
  end

  # [[tag, count], ...] for the sidebar, most used first, then alphabetical.
  def self.tag_counts(repo, schemas, user) -> Array
    counts = {}
    repo.all(schemas.bookmarks().query().where({"user_id": user.id()})).each() do |bookmark|
      Bookmarks.tag_list(bookmark.tags()).each() do |tag|
        counts[tag] = if counts[tag] == nil then 1 else counts[tag] + 1 end
      end
    end
    pairs = counts.keys().map() do |tag| [tag, counts[tag]] end
    pairs.sort_by() do |pair| [-pair[1], pair[0]] end
  end
end
