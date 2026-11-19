require "../../src/toml"

struct InvalidIgnoreOption
  include TOML::Serializable

  @[TOML::Field(ignore_deserialize: ENV.has_key?("SKIP_VALUE"))]
  getter value : String = "default"
end

InvalidIgnoreOption.from_toml("")
