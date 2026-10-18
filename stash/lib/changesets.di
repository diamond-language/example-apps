# Changeset errors as the flat "field message" strings the forms list.
class Changesets
  # "email is required", "username is too short (minimum 3)", ...
  def self.messages(changeset) -> Array
    out = []
    changeset.errors().each() do |field, problems|
      problems.each() do |problem|
        text = problem
        if problem == "can't be blank"
          text = "is required"
        elsif problem.start_with?("should be at least ")
          text = "is too short (minimum #{problem.split(" ")[4]})"
        elsif problem.start_with?("should be at most ")
          text = "is too long (maximum #{problem.split(" ")[4]})"
        end
        out.push("#{field} #{text}")
      end
    end
    out
  end
end
