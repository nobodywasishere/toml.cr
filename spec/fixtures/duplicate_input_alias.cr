require "../../src/toml"

struct DuplicateInputAlias
  include TOML::Serializable

  WIRE_KEY = "shared"

  @[TOML::Field(key: WIRE_KEY)]
  getter first : String

  @[TOML::Field(key: "shared")]
  getter second : String
end

DuplicateInputAlias.from_toml(%(shared = "value"))
