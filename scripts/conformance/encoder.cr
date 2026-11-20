require "json"
require "../../src/toml"

def local_date(text : String) : TOML::LocalDate
  year, month, day = text.split('-')
  TOML::LocalDate.new(year.to_i, month.to_i, day.to_i)
end

def local_time(text : String) : TOML::LocalTime
  hour, minute, seconds = text.split(':')
  second, _, fraction = seconds.partition('.')
  nanos = fraction.empty? ? 0 : fraction.byte_slice(0, 9).ljust(9, '0').to_i
  TOML::LocalTime.new(hour.to_i, minute.to_i, second.to_i, nanosecond: nanos)
end

def decode_scalar(tag : String, text : String) : TOML::Any::Type
  case tag
  when "string" then text
  when "bool"
    case text
    when "true"  then true
    when "false" then false
    else              raise ArgumentError.new("invalid boolean")
    end
  when "integer" then text.to_i64
  when "float"
    parse_float(text)
  when "datetime"   then Time.parse_rfc3339(text)
  when "date-local" then local_date(text)
  when "time-local" then local_time(text)
  when "datetime-local"
    date, time = text.split('T', 2)
    TOML::LocalDateTime.new(local_date(date), local_time(time))
  else
    raise ArgumentError.new("unknown tag #{tag.inspect}")
  end
end

def parse_float(text : String) : Float64
  case text
  when "inf", "+inf" then Float64::INFINITY
  when "-inf"        then -Float64::INFINITY
  when "nan", "+nan" then Float64::NAN
  when "-nan"        then -Float64::NAN
  else                    text.to_f64
  end
end

def decode_table(table : Hash(String, JSON::Any)) : TOML::Table
  table.transform_values { |item| decode_value(item) }
end

def decode_value(item : JSON::Any) : TOML::Any
  case value = item.raw
  when Array
    TOML::Any.new(value.map { |entry| decode_value(entry) })
  when Hash
    tag = value["type"]?.try(&.as_s?)
    text = value["value"]?.try(&.as_s?)
    if value.size == 2 && tag && text
      TOML::Any.new(decode_scalar(tag, text))
    else
      TOML::Any.new(decode_table(value))
    end
  else
    raise ArgumentError.new("expected a tagged value, table, or array")
  end
end

begin
  TOML.dump(decode_table(JSON.parse(STDIN).as_h), STDOUT)
rescue error
  STDERR.puts "#{error.class}: #{error.message}"
  exit 1
end
