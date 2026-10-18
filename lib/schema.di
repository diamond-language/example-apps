# Every table as a Mjolnir schema over a plain struct. Entities come back frozen.
struct User(id: Int, email: String, username: String, password_digest: String)
end
def build_user(row) = User.new(row["id"], row["email"], row["username"], row["password_digest"])

struct Session(id: Int, user_id: Int, token: String, csrf_token: String, expires_at: Int)
end
def build_session(row) = Session.new(row["id"], row["user_id"], row["token"], row["csrf_token"], row["expires_at"])

struct Bookmark(id: Int, user_id: Int, url: String, title: String, note: String | Nil, tags: String, created_at: Int, updated_at: Int)
end
def build_bookmark(row) = Bookmark.new(row["id"], row["user_id"], row["url"], row["title"], row["note"], row["tags"], row["created_at"], row["updated_at"])

class Schemas
  def initialize()
    @users = Mjolnir::Schema.new("users", {"id": :int, "email": :string, "username": :string, "password_digest": :string}, build_user)
    @sessions = Mjolnir::Schema.new("sessions", {"id": :int, "user_id": :int, "token": :string, "csrf_token": :string, "expires_at": :int}, build_session)
    @bookmarks = Mjolnir::Schema.new("bookmarks",
      {"id": :int, "user_id": :int, "url": :string, "title": :string, "note": :string, "tags": :string, "created_at": :int, "updated_at": :int},
      build_bookmark, "id", true)
  end

  def users() = @users
  def sessions() = @sessions
  def bookmarks() = @bookmarks
end
