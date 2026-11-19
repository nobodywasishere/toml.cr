require "json"
require "../../src/toml"

def write_tag(json : JSON::Builder, type : String, value : String) : Nil
  json.object do
    json.field "type", type
    json.field "value", value
  end
end

def write_decoded(json : JSON::Builder, value : TOML::Any::Type) : Nil
  case value
  when Hash
    json.object do
      value.each do |key, item|
        json.field(key) { write_decoded(json, item.raw) }
      end
    end
  when Array
    json.array { value.each { |item| write_decoded(json, item.raw) } }
  when Bool
    write_tag(json, "bool", value.to_s)
  when Int64
    write_tag(json, "integer", value.to_s)
  when Float64
    write_tag(json, "float", format_float(value))
  when String
    write_tag(json, "string", value)
  when TOML::LocalDate
    write_tag(json, "date-local", value.to_s)
  when TOML::LocalTime
    write_tag(json, "time-local", value.to_s)
  when TOML::LocalDateTime
    write_tag(json, "datetime-local", value.to_s)
  when Time
    write_tag(json, "datetime", value.to_rfc3339(fraction_digits: 9))
  end
end

def format_float(value : Float64) : String
  return "nan" if value.nan?
  return value < 0 ? "-inf" : "inf" if value.infinite?
  value.to_s
end

begin
  parsed = TOML.parse(STDIN)
  JSON.build(STDOUT) { |json| write_decoded(json, parsed) }
  STDOUT.puts
rescue error : TOML::ParseException
  STDERR.puts error.message
  exit 1
rescue error
  STDERR.puts error.inspect_with_backtrace
  exit 2
end
