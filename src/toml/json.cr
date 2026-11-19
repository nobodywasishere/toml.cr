require "../toml"
require "json"

# Direct conversion between JSON and TOML value trees.
module TOML::JSON
  class NullError < SerializableError
    getter path : String

    def initialize(@path : String) : Nil
      super("JSON null at #{path} has no TOML representation")
    end
  end

  def self.from_json(value : ::JSON::Any) : Any
    Conversion.new.from_json(value)
  end

  def self.to_json(value : Any) : ::JSON::Any
    Conversion.new.to_json(value)
  end

  private class Conversion
    @ancestors = Set(UInt64).new
    @path = [] of String | Int32

    def from_json(node : ::JSON::Any) : Any
      case value = node.raw
      in Nil
        location = String.build do |io|
          io << '$'
          @path.each { |part| io << '[' << part.to_json << ']' }
        end
        raise NullError.new(location)
      in Array
        with_container(value) { Any.new(value.map_with_index { |child, i| at(i) { from_json(child) } }) }
      in Hash
        with_container(value) { Any.new(value.to_h { |key, child| {key, at(key) { from_json(child) }} }) }
      in Bool, String, Float64, Int64
        Any.new(value)
      end
    end

    def to_json(node : Any) : ::JSON::Any
      case value = node.raw
      in Array
        with_container(value) { ::JSON::Any.new(value.map { |child| to_json(child) }) }
      in Hash
        with_container(value) { ::JSON::Any.new(value.transform_values { |child| to_json(child) }) }
      in Time
        ::JSON::Any.new(value.to_rfc3339(fraction_digits: value.nanosecond.zero? ? 0 : 9))
      in LocalTime, LocalDateTime, LocalDate
        ::JSON::Any.new(value.to_s)
      in Float64
        raise SerializableError.new("JSON cannot represent a non-finite float") unless value.finite?
        ::JSON::Any.new(value)
      in Bool, String, Int64
        ::JSON::Any.new(value)
      end
    end

    private def at(part : String | Int32, &)
      @path << part
      begin
        yield
      ensure
        @path.pop
      end
    end

    private def with_container(container : Reference, &)
      id = container.object_id
      raise SerializableError.new("Cannot convert a cyclic value tree") unless @ancestors.add?(id)
      begin
        yield
      ensure
        @ancestors.delete(id)
      end
    end
  end
end

struct JSON::Any
  def self.new(reader : TOML::PullParser) : self
    TOML::JSON.to_json(reader.read_value)
  end

  def to_toml(builder : TOML::Builder) : Nil
    builder.scalar(TOML::JSON.from_json(self))
  end
end
