require "../../src/toml"

struct InkSample
end

struct Palette
  include TOML::Serializable
  getter swatches : Array(InkSample)

  def initialize(@swatches : Array(InkSample)) : Nil
  end
end

{% if flag?(:write_sample) %}
  Palette.new([InkSample.new]).to_toml
{% else %}
  Palette.from_toml("swatches = [{}]")
{% end %}
