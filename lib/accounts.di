# Account operations: plain functions of the repo and untrusted input, returning
# Mjolnir::Ok(user) or Mjolnir::Err(messages).
def email_format() = "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"
def username_format() = "^[A-Za-z0-9_]+$"

class Accounts
  def self.signup(repo, schemas, params)
    changeset = Mjolnir::Changeset.cast(schemas.users(), nil,
      {"email": params["email"], "username": params["username"]},
      ["email", "username"])
      .validate_required(["email"])
      .validate_length("email", 3, 200)
      .validate_format("email", email_format(), message: "is invalid")
      .unique_constraint("email")
      .validate_required(["username"])
      .validate_length("username", 3, 32)
      .validate_format("username", username_format(), message: "is invalid")
      .unique_constraint("username")
    password = if params["password"] == nil then "" else params["password"] end
    if password.length() < 8
      changeset = changeset.add_error("password", "is too short (minimum 8)")
    end
    if changeset.valid?()
      changeset = changeset.put_change("password_digest", BCrypt.hash(password, 12))
    end
    result = repo.insert(changeset)
    case result
    when Mjolnir::Ok then result
    when Mjolnir::Err then Mjolnir::Err.new(Changesets.messages(result.error()))
    end
  end

  # The user for these credentials, or nil.
  def self.authenticate(repo, schemas, email, password)
    if email == nil || password == nil then return nil end
    user = repo.get_by(schemas.users(), {"email": email})
    if user == nil || !BCrypt.verify(password, user.password_digest()) then return nil end
    user
  end
end
