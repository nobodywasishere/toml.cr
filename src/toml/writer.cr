# :nodoc:
class TOML::Writer
  private BARE_KEY = /\A[A-Za-z0-9_-]+\z/

  @ancestors = Set(UInt64).new

  def initialize(@io : IO) : Nil
  end

  def write(table : Hash(String, V)) : Nil forall V
    validate_keys(table)
    write_container(table) do
      table.each do |key, value|
        write_entry(key, value)
        @io << '\n'
      end
    end
  end

  private def write_entry(key, value)
    if BARE_KEY.matches?(key)
      @io << key
    else
      write_string(key)
    end
    @io << " = "
    write_value(value)
  end

  private def write_value(value : TOML::Any)
    write_value(value.raw)
  end

  private def write_value(value : Bool)
    @io << value
  end

  private def write_value(value : Int)
    if value < Int64::MIN || value > Int64::MAX
      raise ArgumentError.new("TOML integer is outside the signed 64-bit range")
    end
    @io << value
  end

  private def write_value(value : Float)
    write_value(TOML::Any.new(value))
  end

  private def write_value(value : Float64)
    if value.nan?
      @io << "nan"
    elsif value.infinite?
      @io << (value < 0 ? "-inf" : "inf")
    else
      @io << value
    end
  end

  private def write_value(value : String)
    write_string(value)
  end

  private def write_value(value : Time)
    value.to_rfc3339(@io, fraction_digits: value.nanosecond.zero? ? 0 : 9)
  end

  private def write_value(value : LocalDate | LocalTime | LocalDateTime)
    @io << value
  end

  private def write_value(array : Array)
    write_container(array) do
      @io << '['
      array.each_with_index do |value, index|
        @io << ", " unless index.zero?
        write_value(value)
      end
      @io << ']'
    end
  end

  private def write_value(table : Hash(String, V)) forall V
    validate_keys(table)
    write_container(table) do
      @io << '{'
      table.each_with_index do |(key, value), index|
        @io << ", " unless index.zero?
        write_entry(key, value)
      end
      @io << '}'
    end
  end

  private def validate_keys(table : Hash) : Nil
    return unless table.compare_by_identity?

    keys = Set(String).new
    table.each_key do |key|
      raise ArgumentError.new("Duplicate TOML key #{key.inspect}") unless keys.add?(key)
    end
  end

  private def write_string(value)
    raise ArgumentError.new("TOML strings and keys must be valid UTF-8") unless value.valid_encoding?

    @io << '"'
    value.each_char do |char|
      case char
      when '"'  then @io << "\\\""
      when '\\' then @io << "\\\\"
      when '\b' then @io << "\\b"
      when '\t' then @io << "\\t"
      when '\n' then @io << "\\n"
      when '\f' then @io << "\\f"
      when '\r' then @io << "\\r"
      when '\e' then @io << "\\e"
      when '\u0000'..'\u001f', '\u007f'
        @io.printf("\\u%04X", char.ord)
      else
        @io << char
      end
    end
    @io << '"'
  end

  private def write_container(container : Reference, &)
    raise ArgumentError.new("TOML cannot represent a cyclic table or array") unless @ancestors.add?(container.object_id)
    begin
      yield
    ensure
      @ancestors.delete(container.object_id)
    end
  end
end
